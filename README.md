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
auto builder = new ZigCCBuilder();
builder.addArgs(["-c", "source.c", "-o", "output.o"]);
builder.execute();

// Cross-compilation
builder.setTargetTriple("aarch64-linux-gnu");
builder.setCpu("generic");

// C++ mode
builder.addArg("source.cpp"); // Automatically switches to C++ mode
```

## CI Support

Tested on multiple platforms (Linux, macOS, Windows) using DMD and LDC compilers.

## Requirements

- D compiler (DMD or LDC)
- Zig compiler
- DUB package manager

## Installation

```bash
dub add zcc
```

## License

MIT
