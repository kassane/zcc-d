#!/usr/bin/env dub
/+ dub.sdl:
    name "builder"
    dependency "zcc" path="../.."
    mainSourceFiles "build.d"
    buildTypes "release"
+/

import std.stdio : stderr, writeln;
import std.path : buildPath;
import std.file : exists, mkdir;
import builder;

int main()
{
    auto b = new Builder;

    version (Windows)
        immutable lib = "cffi.lib";
    else version (OSX)
        immutable lib = "libcffi.dylib";
    else
        immutable lib = "libcffi.so";

    try
    {
        if (!exists(buildPath("build")))
            mkdir(buildPath("build"));
        version (Windows)
        {
            // zig build-lib
            b.setTargetTriple("native-native-msvc");
            b.file(buildPath("source", "ffi.cc"));
            return b.buildLibrary(buildPath("build", lib));
        }
        else
        {
            // zig c++
            b.addArgs([
                "-shared", "-fPIC",
                "-s", "-O2", "-o", buildPath("build", lib)
            ]);
            b.file(buildPath("source", "ffi.cc"));
            return b.execute;
        }
    }
    catch (Exception e)
    {
        stderr.writeln("Compilation failed: ", e.msg);
        return 1;
    }
}
