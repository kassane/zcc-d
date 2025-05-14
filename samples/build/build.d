#!/usr/bin/env dub
/+ dub.sdl:
    name "builder"
    dependency "zcc" path="../.."
    mainSourceFiles "build.d"
+/

import std.stdio : stderr, writeln;
import std.path : buildPath;
import std.file : exists, mkdir;
import builder;

int main()
{
    auto b = new Builder;

    version (Windows)
        immutable lib = "cffi.dll";
    else version (OSX)
        immutable lib = "libcffi.dylib";
    else
        immutable lib = "libcffi.so";

    try
    {
        if (!exists(buildPath("build")))
            mkdir(buildPath("build"));

        b.addArgs([
            buildPath("source", "ffi.cc"), "-v", "-shared", "-fPIC",
            "-s", "-O2", "-o", buildPath("build", lib)
        ]);
        version (Windows)
            b.setTargetTriple("native-native-msvc");
        return b.execute;
    }
    catch (Exception e)
    {
        stderr.writeln("Compilation failed: ", e.msg);
        return 1;
    }
}
