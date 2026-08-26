-- DynASM x64 loader module.

local dasm_x86 = package.loaded.dasm_x86
package.loaded.dasm_x86 = nil -- unload dasm_x86 if it's already loaded.
_DASM_X64 = true -- Using a global is an ugly, but effective solution.
local dasm = require "dynasm.dasm_x86"
_DASM_X64 = nil
package.loaded.dasm_x86 = dasm_x86
return dasm
