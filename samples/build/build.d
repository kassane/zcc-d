#!/usr/bin/env dub
/+ dub.sdl:
    name "builder"
    dependency "zcc" path="../.."
    mainSourceFiles "build.d"
+/

import std.stdio : stderr, writeln;
import std.path : buildPath;
import builder;

int main()
{
    auto b = new Builder;

    version (Windows)
        immutable ext = ".obj";
    else
        immutable ext = ".o";

    try
    {
        b.addArgs([
            "-c", buildPath("source", "c", "ffi.c"), "-o",
            buildPath("source", "ffi" ~ ext)
        ]);
        return b.execute;
    }
    catch (Exception e)
    {
        stderr.writeln("Compilation failed: ", e.msg);
        return 1;
    }
}
