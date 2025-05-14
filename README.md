# zcc-d

[![CI Build](https://github.com/kassane/zcc-d/actions/workflows/ci.yml/badge.svg)](https://github.com/kassane/zcc-d/actions/workflows/ci.yml)
![Latest release](https://img.shields.io/github/v/release/kassane/zcc-d?include_prereleases&label=latest)
[![Static Badge](https://img.shields.io/badge/v2.111.0%20(stable)-f8240e?logo=d&logoColor=f8240e&label=frontend)](https://dlang.org/download.html)
[![License](https://img.shields.io/github/license/kassane/zcc-d)](https://github.com/kassane/zcc-d/blob/master/LICENSE)


A D library for building C/C++ code using Zig as a cross-compilation toolchain, inspired by [cc-rs](https://github.com/rust-lang/cc-rs) and [cargo-zigbuild](https://github.com/rust-cross/cargo-zigbuild).

## Features

- Cross-compilation support via Zig's C/C++ compiler
- Target triple and CPU architecture configuration
- Automatic C++ mode detection based on file extensions
- Flag transformation and filtering
- Build output logging
- Exception handling for build failures

## Requirements

- [D compiler](https://dlang.org/download.html)
- [Zig compiler](https://ziglang.org/download)
- [DUB](https://github.com/dlang/dub/releases) or [REDUB](https://github.com/MrcSnm/redub/releases) package manager

## Installation

```bash
dub add zcc
```

## Usage

**library**

```d
// Basic usage
auto b = new Builder();
b.addArgs(["-c", "source.c", "-o", "output.o"]);

// Cross-compilation
b.setTargetTriple("aarch64-linux-gnu");
b.setCpu("generic");

// C++ mode
b.addArg("source.cpp"); // Automatically switches to C++ mode

// Running the build
b.execute();
```

**executable**

```console
dub run zcc:cc -- <clang-flags> <source-files>
```

# Contributing

Contributions are welcome! Please open an issue or submit a pull request.