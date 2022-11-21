return [[

daemon on;
worker_processes  ${worker_num};
error_log  ${base_path}/${logs_dir}/error.log info;
pid        ${base_path}/${logs_dir}/nginx.pid;
worker_rlimit_nofile 1024;

events {
    worker_connections  1024;
}


http {
    lua_shared_dict kong_test_logs 20m;
    lua_shared_dict kong_test_logs_lock 20m;
    lua_shared_dict kong_test_delay 20m;

    default_type application/json;
    access_log   ${base_path}/${logs_dir}/access.log;
    sendfile     on;
    tcp_nopush   on;
    server_names_hash_bucket_size 128;

    init_worker_by_lua_block {
        _G.conf = {
            delay = ${delay},
        }

        require("spec.fixtures.web_server.delay").init_worker()
    }

    server {
# if protocol ~= 'https' then
        listen 127.0.0.1:${http_port};
        listen [::1]:${http_port} ipv6only=on;
# else
        listen 127.0.0.1:${http_port} ssl http2;
        listen [::1]:${http_port} ssl http2 ipv6only=on;
        ssl_certificate     ${cert_path}/kong_spec.crt;
        ssl_certificate_key ${cert_path}/kong_spec.key;
        ssl_protocols TLSv1 TLSv1.1 TLSv1.2;
        ssl_ciphers   HIGH:!aNULL:!MD5;
#end

# if check_hostname then
        server_name ${host};
#end

        location /always_200 {
            return 200 ok;
        }

        location / {
            content_by_lua_block {
                local ret = require("spec.fixtures.web_server.log").content()

                if ret then
                    ngx.say(ret)
                    return
                end

                require("spec.fixtures.web_server.delay").content()

                ngx.say(require("spec.fixtures.web_server.echo").content())
            }
        }
    }
}
  

]]