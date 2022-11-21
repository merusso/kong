local cjson             = require "cjson"
local web_server        = require("spec.fixtures.web_server")
local helpers           = require("spec.helpers")

describe("Web Server module", function ()
    it("logs", function ()
        local port = helpers.get_available_port()
        local server = web_server.new({
            port = port,
            host = "localhost"
        })

        server:start()

        finally(function ()
            server:shutdown()
        end)

        local client = helpers.http_client("localhost", port)

        local res = assert(client:request {
            method = "GET",
            path = "/",
            headers = {
                ["X-Test"] = "value"
            },
        })
        assert.res_status(200, res)

        local json = assert(server:get_logs())

        assert.is_array(json)
        assert.same(1, #json)
        assert.same("GET", json[1].method)
        assert.same("/", json[1].path)
        assert.same(200, json[1].status)
        assert.same("value", json[1].headers["x-test"])

        server:clear_logs()

        json = assert(server:get_logs())
        assert.same(0, #json)

    end)

    it("echo", function()
        local port = helpers.get_available_port()
        local server = web_server.new({
            port = port,
            host = "localhost"
        })

        server:start()

        finally(function ()
            server:shutdown()
        end)

        local client = helpers.http_client("localhost", port)

        local res = assert(client:request {
            method = "GET",
            path = "/",
            headers = {
                ["X-Test"] = "value"
            },
        })
        local body = assert.res_status(200, res)
        local json = assert(cjson.decode(body))

        assert.same("GET", json.method)
        assert.same("/", json.uri)
        assert.same("/", json.path)
        assert.same(200, json.status)
        assert.same("value", json.headers["x-test"])
    end)

    it("/delay", function()
        local port = helpers.get_available_port()
        local server = web_server.new({
            port = port,
            host = "localhost"
        })

        server:start()

        finally(function ()
            server:shutdown()
        end)

        local client = helpers.http_client("localhost", port)

        local res = assert(client:request {
            method = "GET",
            path = "/",
        })
        assert.res_status(200, res)

        server:set_delay(3)
        ngx.update_time()
        local start = ngx.now()

        res = assert(client:request {
            method = "GET",
            path = "/",
        })
        assert.res_status(200, res)

        ngx.update_time()
        local elapsed = ngx.now() - start
        assert(elapsed >= 3, "elapsed time should be >= 3 seconds: " .. elapsed)


        server:set_delay(0)
        ngx.update_time()
        start = ngx.now()
        res = assert(client:request {
            method = "GET",
            path = "/",
        })
        assert.res_status(200, res)

        ngx.update_time()
        elapsed = ngx.now() - start
        assert(elapsed <= 1, "elapsed time should be <= 1 seconds: " .. elapsed)
    end)
end)