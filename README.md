[JIT plugin][github]
====================

This plugin is an implementation of a just-in-time (JIT) compiler for Pawn.
It compiles AMX bytecode into native x86 code on the fly and hooks into the
AMX API called by the SA-MP server to replace the VM's interpreter.

Although this is a SA-MP plugin the code is organized into a library called
amxjit which theoretically could be reused in other host programs, although 
I don't know of such applications.

Installation
------------

1. Download a binary package form the [Releases][download] page on Github 
   or build it yourself from source code (see
   [Building from source code](#building-from-source-code)).
2. Extract/copy `jit.so` or `jit.dll` to `<sever>/plugins/`.
3. Add `jit` (Windows) or `jit.so` (Linux) to the `plugins` line of your 
   server.cfg.

Binary archives come with an include file (`jit.inc`) that contains
some helper functions that you may find useful. But **you don't need to
include** it to be able to use the plugin, it's not required.

Usage
-----

Apart from installing the plugin you don't have to configure anything else.
If it gets loaded and you don't see any errors then it means that you code 
has been JIT-ed successfully.

If you see an error about an invalid instructions, check if you are using
YSI or other advanced libraries that use `#emit` (their code may be
incompatible with JIT). If using YSI try to update to the latest version
first. If that doesn't help you are out of luck, sorry. See
[Limitations](#limitations).

Keep in mind that using JIT usually helps with computation-intenstive tasks,
i.e. CPU bound code. It will not improve performance of those parts of code
that spend time on I/O operations such as reading from a database or the 
file system.

Benchmark (open.mp)
-------------------

[`benchmarks/omp_cpu.pwn`](benchmarks/omp_cpu.pwn) on an open.mp server with
no players, compiled with pawncc 3.10.11 `-d0 -O1`. Median of 3 runs per mode;
checksums are identical with and without JIT. More detail, including a real
gamemode, is in [docs/benchmark-openmp.md](docs/benchmark-openmp.md).

| Test | Windows: no JIT → JIT (ms) | Speedup | Linux: no JIT → JIT (ms) | Speedup |
|---|---|---|---|---|
| `int_arith`: 50M LCG iterations | 952 → 68 | **14.0×** | 319 → 78 | **4.1×** |
| `array_sort`: bubble sort, 4000 items | 740 → 24 | **30.8×** | 490 → 30 | **16.3×** |
| `func_calls`: recursive `Fib(30)` | 73 → 10 | **7.3×** | 41 → 11 | **3.7×** |
| `float_math`: 10M float operations | 1001 → 413 | **2.4×** | 1116 → 487 | **2.3×** |
| `native_calls`: 5M `strlen` | 182 → 70 | **2.6×** | 144 → 86 | **1.7×** |
| `string_format`: 300k `format` + `strfind` | 161 → 143 | **1.1×** | 135 → 127 | **1.1×** |

- Windows: open.mp 1.5.8, AMD Ryzen 7 7840HS.
- Linux: open.mp 1.6.7, GitHub Actions runner (AMD EPYC 7763, 4 vCPU, shared
  VM). Rerun it by pushing a commit with `[bench]` in its message.

The machines differ, so compare speedups rather than milliseconds. Speedups are
lower on Linux because open.mp's Linux build (GCC) interprets about 3× faster
than the Windows build (MSVC), while JIT-compiled code runs at about the same
speed on both. Code that mostly calls natives (`format`, `strlen`) gains little
either way: the JIT only speeds up the Pawn code around them.

Building from source code
-------------------------

If you want to build JIT from source code, e.g. to fix a bug and submit a 
pull request, simply follow the steps below. You will need a C++ compiler
and CMake.

### Linux

Install gcc and g++, make and cmake. On Ubuntu you would do that like so:

```
sudo apt-get install gcc g++ make cmake
```

If you're on a 64-bit system you'll need additional packages for compiling
for 32-bit:

```
sudo apt-get install gcc-multilib g++-multilib
```

For CentOS:

```
yum install gcc gcc-c++ cmake28 make
```

Now you're ready to build the plugin:

```
cd jit
mkdir build && cd build
cmake ../ -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF
make
```

### Windows

You'll need to install CMake and Visual Studio (Express edition will suffice).
After that, either run cmake from the command line:

```
cd jit
mkdir build && cd build
path/to/cmake.exe ../ -DBUILD_TESTING=OFF
```

or do the same from cmake-gui. This will generate a Visual Studio project in
the build folder.

To build the project:

```
path/to/cmake.exe --build . --config Release
```

You can also build it from within Visual Studio: open build/jit.sln
and go to menu -> Build -> Build Solution (or just press F7).

Limitations
-----------

Anything that doesn't use `#emit` will probably work perfectly fine. 
Otherwise, it depends on the code. There are some advanced `#emit` hacks 
that simply won't work with this JIT. Self-modifying code is one example 
(although in some caes it's possible to fix, see 
Detecting JIT at runtime {this link isn't available anymore}).

If you're using [YSI][ysi] this plugin most likely will not work for you and
will simply crash your server. However, with the recent versions of YSI this
may be no longer true. Just try it for yourself and see if it works.

Plugins that hook `amx_Exec()`, for example [CrashDetect][crashdetect], can't 
be used together with this plugin. If such hook is detected you will get an 
error at startup and your code will run through the default interpreter as 
usual.

How it works
------------

This is a pretty simple JIT. Code is compiled once and stored in memory until
the corresponding AMX is unloaded. Because of this there is a small delay
during script loading/initialization.

Majority of the compilation process is a direct translation of AMX opcodes 
into sequences of corresponding machine instructions using essentially a giant
`switch` statement. But there are some places where the JIT compiler tries to 
be a little bit smarter: for instance, it will replace calls to common 
floating-point functions (those found in float.inc) with equivalent FP
instructions built into the CPU to avoid the overhead of native function calls.

Code generation is done via [AsmJit][asmjit], a great assembler library for 
x86/x86-64 :thumbsup:. There also was an attempt to use LLVM as an alternative 
backend but it was abandoned...

License
-------

Licensed under the 2-clause BSD license. See [LICENSE.txt](LICENSE.txt).

[github]: https://github.com/Foundation-PAWN/samp-plugin-jit-backup
[download]: https://github.com/Foundation-PAWN/samp-plugin-jit-backup/releases
[asmjit]: https://github.com/kobalicek/asmjit
[ysi]: https://github.com/Y-Less/YSI
[crashdetect]: https://github.com/AmyrAhmady/samp-plugin-crashdetect
