#!/usr/bin/env dub
/+ dub.sdl:
    name "build"
    dependency "zcc" path="../.."
    mainSourceFiles "build.d"
+/

import std.stdio : stderr, writeln;
import builder;

int main(string[] args)
{
    auto cmdArgs = args[1 .. $];
    auto b = new Builder;

    if (!BuildOptions.triple.isNull)
        b.setTargetTriple(BuildOptions.triple.get);
    if (!BuildOptions.cpu.isNull)
        b.setCpu(BuildOptions.cpu.get);

    try
    {
        b.addArgs(cmdArgs);
        return b.execute;
    }
    catch (Exception e)
    {
        stderr.writeln("Compilation failed: ", e.msg);
        return 1;
    }
}
