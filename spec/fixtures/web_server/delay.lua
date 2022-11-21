local utils = require("spec.fixtures.web_server.utils")
local constants = require("spec.fixtures.web_server.constants")


local _M = {}


function _M.init_worker()
    local conf = _G.conf

    if conf.delay and conf.delay > 0 then
        local shdict = ngx.shared[constants.SHDICT_DELAY_NAME]
        shdict:set("delay", tonumber(conf.delay))
    end
end


function _M.content()
    local shdict = ngx.shared[constants.SHDICT_DELAY_NAME]
    local headers = ngx.req.get_headers()

    if headers[constants.X_DELAY_SECONDS_HEADER] then
        local seconds = tonumber(headers[constants.X_DELAY_SECONDS_HEADER])

        if seconds > 0 then
            shdict:set("delay", seconds)

        else
            shdict:delete("delay")
        end

    else
        local delay = shdict:get("delay")

        if delay then
            ngx.update_time()
            ngx.sleep(delay)
        end
    end

    return nil
end


return _M
