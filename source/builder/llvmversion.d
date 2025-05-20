/* MIT License
* Copyright (c) 2025 Matheus C. França
* See LICENSE file for details
*/

/// Utilities for comparing LLVM versions between compilers for LTO build.
module builder.llvmversion;

version (LDC)
{
    import std.process;
    import std.string;
    import std.array;
    import std.algorithm : find;
    import std.exception : enforce;

    /// Compares LLVM versions used by ldc2 and zig cc.
    /// Returns: true if versions match, false otherwise.
    /// Throws: Exception if command execution fails or versions cannot be parsed.
    bool hasMatchingLLVMVersions() @safe
    {
        auto zigResult = execute(["zig", "cc", "--version"]);
        enforce(zigResult.status == 0, "Failed to execute zig cc --version: " ~ zigResult.output);
        auto zigLines = zigResult.output.splitLines;
        enforce(zigLines.length > 0, "No output from zig cc --version");

        // Extract zig cc version
        auto zigFirstLine = zigLines[0].strip;
        auto zigFields = zigFirstLine.split;
        enforce(zigFields.length >= 3 && zigFields[0] == "clang" && zigFields[1] == "version",
            "Unexpected zig cc --version format: " ~ zigFirstLine);
        string zigVersion = zigFields[2];

        auto ldcResult = execute(["ldc2", "--version"]);
        enforce(ldcResult.status == 0, "Failed to execute ldc2 --version: " ~ ldcResult.output);
        auto ldcLines = ldcResult.output.splitLines;
        enforce(ldcLines.length > 1, "Insufficient output from ldc2 --version");

        // Extract ldc2 version
        auto ldcSecondLine = ldcLines[1].strip;
        auto ldcFields = ldcSecondLine.split;
        auto llvmIndex = ldcFields.indexOf("LLVM");
        enforce(llvmIndex >= 0 && llvmIndex + 1 < ldcFields.length,
            "Unexpected ldc2 --version format: " ~ ldcSecondLine);
        string ldcVersion = ldcFields[llvmIndex + 1].strip;

        // Compare versions
        return zigVersion == ldcVersion;
    }

    private ptrdiff_t indexOf(string[] arr, string value) @trusted @nogc nothrow
    {
        foreach (i, v; arr)
            if (v == value)
                return i;
        return -1;
    }

    version (unittest)
    {
        @("Check LLVM version matching")
        @safe unittest
        {
            bool result = hasMatchingLLVMVersions();
            assert(!result, "Expected different LLVM versions");

        }
    }
}
