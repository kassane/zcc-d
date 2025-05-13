module cli.zcc;

import builder;
import std.stdio;

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
