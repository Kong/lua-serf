package = "serf"
version = "0.1-1"
source = {
  url = "git://github.com/Mashape/lua-serf",
  tag = "0.1-1"
}
description = {
  summary = "Lua client for Serf",
  detailed = [[
    A Lua client for Serf (https://serfdom.io/) that leverages Serf's RPC protocol.
  ]],
  homepage = "https://github.com/Mashape/lua-serf",
  license = "MIT"
}
dependencies = {
  "lua >= 5.1",
  "lua-resty-socket ~> 0.0.5-0"
}
build = {
  type = "builtin",
  modules = {
    serfmp = "src/serfmp.lua",
    serf = "src/serf.lua"
  }
}