local cjson   = require "cjson"
local helpers = require "spec.helpers"

local web_server = require("spec.fixtures.web_server")


for _, strategy in helpers.each_strategy() do
  describe("Balancer: least-connections [#" .. strategy .. "]", function()
    local upstream1_id
    local server1, server2
    local test_port1 = helpers.get_available_port()
    local test_port2 = helpers.get_available_port()

    lazy_setup(function()
      -- create two servers, one double the delay of the other
      server1 = web_server.new({
        port = test_port1,
        host = "127.0.0.1",
        protocol = "http",
        delay = 0.1,
      })
      server2 = web_server.new({
        port = test_port2,
        host = "127.0.0.1",
        protocol = "http",
        delay = 0.4,
      })

      server1:start()
      server2:start()

      local bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "upstreams",
        "targets",
      })

      assert(bp.routes:insert({
        hosts      = { "least1.test" },
        protocols  = { "http" },
        service    = bp.services:insert({
          protocol = "http",
          host     = "lcupstream",
        })
      }))

      local upstream1 = assert(bp.upstreams:insert({
        name = "lcupstream",
        algorithm = "least-connections",
      }))
      upstream1_id = upstream1.id

      assert(bp.targets:insert({
        upstream = upstream1,
        target = "127.0.0.1:" .. test_port1,
        weight = 100,
      }))

      assert(bp.targets:insert({
        upstream = upstream1,
        target = "127.0.0.1:" .. test_port2,
        weight = 100,
      }))

      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))
    end)

    lazy_teardown(function()
      helpers.stop_kong()
      server1:shutdown()
      server2:shutdown()
    end)

    it("balances by least-connections", function()
      local thread_max = 100 -- maximum number of threads to use
      local done = false
      local threads = {}

      local handler = function()
        while not done do
          local client = helpers.proxy_client()
          local res = assert(client:send({
            method = "GET",
            path = "/",
            headers = {
              ["Host"] = "least1.test"
            },
          }))
          assert.same(200, res.status)
          client:close()
        end
      end

      -- start the threads
      for i = 1, thread_max do
        threads[#threads+1] = ngx.thread.spawn(handler)
      end

      -- wait while we're executing
      ngx.update_time()
      local finish_at = ngx.now() + 3
      repeat
        ngx.sleep(0.01)
      until ngx.now() >= finish_at

      -- finish up
      done = true
      for i = 1, thread_max do
        ngx.thread.wait(threads[i])
      end

      local results1 = #server1:get_logs()
      local results2 = #server2:get_logs()
      local ratio = results1 / results2
      assert.near(2, ratio, 1)
      assert.is_not(ratio, 0)
    end)

    if strategy ~= "off" then
      it("add and remove targets", function()
        local api_client = helpers.admin_client()

        -- create a new target
        local res = assert(api_client:post("/upstreams/" .. upstream1_id .. "/targets", {
          headers = {
            ["Content-Type"] = "application/json",
          },
          body = {
            target = "127.0.0.1:10003",
            weight = 100
          },
        }))
        api_client:close()
        assert.same(201, res.status)

        -- check if it is available
        api_client = helpers.admin_client()
        local res, err = api_client:send({
          method = "GET",
          path = "/upstreams/" .. upstream1_id .. "/targets/all",
        })
        assert.is_nil(err)

        local body = cjson.decode((res:read_body()))
        api_client:close()
        local found = false
        for _, entry in ipairs(body.data) do
          if entry.target == "127.0.0.1:10003" and entry.weight == 100 then
            found = true
            break
          end
        end
        assert.is_true(found)

        -- update the target and assert that it still exists with weight == 0
        api_client = helpers.admin_client()
        res, err = api_client:send({
          method = "PATCH",
          path = "/upstreams/" .. upstream1_id .. "/targets/127.0.0.1:10003",
          headers = {
            ["Content-Type"] = "application/json",
          },
          body = {
            weight = 0
          },
        })
        assert.is_nil(err)
        assert.same(200, res.status)
        local json = assert.response(res).has.jsonbody()
        assert.is_string(json.id)
        assert.are.equal("127.0.0.1:10003", json.target)
        assert.are.equal(0, json.weight)
        api_client:close()

        api_client = helpers.admin_client()
        local res, err = api_client:send({
          method = "GET",
          path = "/upstreams/" .. upstream1_id .. "/targets/all",
        })
        assert.is_nil(err)

        local body = cjson.decode((res:read_body()))
        api_client:close()
        local found = false
        for _, entry in ipairs(body.data) do
          if entry.target == "127.0.0.1:10003" and entry.weight == 0 then
            found = true
            break
          end
        end
        assert.is_true(found)
      end)
    end
  end)

  if strategy ~= "off" then
    describe("Balancer: add and remove a single target to a least-connection upstream [#" .. strategy .. "]", function()
      local bp
      local test_port = helpers.get_available_port()
      local server = web_server.new({
        port = test_port,
      })

      lazy_setup(function()
        bp = helpers.get_db_utils(strategy, {
          "routes",
          "services",
          "upstreams",
          "targets",
        })

        server:start()

        assert(helpers.start_kong({
          database   = strategy,
          nginx_conf = "spec/fixtures/custom_nginx.template",
        }))
      end)

      lazy_teardown(function()
        server:shutdown()
        helpers.stop_kong()
      end)

      it("add and remove targets", function()
        local an_upstream = assert(bp.upstreams:insert({
          name = "anupstream",
          algorithm = "least-connections",
        }))

        local api_client = helpers.admin_client()

        -- create a new target
        local res = assert(api_client:post("/upstreams/" .. an_upstream.id .. "/targets", {
          headers = {
            ["Content-Type"] = "application/json",
          },
          body = {
            target = "127.0.0.1:" .. test_port,
            weight = 100
          },
        }))
        api_client:close()
        assert.same(201, res.status)

        -- check if it is available
        api_client = helpers.admin_client()
        local res, err = api_client:send({
          method = "GET",
          path = "/upstreams/" .. an_upstream.id .. "/targets/all",
        })
        assert.is_nil(err)

        local body = cjson.decode((res:read_body()))
        api_client:close()
        local found = false
        for _, entry in ipairs(body.data) do
          if entry.target == "127.0.0.1:" .. test_port and entry.weight == 100 then
            found = true
            break
          end
        end
        assert.is_true(found)

        -- delete the target and assert that it is gone
        api_client = helpers.admin_client()
        res, err = api_client:send({
          method = "DELETE",
          path = "/upstreams/" .. an_upstream.id .. "/targets/127.0.0.1:" .. test_port,
        })
        assert.is_nil(err)
        assert.same(204, res.status)
        api_client:close()

        api_client = helpers.admin_client()
        local res, err = api_client:send({
          method = "GET",
          path = "/upstreams/" .. an_upstream.id .. "/targets/all",
        })
        assert.is_nil(err)

        local body = cjson.decode((res:read_body()))
        api_client:close()
        local found = false
        for _, entry in ipairs(body.data) do
          if entry.target == "127.0.0.1:" .. test_port and entry.weight == 0 then
            found = true
            break
          end
        end
        assert.is_false(found)
      end)
    end)
  end
end
