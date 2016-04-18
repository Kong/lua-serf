-- Note: Serf is expected to be in the PATH environment variable for this test to run properly.

local RPC_ADDRESS = "127.0.0.1:7373"

describe("Serf Tests", function()

  describe("Serf process", function()

    local serf = require("serf")(1000)
    assert.truthy(serf)

    before_each(function()
      os.execute([[nohup serf agent -rpc-addr=]]..RPC_ADDRESS..[[ > serf.log 2>&1 & echo $! > serf.pid]])
      -- Wait for agent to start
      while (os.execute("cat serf.log | grep running > /dev/null") / 256 == 1) do
      -- Wait
      end

      local ok, err = serf:connect("127.0.0.1", 7373)
      assert.truthy(ok)
      assert.falsy(err)

      local ok, err = serf:authenticate()
      assert.truthy(ok)
      assert.falsy(err)
    end)

    after_each(function()
      os.execute("kill -9 $(cat serf.pid) && rm serf.pid && rm serf.log")
    end)

    it("members", function()
      local res, err = serf:members()
      assert.truthy(res)
      assert.falsy(err)

      assert.equal(1, #res.Members)
      assert.equal("alive", res.Members[1].Status)
    end)
    
  end)

end)