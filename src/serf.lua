local socket = require "resty.socket"
local mp = require "serfmp"

local DEFAULT_TIMEOUT = 3000
local CLIENT_IPC_VERSION = 1

local Serf = {}
Serf.__index = Serf

setmetatable(Serf, {
  __call = function (cls, ...)
    return cls.new(...)
  end,
})

function Serf.new(timeout, debug)
  local self = setmetatable({}, Serf)
  self.debug = debug
  self.timeout = timeout and timeout or DEFAULT_TIMEOUT
  self.serial_number = 0
  return self
end

function Serf:log(cpt, str)
  print(cpt, str)
  if str then 
    print(str:byte(1, #str)) 
  end
end

-- Building common header for all requests
function Serf:make_header(str)
  self.serial_number = self.serial_number + 1
  return {Command = str, Seq = self.serial_number}
end

-- Encoding and sending RPC requests
function Serf:send_request(header, body)
  if not self.socket then 
    return nil, "Client not connected" 
  end

  local str = mp.pack(header)
  if body then str = str .. mp.pack(body) end
  if self.debug then 
    self:log("Raw request: ", str) 
  end
  return self.socket:send(str)
end

-- Reading all data available on the socket
function Serf:read_connection()
  self.socket:settimeout(0)
  local rsp, msg, prt = self.socket:receive("*a")
  if not rsp and msg == "timeout" then 
    rsp = prt 
  end
  self.socket:settimeout(self.timeout)
  return rsp
end

-- Getting raw server response synchronously in following steps:
-- a) waiting for data available with receive(1)
-- b) reading all data arrived with read_connection()
function Serf:get_response(t)
  self.socket:settimeout(t)
  local rsp = self.socket:receive(1)
  self.socket:settimeout(self.timeout)
  if not rsp then return nil, "No data available" end
  local ext = self:read_connection()
  if ext then 
    rsp = rsp .. ext 
  end
  if self.debug then 
    self:log("Raw response: ", rsp) 
  end
  return rsp
end

-- Decoding server message in following steps:
-- a) trying to decode a response header from the initial data
-- b) if requested and data remaining then try to get a response from it
function Serf:decode_response(rsp, dbl)
  if not rsp then 
    return nil 
  end
  local i, j, n, itm = 1, 1, 0
  itm, i, n = mp.unpack(rsp)
  if not itm or type(itm) ~= "table" then return nil, "Could not decode header" end
  if itm.Error and #itm.Error > 0 then return nil, itm.Error end
  if dbl and itm.Seq and (i - 1) < n then itm, j = mp.unpack(rsp:sub(i)) end
  if (i - 1) + (j - 1) < n then rsp = rsp:sub((i - 1) + (j - 1) + 1) else rsp = nil end
  return itm, nil, rsp
end

function Serf:standard_query(lbl, bdy)
  local hdr = self:make_header(lbl)
  local vld, msg = self:send_request(hdr, bdy)
  if not vld then 
    return nil, msg 
  end
  local rsp, msg = self:get_response(self.timeout)
  if not rsp then 
    return nil, msg 
  end
  return self:decode_response(rsp, true)
end

function Serf:connect(address, port, timeout)
  local sock = socket.tcp()
  sock:settimeout(self.timeout)

  local ok, err = sock:connect(address, port)
  if err then
    return false, err
  end

  self.socket = sock
  return true
end

function Serf:close()
  self.socket:close()
end

function Serf:authenticate(auth_token)
  local hdr = self:make_header("handshake") -- handshake is required for all connections
  local vld, msg = self:send_request(hdr, {Version = CLIENT_IPC_VERSION})
  if not vld then 
    return nil, msg 
  end

  local rsp, msg = self:get_response(self.timeout)
  if not rsp then 
    return nil, msg 
  end

  local itm, msg = self:decode_response(rsp)
  if not itm then 
    return nil, msg 
  end

  -- auth is only required when server is configured for it
  if auth_token then
    local hdr = self:make_header("auth")
    local vld, msg = self:send_request(hdr, {AuthKey = auth_token})
    if not vld then 
      return nil, msg 
    end
    local rsp, msg = self:get_response(self.timeout)
    if not rsp then 
      return nil, msg 
    end
    local itm, msg = self:decode_response(rsp)
    if not itm then 
      return nil, msg 
    end
  end

  return true
end

function Serf.filter_address(rsp, msg)
  if rsp and rsp.Members then
    for i = 1, #rsp.Members do
      local adr = rsp.Members[i].Addr
      if adr and #adr >= 4 then
        rsp.Members[i].Addr = adr:byte(1) .. "." .. adr:byte(2) .. "." .. adr:byte(3) .. "." .. adr:byte(4)
      end
    end
  end
  return rsp, msg
end

function Serf:join(addrs, replay)
  return self:standard_query("join", {Existing = addrs, Replay = replay})
end

function Serf:leave()
  return self:standard_query("leave")
end

function Serf:members()
  return self.filter_address(self:standard_query("members"))
end

function Serf:membersfiltered(tags, status, name)
  return self.filter_address(self:standard_query("members-filtered", {Tags = tags, Status = status, Name = name}))
end

function Serf:getcoordinate(node)
  local rsp, msg = self:standard_query("get-coordinate", {Node = node})
  if rsp and rsp.Ok then rsp = rsp.Coord else rsp = nil end
  return rsp, msg
end

function Serf:forceleave(node)
  return self:standard_query("force-leave", {Node = node})
end

function Serf:event(name, payload, coalesce)
  return self:standard_query("event", {Name = name, Payload = payload, Coalesce = coalesce})
end

function Serf:installkey(key)
  local rsp, msg = self:standard_query("install-key", {Key = key})
  if rsp then rsp = rsp.Messages end
  return rsp, msg
end

function Serf:usekey(key)
  local rsp, msg = self:standard_query("use-key", {Key = key})
  if rsp then rsp = rsp.Messages end
  return rsp, msg
end

function Serf:removekey(key)
  local rsp, msg = self:standard_query("remove-key", {Key = key})
  if rsp then rsp = rsp.Messages end
  return rsp, msg
end

function Serf:listkeys()
  local rsp, msg = self:standard_query("list-keys")
  if rsp then rsp = {rsp.Keys, rsp.NumNodes, rsp.Messages} end
  return rsp, msg
end

function Serf:tags(add, del)
  return self:standard_query("tags", {Tags = add, DeleteTags = del})
end

function Serf:respond(id, msg)
  return self:standard_query("respond", {ID = id, Payload = msg})
end

function Serf:stats()
  return self:standard_query("stats")
end

function Serf:stream(filter, flags)
  -- TODO
end

function Serf:monitor(level, flags)
  -- TODO
end

function Serf:query(specs, flags)  
  -- TODO
end

function Serf:stop(id)
  -- TODO
end

return Serf