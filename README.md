# zcc-d

A D library for building C/C++ code using Zig as a cross-compilation toolchain, inspired by [cc-rs](https://github.com/rust-lang/cc-rs) and [cargo-zigbuild](https://github.com/rust-cross/cargo-zigbuild).

## Features

- Cross-compilation support via Zig's C/C++ compiler
- Target triple and CPU architecture configuration
- Automatic C++ mode detection based on file extensions
- Flag transformation and filtering
- Build output logging
- Exception handling for build failures

## Usage

```d
// Basic usage
auto b = new Builder();
b.addArgs(["-c", "source.c", "-o", "output.o"]);
b.execute();

// Cross-compilation
b.setTargetTriple("aarch64-linux-gnu");
b.setCpu("generic");

// C++ mode
b.addArg("source.cpp"); // Automatically switches to C++ mode
```

## CI Support

Tested on multiple platforms (Linux, macOS, Windows) using DMD and LDC compilers.

## Requirements

- [D compiler](https://dlang.org/download.html)
- [Zig compiler](https://ziglang.org/download)
- DUB or REDUB package manager

## Installation

```bash
dub add zcc
```

## License

MIT
