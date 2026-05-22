/++
 + `dun bundle --compile=PATH` — embed a bundled JS payload into a
 + copy of the running dun binary so it becomes a self-contained
 + executable.
 +
 + File layout when compiled:
 +
 +     [original dun binary bytes]
 +     [bundled JS bytes]
 +     [4-byte LE uint32: bundle size]
 +     [4-byte LE uint32: format version]
 +     [16-byte marker:   `\x7fDUN-COMPILED!\x7f`]
 +
 + On startup, the dun runtime reads the last 24 bytes of its own
 + executable. If the marker matches, it seeks back by `size + 24`
 + and reads the embedded bundle, then runs it instead of the
 + CLI's normal command dispatch.
 +
 + Matches `bun build --compile` / `deno compile` shape.
 +/
module dun.cli.embed;

import std.file : read, write, exists, isFile, getSize;
import std.path : absolutePath;

/// 16-byte magic marker at the end of a compiled binary.
public immutable string kCompileMarker = "\x7fDUN-COMPILED!\x7f";

/++
 + Current embed format version. Bump if the trailer layout
 + changes — the runtime checks this before extracting.
 +/
public immutable uint kCompileFormatVersion = 1;

/// Size of the trailer (marker + size + version) in bytes.
public immutable size_t kCompileTrailerSize =
    kCompileMarker.length + uint.sizeof + uint.sizeof;

/++
 + Append `bundle` to a copy of `srcExe` at `outPath`, then mark
 + the result executable (0o755). Returns 0 on success.
 +/
int writeCompiledExe(string srcExe, string outPath, const(ubyte)[] bundle) @trusted
{
    import std.stdio : stderr;
    try
    {
        if (!exists(srcExe) || !isFile(srcExe))
        {
            stderr.writeln("compile: source binary not found: ", srcExe);
            return 1;
        }
        auto srcBytes = cast(ubyte[]) read(srcExe);
        ubyte[] out_;
        out_.reserve(srcBytes.length + bundle.length + kCompileTrailerSize);
        out_ ~= srcBytes;
        out_ ~= bundle;
        // size (4 bytes LE)
        uint sz = cast(uint) bundle.length;
        out_ ~= [cast(ubyte)(sz & 0xff),
                 cast(ubyte)((sz >> 8) & 0xff),
                 cast(ubyte)((sz >> 16) & 0xff),
                 cast(ubyte)((sz >> 24) & 0xff)];
        // version (4 bytes LE)
        uint v = kCompileFormatVersion;
        out_ ~= [cast(ubyte)(v & 0xff),
                 cast(ubyte)((v >> 8) & 0xff),
                 cast(ubyte)((v >> 16) & 0xff),
                 cast(ubyte)((v >> 24) & 0xff)];
        // marker
        out_ ~= cast(ubyte[]) kCompileMarker;
        write(outPath, out_);
        // chmod +x — best effort via std.file
        version (Posix)
        {
            import core.sys.posix.sys.stat : chmod, S_IRWXU, S_IRGRP, S_IXGRP,
                S_IROTH, S_IXOTH;
            import std.string : toStringz;
            chmod(outPath.toStringz, S_IRWXU | S_IRGRP | S_IXGRP | S_IROTH | S_IXOTH);
        }
        return 0;
    }
    catch (Exception e)
    {
        try stderr.writeln("compile: ", e.msg); catch (Exception) {}
        return 1;
    }
}

/++
 + Extract the embedded bundle from `exePath` if one is present.
 + Returns the bundle bytes, or null if there's no marker.
 +/
const(ubyte)[] readEmbeddedBundle(string exePath) @trusted nothrow
{
    try
    {
        if (!exists(exePath)) return null;
        auto totalSize = getSize(exePath);
        if (totalSize < kCompileTrailerSize) return null;
        auto bytes = cast(ubyte[]) read(exePath);
        // Read trailer from the end.
        size_t markerStart = bytes.length - kCompileMarker.length;
        if (bytes[markerStart .. $] != cast(ubyte[]) kCompileMarker) return null;
        // version
        size_t vOff = markerStart - uint.sizeof;
        uint v = bytes[vOff] | (cast(uint) bytes[vOff+1] << 8)
               | (cast(uint) bytes[vOff+2] << 16) | (cast(uint) bytes[vOff+3] << 24);
        if (v != kCompileFormatVersion) return null;
        // size
        size_t sOff = vOff - uint.sizeof;
        uint sz = bytes[sOff] | (cast(uint) bytes[sOff+1] << 8)
                | (cast(uint) bytes[sOff+2] << 16) | (cast(uint) bytes[sOff+3] << 24);
        if (sz == 0 || sz > sOff) return null;
        return bytes[sOff - sz .. sOff].idup;
    }
    catch (Exception) { return null; }
}
