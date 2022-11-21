local cjson = require("cjson")
local resty_lock = require("resty.lock")
local utils = require("spec.fixtures.web_server.utils")
local constants = require("spec.fixtures.web_server.constants")

local _M = {}


local function get_action()
    return ngx.req.get_headers()[constants.X_LOG_ACTION_HEADER] or "set"
end


local function get_log_group_name()
    return ngx.req.get_headers()[constants.X_LOG_GROUP_HEADER] or "default"
end


local function set()
    local request = utils.request_info()

    return utils.do_with_lock(constants.SHDICT_LOG_LOCK_NAME, constants.LOG_LOCK_NAME, function()
        local dict = ngx.shared[constants.SHDICT_LOG_NAME]
        local group_name = get_log_group_name()
        local logs = dict:get(group_name)
        local tbl = cjson.decode(logs or "[]")
        tbl[#tbl + 1] = request

        dict:set(group_name, cjson.encode(tbl))
    end)
end


local function get()
    local group_name = get_log_group_name()

    if not group_name then
        return false
    end

    local dict = ngx.shared[constants.SHDICT_LOG_NAME]
    local logs = dict:get(group_name)
    return logs or "[]"
end


function _M.content()
    local shdict = ngx.shared[constants.SHDICT_LOG_NAME]

    local action = get_action()

    if action == "set" then
        set()
        return nil

    elseif action == "clear" then
        shdict:flush_all()
        return nil

    elseif action == "get" then
        return get()
    end
end

return _M
