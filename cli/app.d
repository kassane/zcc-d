module cli.zcc;

import std.stdio : stderr;
import std.path : buildPath, extension;
import builder : Builder, BuildOptions;
import std.string : toLower;

int main(string[] args) @safe
{
    auto b = new Builder;

    // Check if triple set msvc, to avoid libc++ build issues
    if (!BuildOptions.triple.isNull)
        b.setTargetTriple(BuildOptions.triple.get);
    if (!BuildOptions.cpu.isNull)
        b.setCpu(BuildOptions.cpu.get);

    string[] flags;
    foreach (arg; args[1 .. $])
    {
        auto ext = extension(arg).toLower;
        if (ext == ".s" || ext == ".c" || ext == ".o" || ext == ".obj" || ext == ".cpp" || ext == ".cxx" || ext == ".cc" || ext == ".c++")
            b.file(arg);
        else
            flags ~= arg;
    }

    try
    {
        b.addArgs(flags);
        return b.execute;
    }
    catch (Exception e)
    {
        return trustedStderr("Error: Compilation failed - ", e);
    }
}

static int trustedStderr(string fmt, Exception e) @trusted
{
    import core.stdc.stdlib : EXIT_FAILURE;

    stderr.writeln(fmt, e.msg);
    return EXIT_FAILURE;
}
