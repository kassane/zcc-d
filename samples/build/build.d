#!/usr/bin/env dub
/+ dub.sdl:
    name "builder"
    dependency "zcc" path="../.."
    mainSourceFiles "build.d"
    buildTypes "release"
+/

import std.stdio : stderr, writeln;
import std.path : buildPath, extension;
import std.file : exists, mkdir;
import std.string : toLower;
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

        b.file(buildPath("source", "ffi.cc"));
        version (Windows)
        {
            b.setTargetTriple("native-native-msvc");
            return b.buildLibrary(buildPath("build", lib));
        }
        else
        {
            b.addArgs([
                "-shared", "-fPIC",
                "-s", "-O2", "-o", buildPath("build", lib)
            ]);
            return b.execute;
        }
    }
    catch (Exception e)
    {
        stderr.writeln("Compilation failed: ", e.msg);
        return 1;
    }
}
