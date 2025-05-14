/* MIT License
* Copyright (c) 2025 Matheus C. França
* See LICENSE file for details
*/

/// Zig cc/c++ compiler wrapper.
module builder;

import std.stdio;
import std.process;
import std.array;
import std.string;
import std.algorithm;
import std.typecons : Nullable;
import std.path : extension;
import std.exception : enforce;

/// Build configurations
struct BuildOptions
{
    /// Target triple (e.g., "x86_64-linux-gnu").
    static Nullable!string triple;
    /// CPU features (e.g., "generic").
    static Nullable!string cpu;
}

/// Flag filtering and transformation utilities.
mixin template FlagChecks()
{
    /// Skips specific flags to avoid conflicts with Zig.
    static bool shouldSkipFlag(string arg) @safe pure nothrow
    {
        static immutable string[] skipExact = [
            "--exclude-libs", "ALL", "--no-as-needed", "/nologo", "/NOLOGO"
        ];
        return skipExact.canFind(arg);
    }

    /// Transforms certain flags for Zig compatibility.
    static string[] transformFlag(string arg) @safe pure nothrow
    {
        if (arg.endsWith("-group"))
            return ["-Wl,--start-group", "-Wl,--end-group"];
        if (arg.endsWith("-dynamic"))
            return ["-Wl,--export-dynamic"];
        return [arg];
    }
}

/// Builds and executes zig cc/c++ commands.
class Builder
{
    private Appender!(string[]) cmds;
    private string targetTriple;
    private string cpu;
    private bool isCPlusPlus;

    /// Constructs a builder for zig cc or c++.
    /// Params:
    ///   useCpp = Use zig c++ if true, zig cc if false.
    this(bool useCpp = false) @safe pure nothrow
    {
        cmds = appender!(string[]);
        cmds.put("zig");
        cmds.put(useCpp ? "c++" : "cc");
        isCPlusPlus = useCpp;
    }

    /// Adds a single argument to the command.
    /// Switches to zig c++ for C++ file extensions, except for MSVC targets.
    Builder addArg(string arg) @safe pure
    {
        mixin FlagChecks;
        if (shouldSkipFlag(arg))
            return this;
        auto transformed = transformFlag(arg);
        cmds.put(transformed);
        if (!isCPlusPlus && transformed.length == 1)
        {
            auto ext = extension(arg).toLower;
            if (ext == ".cpp" || ext == ".cxx" || ext == ".cc" || ext == ".C" || ext == ".c++")
            {
                isCPlusPlus = targetTriple.canFind("msvc") ? false : true;
                cmds.data[1] = targetTriple.canFind("msvc") ? "cc" : "c++";
            }
        }
        return this;
    }

    /// Adds multiple arguments to the command.
    Builder addArgs(string[] args) @safe pure
    {
        foreach (arg; args)
            addArg(arg);
        return this;
    }

    /// Sets the target triple, transforming arm64-apple to aarch64-<macos|ios>.
    Builder setTargetTriple(string triple) @safe pure nothrow
    {
        if (triple.startsWith("arm64-apple"))
        {
            targetTriple = "aarch64" ~ triple[11 .. $]; // Replace arm64-apple to aarch64-<macos|ios>
        }
        else if (triple.startsWith("x86_64-apple"))
        {
            targetTriple = "x86_64" ~ triple[12 .. $]; // Replace x86_64-apple to x86_64-<macos|ios>
        }
        else
        {
            targetTriple = triple;
        }
        return this;
    }

    /// Sets the CPU features.
    Builder setCpu(string cpu) @safe pure nothrow
    {
        this.cpu = cpu;
        return this;
    }

    /// Builds the Zig command with -fno-sanitize=all.
    string[] build() @safe pure
    {
        auto result = cmds.data.dup;
        if (!targetTriple.empty)
            result ~= ["-target", targetTriple];
        if (!cpu.empty)
            result ~= [format("-mcpu=%s", cpu)];
        if (result.length > 3)
            result ~= "-fno-sanitize=all"; // Disable ubsan
        return result;
    }

    /// Executes the Zig command, printing output and flags.
    /// Throws: Exception on non-zero exit status or execution failure.
    int execute() @trusted
    {
        auto cmd = build();
        cmds.data[1] = targetTriple.canFind("msvc") ? "cc" : "c++";

        if (cmd.length > 2)
        {
            write("[zig ", cmds.data[1], "] flags: \"");
            foreach (c; cmd[2 .. $])
                write(c, " ");
            writeln("\"");
        }

        version (DMD)
        {
            if (!targetTriple.empty && targetTriple != "native-native" &&
                !targetTriple.canFind("x86_64", "i386", "i686"))
            {
                stderr.writeln("Error: DMD only supports x86/x86_64 or -target native-native");
                return 1;
            }
        }

        try
        {
            auto result = std.process.execute(cmd);
            if (result.output.length > 0)
                write(result.output);
            enforce(result.status == 0, format("Zig %s failed with exit code %d: %s",
                    cmds.data[1], result.status, result.output));
            return result.status;
        }
        catch (ProcessException e)
        {
            stderr.writeln("Error executing zig ", cmds.data[1], ": ", e.msg);
            return 1;
        }
    }
}

/// Unit tests for Builder.
version (unittest)
{
    import std.exception : assertThrown;

    @("Skip excluded flags")
    @safe unittest
    {
        auto builder = new Builder();
        builder.addArg("--no-as-needed").addArg("--exclude-libs").addArg("/nologo");
        assert(builder.build() == ["zig", "cc"]);
    }

    @("Transform -group and -dynamic flags")
    @safe unittest
    {
        auto builder = new Builder();
        builder.addArg("-group");
        assert(builder.build() == [
            "zig", "cc", "-Wl,--start-group", "-Wl,--end-group",
            "-fno-sanitize=all"
        ]);
    }

    @("Preserve explicit library flags")
    @safe unittest
    {
        auto builder = new Builder();
        builder.addArg("-lm");
        assert(builder.build() == ["zig", "cc", "-lm"]);
    }

    @("Set target triple and CPU")
    @safe unittest
    {
        auto builder = new Builder();
        builder.setTargetTriple("arm64-apple-macos").setCpu("generic");
        assert(builder.build() == [
            "zig", "cc", "-target", "aarch64-macos", "-mcpu=generic",
            "-fno-sanitize=all"
        ]);
    }

    @("Detect C++ mode from file extension")
    @safe unittest
    {
        auto builder = new Builder();
        builder.addArg("test.cpp");
        assert(builder.build() == ["zig", "c++", "test.cpp"]);
    }

    @("DMD rejects non-x86/x86_64 targets")
    @safe unittest
    {
        version (DMD)
        {
            auto builder = new Builder();
            builder.setTargetTriple("aarch64-unknown-linux-gnu");
            assert(builder.execute() == 1);
        }
    }

    @("LDC allows all targets")
    @safe unittest
    {
        version (LDC)
        {
            auto builder = new Builder();
            builder.setTargetTriple("aarch64-unknown-linux-gnu");
            assert(builder.build().canFind("aarch64-unknown-linux-gnu"));
        }
    }

    @("Pass through Clang flags")
    @safe unittest
    {
        auto builder = new Builder();
        builder.addArg("-Wall").addArg("-std=c99").addArg("-h");
        assert(builder.build() == [
            "zig", "cc", "-Wall", "-std=c99", "-h", "-fno-sanitize=all"
        ]);
    }

    @("DMD allows x86_64 target")
    @safe unittest
    {
        version (DMD)
        {
            auto builder = new Builder();
            builder.setTargetTriple("x86_64-pc-linux-gnu");
            assert(builder.build().canFind("x86_64-pc-linux-gnu"));
        }
    }

    @("Pass --help to zig")
    @safe unittest
    {
        auto builder = new Builder();
        builder.addArg("--help");
        assert(builder.build() == ["zig", "cc", "--help"]);
    }

    @("Throw on failed execution")
    @safe unittest
    {
        auto builder = new Builder();
        builder.addArg("nonexistent.c");
        assertThrown!Exception(builder.execute());
    }

    @("Detect C++ mode with any flag")
    @safe unittest
    {
        auto builder = new Builder();
        builder.addArg("test.cpp").addArg("-some-flag");
        assert(builder.build() == [
            "zig", "c++", "test.cpp", "-some-flag", "-fno-sanitize=all"
        ]);
    }

    @("DMD allows native-native target")
    @safe unittest
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
    @safe unittest
    {
        auto builder = new Builder();
        builder.addArg("-invalid-flag");
        assertThrown!Exception(builder.execute());
    }

    @("Pass -h to zig")
    @safe unittest
    {
        auto builder = new Builder();
        builder.addArg("-h");
        assert(builder.build() == ["zig", "cc", "-h"]);
    }

    @("MSVC target avoids zig c++")
    @safe unittest
    {
        auto builder = new Builder();
        builder.setTargetTriple("x86_64-windows-msvc").addArg("test.cc");
        assert(builder.build() == [
            "zig", "cc", "test.cc", "-target", "x86_64-windows-msvc",
            "-fno-sanitize=all"
        ]);
    }

    @("Transform arm64-apple-ios to aarch64-ios")
    @safe unittest
    {
        auto builder = new Builder();
        builder.setTargetTriple("arm64-apple-ios").addArg("test.c");
        assert(builder.build() == [
            "zig", "cc", "test.c", "-target", "aarch64-ios", "-fno-sanitize=all"
        ]);
    }

    @("MSVC target with native-windows-msvc")
    @safe unittest
    {
        auto builder = new Builder();
        builder.addArg("lib.cc").setTargetTriple("native-windows-msvc");
        assert(builder.build() == [
            "zig", "c++", "lib.cc", "-target", "native-windows-msvc",
            "-fno-sanitize=all"
        ]);
    }
}
