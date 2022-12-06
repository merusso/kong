# syntax=docker/dockerfile:1.4

FROM ghcr.io/kong/kong-runtime:1.1.3-linux-gnu as build

ENV PATH=$PATH:/kong/bin:/usr/local/openresty/bin/:/usr/local/kong/bin/:/usr/local/openresty/nginx/sbin/
ENV LUA_PATH=/kong/?.lua;/kong/?/init.lua;/root/.luarocks/share/lua/5.1/?.lua;/root/.luarocks/share/lua/5.1/?/init.lua;/usr/local/share/lua/5.1/?.lua;/usr/local/share/lua/5.1/?/init.lua;./?.lua;/usr/local/openresty/luajit/share/luajit-2.1.0-beta3/?.lua;/usr/local/openresty/luajit/share/lua/5.1/?.lua;/usr/local/openresty/luajit/share/lua/5.1/?/init.lua
ENV LUA_CPATH=/root/.luarocks/lib/lua/5.1/?.so;/usr/local/lib/lua/5.1/?.so;./?.so;/usr/local/openresty/luajit/lib/lua/5.1/?.so;/usr/local/lib/lua/5.1/loadall.so

RUN rm -rf /kong && rm -rf /distribution/*

COPY . /kong
WORKDIR /kong
RUN ./install-kong.sh

RUN ./install-test.sh && \
    kong version


FROM scratch

COPY --from=build /tmp/build /
