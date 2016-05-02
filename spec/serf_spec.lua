-- Note: Serf is expected to be in the PATH environment variable for this test to run properly.

local BIND_ADDRESS_1 = "127.0.0.1:7946"
local RPC_ADDRESS_1 = "127.0.0.1:7373"

local BIND_ADDRESS_2 = "127.0.0.1:8946"
local RPC_ADDRESS_2 = "127.0.0.1:8373"

local function split(str, pat)
  local t = {}  -- NOTE: use {n = 0} in Lua-5.0
  local fpat = "(.-)" .. pat
  local last_end = 1
  local s, e, cap = str:find(fpat, 1)
  while s do
    if s ~= 1 or cap ~= "" then
      table.insert(t,cap)
    end
    last_end = e+1
    s, e, cap = str:find(fpat, last_end)
  end
  if last_end <= #str then
    cap = str:sub(last_end)
    table.insert(t, cap)
  end
  return t
end

describe("Serf Tests", function()

  local function start_serf(name, bind_address, rpc_address)
    local serf = require("serf")(1000)
    assert.truthy(serf)
    os.execute([[nohup serf agent -node=]]..name..[[ -bind=]]..bind_address..[[ -rpc-addr=]]..rpc_address..[[ > serf_]]..name..[[.log 2>&1 & echo $! > serf_]]..name..[[.pid]])
    -- Wait for agent to start
    while (os.execute([[cat serf_]]..name..[[.log | grep running > /dev/null]]) / 256 == 1) do
    -- Wait
    end

    local rpc_parts = split(rpc_address, ":")
    local ok, err = serf:connect(rpc_parts[1], tonumber(rpc_parts[2]))
    assert.truthy(ok)
    assert.falsy(err)

    local ok, err = serf:authenticate()
    assert.truthy(ok)
    assert.falsy(err)

    return serf
  end

  local function stop_serf(name)
    os.execute([[kill -9 $(cat serf_]]..name..[[.pid) && rm serf_]]..name..[[.pid && rm serf_]]..name..[[.log]])
  end

  local serf

  before_each(function()
    serf = start_serf("node1", BIND_ADDRESS_1, RPC_ADDRESS_1)
  end)

  after_each(function()
    stop_serf("node1")
  end)

  it("members", function()
    local res, err = serf:members()
    assert.truthy(res)
    assert.falsy(err)

    assert.equal(1, #res.Members)
    assert.equal("alive", res.Members[1].Status)
    assert.equal("node1", res.Members[1].Name)
  end)

  describe("multi-node", function()

    before_each(function()
      start_serf("node2", BIND_ADDRESS_2, RPC_ADDRESS_2)
    end)

    after_each(function()
      stop_serf("node2")
    end)

    it("should join", function()
      local res, err = serf:join({BIND_ADDRESS_2})
      assert.truthy(res)
      assert.falsy(err)

      local res, err = serf:members()
      assert.truthy(res)
      assert.falsy(err)

      assert.equal(2, #res.Members)
      for _, v in ipairs(res.Members) do
        assert.equal("alive", v.Status)
      end
    end)

    
  end)
end)