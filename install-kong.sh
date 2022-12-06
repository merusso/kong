#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

if [ -n "${DEBUG:-}" ]; then
    set -x
fi

# Retries a command a configurable number of times with backoff.
#
# The retry count is given by ATTEMPTS (default 5), the initial backoff
# timeout is given by TIMEOUT in seconds (default 1.)
#
# Successive backoffs double the timeout.
function with_backoff {
  local max_attempts=${ATTEMPTS-5}
  local timeout=${TIMEOUT-5}
  local attempt=1
  local exitCode=0

  while (( $attempt < $max_attempts ))
  do
    if "$@"
    then
      return 0
    else
      exitCode=$?
    fi

    echo "Failure! Retrying in $timeout.." 1>&2
    sleep $timeout
    attempt=$(( attempt + 1 ))
    timeout=$(( timeout * 2 ))
  done

  if [[ $exitCode != 0 ]]
  then
    echo "You've failed me for the last time! ($@)" 1>&2
  fi

  return $exitCode
}

function main() {
  ROCKS_CONFIG=$(mktemp)
  echo "
  rocks_trees = {
    { name = [[system]], root = [[/usr/local]] }
  }
  " > $ROCKS_CONFIG

  cp -R /tmp/build/* /

  export LUAROCKS_CONFIG=$ROCKS_CONFIG
  export LUA_PATH="/usr/local/share/lua/5.1/?.lua;/usr/local/openresty/luajit/share/luajit-2.1.0-beta3/?.lua;;"
  export PATH=$PATH:/usr/local/openresty/luajit/bin

  /usr/local/bin/luarocks --version
  /usr/local/kong/bin/openssl version
  ldd /usr/local/openresty/nginx/sbin/nginx || true
  strings /usr/local/openresty/nginx/sbin/nginx | grep rpath || true
  strings /usr/local/openresty/bin/openresty | grep rpath || true
  find /usr/local/kong/lib/ || true
  /usr/local/openresty/bin/openresty -V || true

  pushd /kong
    luarocks make CRYPTO_DIR=/usr/local/kong \
        OPENSSL_DIR=/usr/local/kong \
        YAML_LIBDIR=/tmp/build/usr/local/kong/lib \
        YAML_INCDIR=/tmp/yaml \
        EXPAT_DIR=/usr/local/kong \
        LIBXML2_DIR=/usr/local/kong \
        CFLAGS="-L/tmp/build/usr/local/kong/lib -Wl,-rpath,/usr/local/kong/lib -O2 -std=gnu99 -fPIC"

    make dependencies
  popd

  cp /kong/bin/kong /tmp/build/usr/local/bin/kong
  sed -i 's/resty/\/usr\/local\/openresty\/bin\/resty/' /tmp/build/usr/local/bin/kong
}

main