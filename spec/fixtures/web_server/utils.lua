local _M = {}
local resty_lock = require("resty.lock")


function _M.on_error(err)
    ngx.status = ngx.HTTP_INTERNAL_SERVER_ERROR
    ngx.say("internal error in spec/fixtures/web_server: " .. tostring(err))
    ngx.exit(ngx.HTTP_OK)
end


function _M.request_info()
    local headers = ngx.req.get_headers()

    ngx.req.read_body()
    local body = ngx.var.request_body

    local uri = ngx.var.request_uri or ""
    local s = string.find(uri, "?", 2, true)
    local path = s and string.sub(uri, 1, s - 1) or uri

    return {
        time = ngx.now(),
        uri = uri,
        path = path,
        args = ngx.var.args,
        method = ngx.req.get_method(),
        status = 200,
        headers = headers,
        body = body,
    }
end


function _M.do_with_lock(shdict_name, lock_name, fn)
    return xpcall(function()
        local lock = assert(resty_lock:new(shdict_name))
        assert(lock:lock(lock_name))

        fn()

        assert(lock:unlock())
    end, _M.on_error)
end


return _M
