package = "dynasm-luamode"
version = "1.5.0-1"

source = {
  url = "git+https://github.com/slashOwO/dynasm-luamode.git"
}

description = {
  summary = "DynASM with Lua mode",
  detailed = [[
    Modified version of DynASM that allows generating, compiling,
    and running x86 and x86-64 assembly code directly from Lua.
  ]],
  license = "MIT"
}

dependencies = {
  "lua >= 5.1"
}

build = {
  type = "builtin",
  modules = {
    ["dasm_x86"] = {
      sources = { "dynasm/dasm_x86.c" }
    },
    ["dynasm.init"] = "dynasm/init.lua",
    ["dasm"] = "dasm.lua",
    ["dynasm.dasm_mm"] = "dynasm/dasm_mm.lua",
    ["dynasm.dasm_x64"] = "dynasm/dasm_x64.lua",
    ["dynasm.dasm_x86"] = "dynasm/dasm_x86.lua",
    ["dynasm.dynasm"] = "dynasm/dynasm.lua"
  },
  install = {
    bin = {
      dynasm = "dynasm/dynasm.lua"
    }
  }
}
