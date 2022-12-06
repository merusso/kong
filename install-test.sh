

#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

if [ -n "${DEBUG:-}" ]; then
    set -x
fi

function test() {
    cp -R /tmp/build /
    mv /tmp/build /tmp/bkup

    # From kong-openssl test.sh
    /usr/local/kong/bin/openssl version
    ls -la /usr/local/kong/lib/libyaml.so

    # From kong-runtime test.sh
    /usr/local/openresty/bin/openresty -V 2>&1 | grep -q pcre
    /usr/local/openresty/bin/resty -e 'print(jit.version)' | grep -q 'LuaJIT[[:space:]][[:digit:]]\+.[[:digit:]]\+.[[:digit:]]\+-[[:digit:]]\{8\}'
    ls -l /usr/local/openresty/lualib/resty/websocket/*.lua
    grep _VERSION /usr/local/openresty/lualib/resty/websocket/*.lua
    luarocks --version

    mv /tmp/bkup /tmp/build
}

test