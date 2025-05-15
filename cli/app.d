module cli.zcc;

import std.stdio : stderr;
import std.path : buildPath, extension;
import builder : Builder, BuildOptions;
import std.string : toLower;

int main(string[] args) @safe
{
    auto cmdArgs = args[1 .. $];
    auto b = new Builder;

    string[] flags;
    foreach (arg; cmdArgs)
    {
        auto ext = extension(arg).toLower;
        if (ext == ".s" || ext == ".c" || ext == ".o" || ext == ".obj" || ext == ".cpp" || ext == ".cxx" || ext == ".cc" || ext == ".c++")
            b.file(arg);
        else
            flags ~= arg;
    }

    if (!BuildOptions.triple.isNull)
        b.setTargetTriple(BuildOptions.triple.get);
    if (!BuildOptions.cpu.isNull)
        b.setCpu(BuildOptions.cpu.get);

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
