local utils = require("spec.fixtures.web_server.utils")
local cjson = require("cjson")

local _M = {}

function _M.content()
    return cjson.encode(utils.request_info())
end

return _M
