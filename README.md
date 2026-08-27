# DynASM with Lua mode

## `local dynasm = require "dynasm"`

This repository is a fork of [DynASM](https://luajit.org/dynasm.html) that merges the Lua mode from [luapower/dynasm](https://github.com/luapower/dynasm), which allows generating, compiling, and running x86 and x86‑64 assembly code directly from Lua. It also exposes the DynASM assembler and linker to be used as Lua modules.

Jump To: [Examples](#examples) |
         [DynASM API](#dynasm-api) |
         [DASM API](#dasm-api) |
         [Changes to DynASM](#changes-to-dynasm) |
         [Instructions](http://corsix.github.io/dynasm-doc/instructions.html) |
         [Directives](http://corsix.github.io/dynasm-doc/reference.html#directives)

## Features

* Translate, compile, and run Lua/ASM code from Lua without C glue.
* Load Lua/ASM (`.dasl`) files with `require()`.
* Work with file, string, and stream inputs and outputs.

## Installation

Install with LuaRocks:

```shell
$ luarocks make dynasm-luamode-1.5.0-1.rockspec
```

This installs the `dynasm` command and the Lua modules, which can be loaded with
`require "dynasm"` and `require "dasm"`.

After installation, you can run DynASM with:

```shell
$ dynasm
```

## Before you start

1. DynASM is [not an inline assembler](http://www.corsix.org/content/what-is-dynasm), it's a code generator.
	The following code:

	```lua
	function codegen(Dst)
		for i = 1, 3 do
			| mov ax, i
		end
	end
	```

	does **not** run the assembly instruction 3 times when codegen is called, instead, it merely adds the
	instruction sequence `mov ax, 1; mov ax, 2; mov ax, 3` to the dynasm state `Dst` when codegen is called.
	Mixing Lua and ASM code like this has the effect of generating code, not running it.

2. DynASM has two parts: the assembler/preprocessor, written in Lua, and the the linker/encoder, written in C.
`dynasm.lua` is the preprocessor. It takes mixed C/ASM code as input (from a file, string or file-like object)
and generates C code (to a file, string, or file-like object). Alternatively, it can take mixed Lua/ASM
code (like the above example) and generate Lua code, which is what the "Lua mode" part is all about.
`dasm.lua` is the binding to the C part of DynASM (the linker/encoder) which deals with building the code into
executable memory that can be called into.

3. `.dasl` files refer to Lua/ASM files, `.dasc` files refer to C/ASM files. dasl files can be used transparently
as Lua modules (they are translated on-the-fly).

## Examples

### 1. Self-contained module

This simple, self-contained module publishes the function `multiply(x, y) -> x * y`.

#### `multiply_x86.dasl`:

```lua
local ffi = require "ffi"              -- required
local dasm = require "dasm"            -- required

|.arch x86                             -- must be the first instruction
|.actionlist actions                   -- make an action list called `actions`

local Dst = dasm.new(actions)          -- make a dasm state, the name must be `Dst`

-- the next chunk of asm code will be added to the action list, and a call
-- to `dasm.put(Dst, 0)` will be generated in its place, which will be copying
-- the code from the start of the action list into the Dst state.

|  mov eax, [esp+4]
|  imul dword [esp+8]
|  ret

local code = Dst:build()               -- check, link and encode the code
local fptr = ffi.cast("int32_t __cdecl (*) (int32_t x, int32_t y)", code) -- take a callable pointer to it

return function(x, y)
	local _ = code                       -- keep the code buffer alive so it doesn't get collected
	return fptr(x, y)
end
```

The best way to understand how the above code is supposed to work is to translate it:

```shell
$ dynasm multiply_x86.dasl
```

#### `main.lua`:

```lua
require "dynasm"                           -- hook in the `require` loader for .dasl files
local multiply = require "multiply_x86"    -- translate, load and run `multiply_x86.dasl`
assert(multiply(-7, 5) == -35)
```

### 2. Code gen / build split

This is an idea on how you can keep your asm code separated from the plumbing required to build it,
and also how you can make separate functions out of different asm chunks from the same dasl file.

#### `funcs_x86.dasl`:

```lua
local ffi = require "ffi"
local dasm = require "dasm"

|.arch x86
|.actionlist actions
|.globalnames globalnames

local gen = {}

-- function which generates code into the dynasm state called `Dst`
-- and returns a "make" function which gets a dasm.globals() map
-- and returns a function that knows how to call into its code.
function gen.mul(Dst)
   |->mul:
   |  mov eax, [esp+4]
   |  imul dword [esp+8]
   |  ret
   return function(globals)
     return ffi.cast("int32_t __cdecl (*) (int32_t x, int32_t y)", globals.mul)
   end
end

function gen.add(Dst)
   |->add:
   |  mov eax, [esp+4]
   |  add eax, dword [esp+8]
   |  ret
   return function(globals)
     return ffi.cast("int32_t __cdecl (*) (int32_t x, int32_t y)", globals.add)
   end
end

return { gen = gen, actions = actions, globalnames = globalnames }
```

#### `funcs.lua`:

```lua
local dynasm = require "dynasm"
local dasm   = require "dasm"
local funcs  = require "funcs_x86"

local state, globals = dasm.new(funcs.actions)     -- create a dynasm state with the generated action list

local M = {}                                       -- generate the code, collecting the make functions
for name, gen in pairs(funcs.gen) do
   M[name] = gen(state)
end

local buf, size = state:build()                    -- check, link and encode the code
local globals = dasm.globals(globals, funcs.globalnames)   -- get the map of global_name -> global_addr

for name, make in pairs(M) do                      -- make the callable functions
   M[name] = make(globals)
end

M.__buf = buf                                      -- keep buf alive so it doesn't get collected

return M
```

#### `main.lua`:

```lua
local funcs = require "funcs"

assert(funcs.mul(-7, 5) == -35)
assert(funcs.add(-7, 5) == -2)
```

### 3. Load code from a string

```lua
local dynasm = require "dynasm"

local gencode, actions = dynasm.loadstring([[
local ffi  = require "ffi"
local dasm = require "dasm"

|.arch x86
|.actionlist actions

local function gencode(Dst)
	|  mov ax, bx
end

return gencode, actions
]])()
```

### 4. Translate from Lua

```lua
local dynasm = require "dynasm"
print(dynasm.translate_tostring "multiply_x86.dasl")
```

The above is equivalent to the command line:

```shell
$ dynasm multiply_x86.dasl
```

> **Tip**: You can pre-assemble `foo.dasl` into `foo.lua` -- `require()` will then choose `foo.lua`
over `foo.dasl`, so you basically get transparent caching for free. This speeds up app loading a bit,
and you can ship your app without the assembler (you still need to ship the linker/encoder for
all the platforms that you support).


### 5. Demo/tutorial

Check out the [dynasm_demo_x86.dasl](https://github.com/luapower/dynasm/blob/master/dynasm_demo_x86.dasl) and [dynasm_demo.lua](https://github.com/luapower/dynasm/blob/master/dynasm_demo.lua) modules in the [luapower/dynasm](https://github.com/luapower/dynasm) repository for more in-depth knowledge
about DynASM/Lua interaction. It works on Windows, Linux and OSX, both x86 and x64.

### 6. Brainfuck JIT compiler

The examples above don't do DynASM enough justice, because DynASM was after all made for building JIT compilers.
The [luapower/bf](https://github.com/luapower/bf) project contains a Lua/ASM translation of the code from Josh Haberman's
[tutorial](http://blog.reverberate.org/2012/12/hello-jit-world-joy-of-simple-jits.html) on DynASM and JITs,
and probably the simplest JIT compiler you could write. It too works on Windows, Linux and OSX, x86 and x64.


## DynASM API

### High-level API

| Function | Description |
| --- | --- |
| `dynasm.loadfile(infile [, opt [, env]]) -> chunk` | Load a `.dasl` file and return it as a Lua chunk. |
| `dynasm.loadstring(s [, opt [, chunkname [, env]]]) -> chunk` | Load a `.dasl` string and return it as a Lua chunk. |

### Low-level API

| Function | Description |
| --- | --- |
| `dynasm.translate(infile, outfile [, opt])` | Translate a `.dasc` or `.dasl` file. |
| `dynasm.string_infile(s) -> infile` | Use a string as input to `translate()`. |
| `dynasm.func_outfile(func) -> outfile` | Create an output that calls `func(s)` for each piece. |
| `dynasm.table_outfile(t) -> outfile` | Create an output that writes pieces to a table. |
| `dynasm.translate_tostring(infile [, opt]) -> s` | Translate to a string. |
| `dynasm.translate_toiter(infile [, opt]) -> iter() -> s` | Translate to an iterator of string pieces. |

## DASM API

### High-level API

| Function | Description |
| --- | --- |
| `dasm.new(actionlist [, externnames [, sectioncount [, globalcount [, externget [, globals]]]]]) -> state, globals` | Create a DASM state for an action list. |
| `state:build() -> buf, size` | Check, link, alloc, encode, and mprotect the generated code. |
| `dasm.dump(buf, size)` | Dump code using LuaJIT's included disassembler. |
| `dasm.globals(globals, globalnames) -> { name -> addr }` | Convert globals into a name-to-address table. |

### Low-level API

| Function | Description |
| --- | --- |
| `state:init(maxsection)` | Initialize a state. |
| `state:free()` | Free a state. |
| `state:setupglobal(globals, globalcount)` | Set up the globals buffer. |
| `state:growpc(maxpc)` | Grow the number of available PC labels. |
| `state:setup(actionlist)` | Set up the state with an action list. |
| `state:put(start, ...)` | The assembler generates these calls. |
| `state:link() -> size` | Link the code and return its size. |
| `state:encode(buf)` | Encode the code into a buffer. |
| `state:getpclabel(pclabel [, buf])` | Return a PC label offset, or a pointer with `buf`. |
| `state:checkstep(secmatch)` | Check the code before encoding. |
| `state:setupextern(externnames, getter)` | Set up an `extern` handler. |

## Changes to DynASM

* Added `-l, --lang C|Lua` command line option (set automatically for dasl and dasc files).
* In Lua mode, `-N` also attempts to keep generated line numbers in sync with the input by inserting blank lines. Use `-L` to disable this padding. This is best-effort only: macro expansion, `.include`, and `.capture`/`.dumpcapture` may break line alignment.
* ASM comments now use `--` in Lua mode instead of `//`.
* The defines `ARCH`, `OS`, `X86`, `X64`, `WINDOWS`, `LINUX`, and `OSX` are available by default in Lua mode.
* The `.globals` directive generates `DASM_MAXGLOBAL` in Lua mode.
* `.type` usage is limited in Lua mode: `FOO.field`, `FOO[expr]` and `FOO[expr].field` are ok, but arbitrary expressions like `FOO[5].bar[2].baz` are not.
* `extern foo` resolves to `ffi.C.foo` by default; if foo has no cdef, `ffi.cdef "void foo()"` is called (i.e. a dummy cdef is made for it - caveat emptor).
* `minilua` is no longer supported.

## Assembler tutorials & ref docs

* [The Unofficial DynASM Documentation](https://corsix.github.io/dynasm-doc/index.html)
* [x64 tutorial](https://software.intel.com/en-us/articles/introduction-to-x64-assembly/)
* [SSE quick ref](http://softpixel.com/~cwright/programming/simd/sse.php)
* [FPU tutorial & ref](http://www.website.masmforum.com/tutorials/fptute/index.html)
* [Agner Fog - Calling Conventions](http://www.agner.org/optimize/calling_conventions.pdf)
* [Agner Fog - CPU Internals](http://www.agner.org/optimize/microarchitecture.pdf)
* [Agner Fog - Optimization Guide](http://www.agner.org/optimize/optimizing_assembly.pdf)
* [Agner Fog - Instruction Tables](http://www.agner.org/optimize/instruction_tables.pdf)
