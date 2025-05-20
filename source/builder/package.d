/* MIT License
* Copyright (c) 2025 Matheus C. França
* See LICENSE file for details
*/

/// Wraps compiler commands.
module builder;

import std.stdio;
import std.process;
import std.array;
import std.string;
import std.algorithm : canFind, filter, any, startsWith, endsWith;
import std.typecons : Nullable;
import std.path : extension;
import std.exception : enforce;

/// Stores build configuration options.
struct BuildOptions
{
    /// Target triple (e.g., x86_64-linux-gnu).
    static Nullable!string triple;
    /// CPU features (e.g., generic).
    static Nullable!string cpu;
}

/// Provides flag filtering and transformation utilities.
mixin template FlagChecks()
{
    /// Transforms or skips flags for Zig compatibility.
    static string[] processFlag(string arg) @safe pure nothrow
    {
        static immutable string[] skipExact = [
            "--exclude-libs", "ALL", "--no-as-needed", "/nologo", "/NOLOGO"
        ];
        if (skipExact.canFind(arg))
            return [];
        if (arg.endsWith("-group"))
            return ["-Wl,--start-group", "-Wl,--end-group"];
        if (arg.endsWith("-dynamic"))
            return ["-Wl,--export-dynamic"];
        return [arg];
    }

    /// Checks if a flag is Clang-specific for -cflags.
    static bool isClangFlag(string arg) @safe pure nothrow
    {
        return !arg.startsWith("-Wl,") && arg != "-Wl,--start-group" &&
            arg != "-Wl,--end-group" && arg != "-Wl,--export-dynamic";
    }
}

/// Builds and executes Zig subcommands.
class Builder
{
    /// Minimum command length for sanitizer flags (zig, cc/c++, +1 arg).
    private enum MIN_SANITIZE_COMMAND_LENGTH = 3;
    /// Base command length (zig, cc/c++).
    private enum BASE_COMMAND_LENGTH = 2;
    /// Length of "arm64-apple" prefix.
    private enum ARM64_APPLE_PREFIX_LENGTH = "arm64-apple".length;
    /// Length of "x86_64-apple" prefix.
    private enum X86_64_APPLE_PREFIX_LENGTH = "x86_64-apple".length;
    /// Length of "-unknown-unknown" suffix.
    private enum UNKNOWN_UNKNOWN_LENGTH = "-unknown-unknown".length;
    /// Allowed DMD architectures.
    private static immutable ALLOWED_DMD_ARCHES = ["x86_64", "i386", "i686"];
    //dfmt off
    /// Supported Zig triples.
     private static immutable SUPPORTED_ZIG_TRIPLES = [
        "arc-linux-gnu", "arm-freebsd-eabihf", "arm-linux-gnueabi", "arm-linux-gnueabihf",
        "arm-linux-musleabi", "arm-linux-musleabihf", "armeb-linux-gnueabi",
        "armeb-linux-gnueabihf", "armeb-linux-musleabi", "armeb-linux-musleabihf",
        "thumb-freebsd-eabihf", "thumb-linux-musleabi", "thumb-linux-musleabihf",
        "thumb-windows-gnu", "thumbeb-linux-musleabi", "thumbeb-linux-musleabihf",
        "aarch64-freebsd-none", "aarch64-linux-gnu", "aarch64-linux-musl",
        "aarch64-macos-none", "aarch64-windows-gnu", "aarch64_be-linux-gnu",
        "aarch64_be-linux-musl", "csky-linux-gnueabi", "csky-linux-gnueabihf",
        "hexagon-linux-musl", "loongarch64-linux-gnu", "loongarch64-linux-gnusf",
        "loongarch64-linux-musl", "loongarch64-linux-muslsf", "m68k-linux-gnu",
        "m68k-linux-musl", "mips-linux-gnueabi", "mips-linux-gnueabihf",
        "mips-linux-musleabi", "mips-linux-musleabihf", "mipsel-linux-gnueabi",
        "mipsel-linux-gnueabihf", "mipsel-linux-musleabi", "mipsel-linux-musleabihf",
        "mips64-linux-gnuabi64", "mips64-linux-gnuabin32", "mips64-linux-muslabi64",
        "mips64-linux-muslabin32", "mips64el-linux-gnuabi64", "mips64el-linux-gnuabin32",
        "mips64el-linux-muslabi64", "mips64el-linux-muslabin32", "powerpc-freebsd-eabihf",
        "powerpc-linux-gnueabi", "powerpc-linux-gnueabihf", "powerpc-linux-musleabi",
        "powerpc-linux-musleabihf", "powerpc64-freebsd-none", "powerpc64-linux-gnu",
        "powerpc64-linux-musl", "powerpc64le-freebsd-none", "powerpc64le-linux-gnu",
        "powerpc64le-linux-musl", "riscv32-linux-gnu", "riscv32-linux-musl",
        "riscv64-freebsd-none", "riscv64-linux-gnu", "riscv64-linux-musl",
        "s390x-linux-gnu", "s390x-linux-musl", "sparc-linux-gnu", "sparc64-linux-gnu",
        "wasm32-wasi-musl", "wasm32-wasi", "wasm32-emscripten", "x86-freebsd-none",
        "x86-linux-gnu", "x86-linux-musl", "x86-windows-gnu", "x86_64-freebsd-none",
        "x86_64-linux-gnu", "x86_64-linux-gnux32", "x86_64-linux-musl",
        "x86_64-linux-muslx32", "x86_64-macos-none", "x86_64-windows-gnu"
    ];
    //dfmt on

    private Appender!(string[]) cmds;
    private Appender!(string[]) sourceFiles;
    private string targetTriple;
    private string cpu;
    private bool isCPlusPlus;
    private string[] warnings;

    /// Creates a builder for Zig cc or c++.
    /// Params:
    ///   useCpp = Use C++ mode if true, C mode if false.
    this(bool useCpp = false) @safe pure nothrow
    {
        cmds = appender!(string[]);
        sourceFiles = appender!(string[]);
        cmds.put("zig");
        cmds.put(useCpp ? "c++" : "cc");
        isCPlusPlus = useCpp;
    }

    /// Adds a compiler flag, ignoring source files and target options.
    /// Params:
    ///   arg = Flag to add.
    /// Returns: This builder for chaining.
    Builder addArg(string arg) @safe pure
    {
        auto ext = extension(arg).toLower;
        if (ext == ".c" || ext == ".o" || ext == ".obj" || ext == ".s"
            || ext == ".cpp" || ext == ".cxx" || ext == ".cc" || ext == ".c++")
            return this;
        if (arg == "--target" || arg.startsWith("--target="))
            return this;
        mixin FlagChecks;
        cmds.put(processFlag(arg));
        return this;
    }

    /// Adds multiple compiler flags.
    /// Params:
    ///   args = Flags to add.
    /// Returns: This builder for chaining.
    Builder addArgs(string[] args) @safe pure
    {
        foreach (arg; args)
            addArg(arg);
        return this;
    }

    /// Adds a source file, enabling C++ mode for .cpp/.cxx/.cc/.c++ files.
    /// Params:
    ///   file = Source file path (.c, .cpp, .cxx, .cc, .c++, .o, .obj, .s).
    /// Returns: This builder for chaining.
    Builder file(string file) @safe pure
    {
        auto ext = extension(file).toLower;
        if (ext == ".cpp" || ext == ".cxx" || ext == ".cc" || ext == ".c++")
        {
            if (!targetTriple.endsWith("msvc"))
            {
                isCPlusPlus = true;
                cmds.data[1] = "c++";
            }
        }
        else if (ext != ".c" && ext != ".o" && ext != ".obj" && ext != ".s")
            return this;
        sourceFiles.put(file);
        return this;
    }

    /// Adds multiple source files.
    /// Params:
    ///   files = Source file paths.
    /// Returns: This builder for chaining.
    Builder files(string[] files) @safe pure
    {
        foreach (f; files)
            file(f);
        return this;
    }

    /// Sets the target triple, transforming RISC-V, ARM, WebAssembly, Apple, and GNU-style triples.
    /// Params:
    ///   triple = Target triple (e.g., x86_64-linux-gnu).
    /// Returns: This builder for chaining.
    Builder setTargetTriple(string triple) @safe pure
    {
        string transformedTriple = triple;

        // Rename RISC-V architectures (riscv64*, riscv32*) to riscv64-, riscv32-
        if (triple.startsWith("riscv"))
        {
            auto hyphenIndex = triple.indexOf('-');
            if (hyphenIndex > 0)
            {
                auto prefix = triple[0 .. hyphenIndex];
                if (prefix.startsWith("riscv64"))
                    transformedTriple = "riscv64" ~ triple[hyphenIndex .. $];
                else if (prefix.startsWith("riscv32"))
                    transformedTriple = "riscv32" ~ triple[hyphenIndex .. $];
            }
            else
                warnings ~= "Warning: Malformed RISC-V triple " ~ triple;
        }
        // Rename ARM architectures (armv5*, armv6*, armv7*, armv8*) to arm-
        else if (triple.startsWith("armv"))
        {
            auto hyphenIndex = triple.indexOf('-');
            if (hyphenIndex > 0)
            {
                auto prefix = triple[0 .. hyphenIndex];
                if (prefix.startsWith("armv5") || prefix.startsWith("armv6") ||
                    prefix.startsWith("armv7") || prefix.startsWith("armv8"))
                {
                    transformedTriple = "arm" ~ triple[hyphenIndex .. $];
                }
            }
            else
                warnings ~= "Warning: Malformed ARM triple " ~ triple;
        }
        // Handle WebAssembly triples
        else if (triple.startsWith("wasm32-"))
        {
            auto parts = triple.split('-');
            if (parts.length >= 3)
            {
                if (parts[$ - 1] == "wasm" && parts.length >= 4)
                {
                    string abi = parts[$ - 2];
                    if (abi == "emscripten")
                        transformedTriple = "wasm32-emscripten";
                    else if (parts.length == 4 && parts[1] == "unknown" && parts[2] == "unknown")
                        transformedTriple = "wasm32-freestanding";
                    else
                        transformedTriple = "wasm32-" ~ abi;
                }
                else if (parts[$ - 1] == "musl" && parts.length >= 3)
                {
                    string abi = parts[$ - 2];
                    transformedTriple = "wasm32-" ~ abi;
                }
                else
                {
                    string abi = parts[$ - 1];
                    transformedTriple = "wasm32-" ~ abi;
                }
            }
            else
                warnings ~= "Warning: Malformed WebAssembly triple " ~ triple;
        }

        // Apply existing transformations
        if (transformedTriple.startsWith("arm64-apple"))
            targetTriple = "aarch64" ~ transformedTriple[ARM64_APPLE_PREFIX_LENGTH .. $];
        else if (transformedTriple.startsWith("x86_64-apple"))
            targetTriple = "x86_64" ~ transformedTriple[X86_64_APPLE_PREFIX_LENGTH .. $];
        else if (transformedTriple.endsWith("-unknown-unknown"))
            targetTriple = transformedTriple[0 .. $ - UNKNOWN_UNKNOWN_LENGTH] ~ "-freestanding";
        else if (transformedTriple.canFind("-unknown-"))
        {
            auto parts = transformedTriple.split("-unknown-");
            if (parts.length == 2)
                targetTriple = parts[0] ~ "-" ~ parts[1];
            else
                targetTriple = transformedTriple;
        }
        else
            targetTriple = transformedTriple;

        // Store warning if triple is not supported by Zig
        if (!SUPPORTED_ZIG_TRIPLES.canFind(targetTriple))
            warnings ~= "Warning: Target triple " ~ targetTriple ~ " is not in Zig's supported triple list";
        return this;
    }

    /// Sets CPU features.
    /// Params:
    ///   cpu = CPU feature string (e.g., generic).
    /// Returns: This builder for chaining.
    Builder setCpu(string cpu) @safe pure nothrow
    {
        this.cpu = cpu;
        return this;
    }

    /// Builds the Zig command with sanitizer flags if needed.
    /// Returns: Command array for execution.
    string[] build() @safe pure
    {
        auto result = cmds.data.dup ~ sourceFiles.data;
        if (!targetTriple.empty)
            result ~= ["-target", targetTriple];
        if (!cpu.empty)
            result ~= ["-mcpu=" ~ cpu];
        if (result.length > MIN_SANITIZE_COMMAND_LENGTH)
            result ~= "-fno-sanitize=all";
        return result;
    }

    /// Builds a static or dynamic library with Zig build-lib.
    /// Params:
    ///   libpath = Output file path.
    ///   isShared = Build a dynamic library if true, static if false.
    /// Returns: Exit status (0 for success).
    int buildLibrary(string libpath, bool isShared = false) @trusted
    {
        if (sourceFiles.data.length == 0)
        {
            stderr.writeln("Error: No source files specified for library build");
            return 1;
        }
        auto cmd = ["zig", "build-lib"] ~ sourceFiles.data;
        cmd ~= ["-femit-bin=" ~ libpath, "-OReleaseFast"]; // disble ubsan
        if (isShared)
            cmd ~= ["-dynamic"];
        if (!targetTriple.empty)
            cmd ~= ["-target", targetTriple];
        if (!cpu.empty)
            cmd ~= ["-mcpu=" ~ cpu];

        mixin FlagChecks;
        auto clangFlags = cmds.data.filter!(isClangFlag).array;
        if (clangFlags.length)
            cmd ~= ["-cflags"] ~ clangFlags[2 .. $] ~ ["--"];
        cmd ~= isCPlusPlus && !targetTriple.endsWith("msvc") ? "-lc++" : "-lc";

        debug
        {
            write("[zig build-lib] flags: \"");
            foreach (c; cmd[2 .. $])
                write(c, " ");
            writeln("\"");
        }

        // Log warnings before execution
        foreach (warning; warnings)
            stderr.writeln(warning);
        return executeCommand(cmd, "build-lib");
    }

    /// Executes the Zig command, printing flags in debug mode.
    /// Returns: Exit status (0 for success).
    int execute() @trusted
    {
        auto cmd = build();
        if (cmd.length > BASE_COMMAND_LENGTH)
        {
            debug
            {
                write("[zig ", cmds.data[1], "] flags: \"");
                foreach (c; cmd[BASE_COMMAND_LENGTH .. $])
                    write(c, " ");
                writeln("\"");
            }
        }

        // Log warnings before execution
        foreach (warning; warnings)
            stderr.writeln(warning);
        return executeCommand(cmd, cmds.data[1]);
    }

    /// Executes a command, enforcing DMD architecture restrictions.
    /// Params:
    ///   cmd = Command array to execute.
    ///   mode = Command mode (e.g., cc, c++, build-lib).
    /// Returns: Exit status (0 for success).
    private int executeCommand(string[] cmd, string mode) @trusted
    {
        version (DMD)
        {
            if (!targetTriple.empty && targetTriple != "native-native" &&
                !ALLOWED_DMD_ARCHES.any!(arch => targetTriple.canFind(arch)))
            {
                stderr.writeln("Error: DMD only supports x86/x86_64 or -target native-native");
                return 1;
            }
        }

        try
        {
            auto result = std.process.execute(cmd);
            if (result.output.length)
                write(result.output);
            enforce(result.status == 0, format("Zig %s failed with exit code %d: %s",
                    mode, result.status, result.output));
            return result.status;
        }
        catch (ProcessException e)
        {
            stderr.writeln("Error executing zig ", mode, ": ", e.msg);
            return 1;
        }
    }
}

/// Unit tests for Builder.
version (unittest)
{
    import std.exception : assertThrown;
    import std.algorithm : any;

    @("Skip excluded flags")
    unittest
    {
        auto builder = new Builder();
        builder.addArg("--no-as-needed").addArg("--exclude-libs").addArg("/nologo");
        assert(builder.build() == ["zig", "cc"]);
    }

    @("Transform -group and -dynamic flags")
    unittest
    {
        auto builder = new Builder();
        builder.addArg("-group");
        assert(builder.build() == [
            "zig", "cc", "-Wl,--start-group", "-Wl,--end-group",
            "-fno-sanitize=all"
        ]);
    }

    @("Preserve explicit library flags")
    unittest
    {
        auto builder = new Builder();
        builder.addArg("-lm");
        assert(builder.build() == ["zig", "cc", "-lm"]);
    }

    @("Set target triple and CPU")
    unittest
    {
        auto builder = new Builder();
        builder.setTargetTriple("arm64-apple-macos").setCpu("generic");
        assert(builder.build() == [
            "zig", "cc", "-target", "aarch64-macos", "-mcpu=generic",
            "-fno-sanitize=all"
        ]);
    }

    @("Detect C++ mode from file extension")
    unittest
    {
        auto builder = new Builder();
        builder.file("test.cpp");
        assert(builder.build() == ["zig", "c++", "test.cpp"]);
    }

    @("DMD rejects non-x86/x86_64 targets")
    unittest
    {
        version (DMD)
        {
            auto builder = new Builder();
            builder.setTargetTriple("wasm32-wasi-musl");
            assert(builder.execute() == 1);
        }
    }

    @("LDC allows all targets")
    unittest
    {
        version (LDC)
        {
            auto builder = new Builder();
            builder.setTargetTriple("riscv64-linux-gnu");
            assert(builder.build().canFind("riscv64-linux-gnu"));
        }
    }

    @("Pass through Clang flags")
    unittest
    {
        auto builder = new Builder();
        builder.file("test.c").addArg("-Wall").addArg("-std=c99").addArg("-h");
        assert(builder.build() == [
            "zig", "cc", "-Wall", "-std=c99", "-h", "test.c", "-fno-sanitize=all"
        ]);
    }

    @("DMD allows x86_64 target")
    unittest
    {
        version (DMD)
        {
            auto builder = new Builder();
            builder.setTargetTriple("x86_64-linux-gnu");
            assert(builder.build().canFind("x86_64-linux-gnu"));
        }
    }

    @("Pass --help to zig")
    unittest
    {
        auto builder = new Builder();
        builder.addArg("--help");
        assert(builder.build() == ["zig", "cc", "--help"]);
    }

    @("Throw on failed execution")
    unittest
    {
        auto builder = new Builder();
        builder.file("nonexistent.c");
        assertThrown!Exception(builder.execute());
    }

    @("Detect C++ mode with any flag")
    unittest
    {
        auto builder = new Builder();
        builder.file("test.cpp").addArg("-some-flag");
        assert(builder.build() == [
            "zig", "c++", "-some-flag", "test.cpp", "-fno-sanitize=all"
        ]);
    }

    @("DMD allows native-native target")
    unittest
    {
        version (DMD)
        {
            auto builder = new Builder();
            builder.setTargetTriple("native-native");
            assert(builder.build() == [
                "zig", "cc", "-target", "native-native", "-fno-sanitize=all"
            ]);
        }
    }

    @("Throw on invalid Clang flag")
    unittest
    {
        auto builder = new Builder();
        builder.file("test.c").addArg("-invalid-flag");
        assertThrown!Exception(builder.execute());
    }

    @("Pass -h to zig")
    unittest
    {
        auto builder = new Builder();
        builder.addArg("-h");
        assert(builder.build() == ["zig", "cc", "-h"]);
    }

    @("MSVC target avoids zig c++")
    unittest
    {
        auto builder = new Builder();
        builder.setTargetTriple("x86_64-windows-msvc").file("test.cc");
        assert(builder.build() == [
            "zig", "cc", "test.cc", "-target", "x86_64-windows-msvc",
            "-fno-sanitize=all"
        ]);
    }

    @("Transform arm64-apple-ios to aarch64-ios")
    unittest
    {
        auto builder = new Builder();
        builder.setTargetTriple("arm64-apple-ios").file("test.c");
        assert(builder.build() == [
            "zig", "cc", "test.c", "-target", "aarch64-ios", "-fno-sanitize=all"
        ]);
    }

    @("MSVC target with native-windows-msvc")
    unittest
    {
        auto builder = new Builder();
        builder.setTargetTriple("native-windows-msvc").file("test.cc");
        assert(builder.build() == [
            "zig", "cc", "test.cc", "-target", "native-windows-msvc",
            "-fno-sanitize=all"
        ]);
    }

    @("Build library with C source")
    unittest
    {
        auto builder = new Builder();
        builder.file("test.c").addArg("-Wall");
        assertThrown!Exception(builder.buildLibrary("test.lib"));
    }

    @("Build library with C++ source")
    unittest
    {
        auto builder = new Builder();
        builder.file("test.cpp").addArg("-std=c++11");
        assertThrown!Exception(builder.buildLibrary("libtest.a"));
    }

    @("Build library with extra flags")
    unittest
    {
        auto builder = new Builder();
        builder.file("test.c").addArg("-Wall").file("rc.s");
        assertThrown!Exception(builder.buildLibrary("test.dylib"));
    }

    @("Add object file")
    unittest
    {
        auto builder = new Builder();
        builder.file("test.o");
        assert(builder.build() == ["zig", "cc", "test.o"]);
    }

    @("Add assembly file")
    unittest
    {
        auto builder = new Builder();
        builder.file("test.s");
        assert(builder.build() == ["zig", "cc", "test.s"]);
    }

    @("Transform armv5te-linux-gnu to arm-linux-gnu")
    unittest
    {
        auto builder = new Builder();
        builder.setTargetTriple("armv5te-linux-gnu");
        assert(builder.build() == [
            "zig", "cc", "-target", "arm-linux-gnu", "-fno-sanitize=all"
        ]);
    }

    @("Transform armv6-linux-musl to arm-linux-musl")
    unittest
    {
        auto builder = new Builder();
        builder.setTargetTriple("armv6-linux-musl");
        assert(builder.build() == [
            "zig", "cc", "-target", "arm-linux-musl", "-fno-sanitize=all"
        ]);
    }

    @("Transform armv7-linux-musl to arm-linux-musl")
    unittest
    {
        auto builder = new Builder();
        builder.setTargetTriple("armv7-linux-musl");
        assert(builder.build() == [
            "zig", "cc", "-target", "arm-linux-musl", "-fno-sanitize=all"
        ]);
    }

    @("Transform armv8a-freestanding to arm-freestanding")
    unittest
    {
        auto builder = new Builder();
        builder.setTargetTriple("armv8a-freestanding");
        assert(builder.build() == [
            "zig", "cc", "-target", "arm-freestanding", "-fno-sanitize=all"
        ]);
    }

    @("Transform riscv64gc-linux-gnu to riscv64-linux-gnu")
    unittest
    {
        auto builder = new Builder();
        builder.setTargetTriple("riscv64gc-linux-gnu");
        assert(builder.build() == [
            "zig", "cc", "-target", "riscv64-linux-gnu", "-fno-sanitize=all"
        ]);
    }

    @("Transform riscv32i-linux-musl to riscv32-linux-musl")
    unittest
    {
        auto builder = new Builder();
        builder.setTargetTriple("riscv32i-linux-musl");
        assert(builder.build() == [
            "zig", "cc", "-target", "riscv32-linux-musl", "-fno-sanitize=all"
        ]);
    }

    @("Transform wasm32-unknown-unknown-wasm to wasm32-freestanding")
    unittest
    {
        auto builder = new Builder();
        builder.setTargetTriple("wasm32-unknown-unknown-wasm");
        assert(builder.build() == [
            "zig", "cc", "-target", "wasm32-freestanding", "-fno-sanitize=all"
        ]);
    }

    @("Transform wasm32-unknown-emscripten-wasm to wasm32-emscripten")
    unittest
    {
        auto builder = new Builder();
        builder.setTargetTriple("wasm32-unknown-emscripten-wasm");
        assert(builder.build() == [
            "zig", "cc", "-target", "wasm32-emscripten", "-fno-sanitize=all"
        ]);
    }

    @("Support wasm32-wasi-musl triple")
    unittest
    {
        auto builder = new Builder();
        builder.setTargetTriple("wasm32-wasi-musl");
        assert(builder.build() == [
            "zig", "cc", "-target", "wasm32-wasi", "-fno-sanitize=all"
        ]);
    }
}
