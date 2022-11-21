local _M = {}

local fmt = string.format
local mock_srv_tpl_file = require "spec.fixtures.web_server.nginx_conf"
local constants = require "spec.fixtures.web_server.constants"
local ngx = require "ngx"
local pl_dir = require "pl.dir"
local pl_file = require "pl.file"
local pl_template = require "pl.template"
local pl_path = require "pl.path"
local pl_stringx = require "pl.stringx"
local uuid = require "resty.jit-uuid"
local http_client = require "resty.http"
local cjson = require "cjson"


-- we need this to get random UUIDs
math.randomseed(os.time())


local HTTPS_SERVER_START_MAX_RETRY = 10

_M.LOGS_PATH = "/logs"
_M.ECHO_PATH = "/echo"
_M.DELAY_PATH = "/delay"
_M.ALWAYS_200_PATH = "/always_200"

local tmp_root = os.getenv("TMPDIR") or "/tmp"
-- local host_regex = [[([a-z0-9\-._~%!$&'()*+,;=]+@)?([a-z0-9\-._~%]+|\[[a-z0-9\-._~%!$&'()*+,;=:]+\])(:?[0-9]+)*]]



local function create_temp_dir(copy_cert_and_key)
  local tmp_name = fmt("nginx_%s", uuid())
  local tmp_path = fmt("%s/%s", tmp_root, tmp_name)
  local _, err = pl_path.mkdir(tmp_path)
  if err then
    return nil, err
  end

  local _, err = pl_path.mkdir(tmp_path .. "/logs")
  if err then
    return nil, err
  end

  if copy_cert_and_key then
    local status = pl_dir.copyfile("./spec/fixtures/kong_spec.crt", tmp_path)
    if not status then
      return nil, "could not copy cert"
    end

    status = pl_dir.copyfile("./spec/fixtures/kong_spec.key", tmp_path)
    if not status then
      return nil, "could not copy private key"
    end
  end

  return tmp_path
end


local function create_conf(params)
  local tpl, err = pl_template.compile(mock_srv_tpl_file)
  if err then
    return nil, err
  end

  local compiled_tpl = pl_stringx.Template(tpl:render(params, { ipairs = ipairs }))
  local conf_filename = params.base_path .. "/nginx.conf"
  local conf, err = io.open (conf_filename, "w")
  if err then
    return nil, err
  end

  conf:write(compiled_tpl:substitute(params))
  conf:close()

  return conf_filename
end


function _M:start()
  if not pl_path.exists(tmp_root) or not pl_path.isdir(tmp_root) then
    error("could not get a temporary path", 2)
  end

  local err
  self.base_path, err = create_temp_dir(self.protocol == "https")
  if err then
    error(fmt("could not create temp dir: %s", err), 2)
  end

  local conf_params = {
    base_path = self.base_path,
    delay = self.delay,
    cert_path = "./",
    check_hostname = self.check_hostname,
    logs_dir = self.logs_dir,
    host = self.host,
    hosts = self.hosts,
    http_port = self.http_port,
    protocol = self.protocol,
    worker_num = self.worker_num,
  }

  local file, err = create_conf(conf_params)
  if err then
    error(fmt("could not create conf: %s", err), 2)
  end

  for _ = 1, HTTPS_SERVER_START_MAX_RETRY do
    if os.execute("nginx -c " .. file .. " -p " .. self.base_path) then
      return
    end

    ngx.sleep(1)
  end

  error("failed starting nginx")
end


function _M:shutdown()
  local pid_filename = self.base_path .. "/logs/nginx.pid"
  local pid_file = io.open (pid_filename, "r")
  if pid_file then
    local pid, err = pid_file:read()
    if err then
      error(fmt("could not read pid file: %s", tostring(err)), 2)
    end

    local kill_nginx_cmd = fmt("kill -s TERM %s", tostring(pid))
    local status = os.execute(kill_nginx_cmd)
    if not status then
      error(fmt("could not kill nginx test server. %s was not removed", self.base_path), 2)
    end

    local pidfile_removed
    local watchdog = 0
    repeat
      pidfile_removed = pl_file.access_time(pid_filename) == nil
      if not pidfile_removed then
        ngx.sleep(0.01)
        watchdog = watchdog + 1
        if(watchdog > 100) then
          error("could not stop nginx", 2)
        end
      end
    until(pidfile_removed)
  end

  local _, err = pl_dir.rmtree(self.base_path)
  if err then
    print(fmt("could not remove %s: %s", self.base_path, tostring(err)))
  end

end


function _M:get_logs(group)
  group = group or "default"

  local client = http_client.new()

  local res, err = client:request_uri(self:get_uri(), {
    method = "GET",
    headers = {
      [constants.X_LOG_GROUP_HEADER] = group,
      [constants.X_LOG_ACTION_HEADER] = "get",
    }
  })

  if not res then
      ngx.log(ngx.ERR, "request failed: ", err)
      return
  end

  assert(res.status == 200, "expected 200, got " .. res.status)
  return cjson.decode(res.body)
end


function _M:clear_logs()
  local client = http_client.new()

  local res, err = client:request_uri(self:get_uri(), {
    method = "GET",
    headers = {
      [constants.X_LOG_ACTION_HEADER] = "clear",
    },
  })

  assert(res.status == 200)
end


function _M:set_delay(seconds)
  local client = http_client.new()

  local res, err = client:request_uri(self:get_uri(), {
    method = "GET",
    headers = {
      [constants.X_DELAY_SECONDS_HEADER] = seconds,
    },
  })

  assert(res.status == 200)
end


function _M:get_uri()
  return string.format("http://%s:%d", self.host, tonumber(self.port))
end


function _M.new(opts)
  assert(opts.port)
  opts.host = opts.host or "localhost"
  opts.protocol = opts.protocol or "http"
  opts.workers = opts.workers or 2
  opts.delay = opts.delay or 0
  opts.check_hostname = opts.check_hostname or false

  local self = setmetatable({}, _M)

  self.delay = tonumber(opts.delay)
  self.host = opts.host or "localhost"
  self.http_port = opts.port
  self.logs_dir = "logs"
  self.protocol = opts.protocol
  self.worker_num = opts.workers
  self.port = opts.port

  return setmetatable(self, {
    __index = _M,
    __gc = function(self)
      self:shutdown()
    end
  })

end

return _M
