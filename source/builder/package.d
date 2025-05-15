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
import std.algorithm : canFind, filter, any;
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

    private Appender!(string[]) cmds;
    private Appender!(string[]) sourceFiles;
    private string targetTriple;
    private string cpu;
    private bool isCPlusPlus;

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
        if (ext == ".c" || ext == ".cpp" || ext == ".cxx" || ext == ".cc" || ext == ".c++")
            return this;
        if (arg == "-target" || arg.startsWith("--target="))
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
    ///   file = Source file path.
    /// Returns: This builder for chaining.
    Builder file(string file) @safe pure
    {
        auto ext = extension(file).toLower;
        if (ext == ".cpp" || ext == ".cxx" || ext == ".cc" || ext == ".c++")
        {
            if (!targetTriple.endsWith("-windows-msvc"))
            {
                isCPlusPlus = true;
                cmds.data[1] = "c++";
            }
        }
        else if (ext != ".c")
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

    /// Sets the target triple, transforming Apple and GNU-style triples.
    /// Params:
    ///   triple = Target triple (e.g., x86_64-linux-gnu).
    /// Returns: This builder for chaining.
    Builder setTargetTriple(string triple) @safe pure nothrow
    {
        if (triple.startsWith("arm64-apple"))
            targetTriple = "aarch64" ~ triple[ARM64_APPLE_PREFIX_LENGTH .. $];
        else if (triple.startsWith("x86_64-apple"))
            targetTriple = "x86_64" ~ triple[X86_64_APPLE_PREFIX_LENGTH .. $];
        else if (triple.endsWith("-unknown-unknown"))
            targetTriple = triple[0 .. $ - UNKNOWN_UNKNOWN_LENGTH] ~ "-freestanding";
        else if (triple.canFind("-unknown-"))
        {
            auto parts = triple.split("-unknown-");
            if (parts.length == 2)
                targetTriple = parts[0] ~ "-" ~ parts[1];
            else
                targetTriple = triple;
        }
        else
            targetTriple = triple;
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

    /// Builds a static library with Zig build-lib.
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
        cmd ~= [
            "-femit-bin=" ~ libpath, isShared ? "-dynamic": "", "-fno-sanitize-c"
        ];
        if (!targetTriple.empty)
            cmd ~= ["-target", targetTriple];
        if (!cpu.empty)
            cmd ~= ["-mcpu=" ~ cpu];

        mixin FlagChecks;
        auto clangFlags = cmds.data.filter!(isClangFlag).array;
        if (clangFlags.length)
            cmd ~= ["-cflags"] ~ clangFlags[2 .. $] ~ ["--"];
        cmd ~= isCPlusPlus ? "-lc++" : "-lc";

        debug write("[zig build-lib] flags: \"");
        foreach (c; cmd[2 .. $])
            write(c, " ");
        writeln("\"");

        return executeCommand(cmd, "build-lib");
    }

    /// Executes the Zig command, printing flags in debug mode.
    /// Returns: Exit status (0 for success).
    int execute() @trusted
    {
        auto cmd = build();
        if (cmd.length > BASE_COMMAND_LENGTH)
        {
            debug write("[zig ", cmds.data[1], "] flags: \"");
            foreach (c; cmd[BASE_COMMAND_LENGTH .. $])
                write(c, " ");
            writeln("\"");
        }
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
            builder.setTargetTriple("aarch64-freestanding");
            assert(builder.execute() == 1);
        }
    }

    @("LDC allows all targets")
    unittest
    {
        version (LDC)
        {
            auto builder = new Builder();
            builder.setTargetTriple("aarch64-linux-gnu");
            assert(builder.build().canFind("aarch64-linux-gnu"));
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
        builder.file("test.c").addArg("-Wall").addArg("rc.s");
        assertThrown!Exception(builder.buildLibrary("test.dylib"));
    }
}
