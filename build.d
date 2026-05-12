#!/usr/bin/env rdmd
/**
 * build.d — Vendor dependency orchestrator for DunJS.
 *
 * A fully standalone build script inspired by sokol-d's pattern.
 * Downloads and builds engine backend libraries with full toolchain
 * detection, cross-platform support, retry logic, and verbose output.
 *
 * Backends:
 *   - QuickJS-NG : CMake-based build → libqjs.a (github.com/quickjs-ng/quickjs)
 *   - JSC        : System library check + header download
 *   - V8 shim    : g++/clang++ → libv8shim.a (requires system libv8-dev)
 *
 * Usage:
 *   rdmd build.d                          # Build default (quickjs)
 *   rdmd build.d --backend=quickjs        # Explicit backend
 *   rdmd build.d --backend=v8             # Build V8 shim
 *   rdmd build.d --backend=jsc            # Check JSC availability
 *   rdmd build.d --backend=all            # Build all backends
 *   rdmd build.d --clean                  # Remove vendor build artifacts
 *   rdmd build.d --verbose                # Verbose output
 *   rdmd build.d --jobs=8                 # Override parallel job count
 *   rdmd build.d --force                  # Force rebuild even if up-to-date
 *
 * Invoked from dub.json preBuildCommands:
 *   $DC -run $PACKAGE_DIR/build.d --backend=quickjs
 */
module build;

import std.algorithm : canFind, filter, map, splitter;
import std.array     : array, join;
import std.conv      : to, ConvException;
import std.file;
import std.path;
import std.process;
import std.range     : empty;
import std.stdio;
import std.string;
import std.datetime  : MonoTime, Duration, dur;
import core.thread   : Thread;

// ════════════════════════════════════════════════════════════════════
// Configuration Constants
// ════════════════════════════════════════════════════════════════════

enum Backend { quickjs, jsc, v8, all }

enum Platform { linux, macos, freebsd, windows, unknown }

/// Verbosity level for build output.
enum Verbosity { normal, verbose }

// QuickJS-NG configuration
enum QJS_REPO        = "quickjs-ng/quickjs";
enum QJS_VERSION     = "v0.14.0";
enum QJS_URL_TAGGED  = "https://github.com/" ~ QJS_REPO ~ "/archive/refs/tags/"
                     ~ QJS_VERSION ~ ".tar.gz";
enum QJS_URL_MASTER  = "https://github.com/" ~ QJS_REPO ~ "/archive/refs/heads/master.tar.gz";
version (Windows)
    enum QJS_LIB_NAME = "qjs.lib";
else
    enum QJS_LIB_NAME = "libqjs.a";
enum QJS_SRC_MARKER  = "quickjs.h";

// JavaScriptCore configuration
// Prebuilt JSC static libraries from oven-sh/WebKit (same as Bun uses).
// Falls back to system packages (libjavascriptcoregtk-4.1-dev) if download
// fails or on unsupported platforms.
enum JSC_WEBKIT_VERSION = "88b2f7a2159c913f7dd0d73c0e88d66138cd67ba";
enum JSC_PKG_NAMES      = ["javascriptcoregtk-4.1", "javascriptcoregtk-6.0", "javascriptcoregtk-4.0"];
enum JSC_LIB_MARKER     = "lib/libJavaScriptCore.a";

// V8 configuration
// Pre-built monolith from github.com/kuoruan/libv8 (preferred: self-contained, no system dep).
// Archive layout (flat root): include/ + libv8_monolith.a + gn-args_*.txt
// Fallback: system libv8-dev headers via /usr/include/v8 or Node.js headers tarball.
enum V8_PREBUILT_VERSION  = "v13.1.201.22";
enum V8_PREBUILT_BASE_URL = "https://github.com/kuoruan/libv8/releases/download/"
                            ~ V8_PREBUILT_VERSION ~ "/";
enum V8_NODE_VERSION   = "v22.15.0";   // kept for fallback header download
enum V8_HEADERS_MARKER = "v8.h";
enum V8_SYSTEM_INCLUDE = "/usr/include/v8";

// SQLite configuration
// Downloads the amalgamation source (sqlite3.c + sqlite3.h) for ImportC bindings.
// Compiled to libsqlite3.a and used by all engine backends.
enum SQLITE_VERSION     = "3490200";   // 3.49.2
enum SQLITE_YEAR        = "2025";
enum SQLITE_URL         = "https://www.sqlite.org/" ~ SQLITE_YEAR
                        ~ "/sqlite-autoconf-" ~ SQLITE_VERSION ~ ".tar.gz";
enum SQLITE_SRC_MARKER  = "sqlite3.h";

// Download retry configuration
enum DOWNLOAD_MAX_RETRIES = 3;
enum DOWNLOAD_RETRY_DELAY_SECS = 2;

// Derived paths (computed at module init via immutable + CTFE-safe dirName)
immutable PACKAGE_DIR = __FILE_FULL_PATH__.dirName;

string vendorDir()    { return buildPath(PACKAGE_DIR, "vendor"); }
string qjsDir()      { return buildPath(vendorDir(), "quickjs"); }
string qjsBuildDir() { return buildPath(qjsDir(), "build"); }
string qjsArchive()  { return buildPath(vendorDir(), "quickjs.tar.gz"); }
string jscDir()      { return buildPath(vendorDir(), "jsc"); }
string jscArchive()  { return buildPath(vendorDir(), "jsc.tar.gz"); }
string v8shimDir()   { return buildPath(vendorDir(), "v8shim"); }
string v8Dir()       { return buildPath(vendorDir(), "v8"); }
string v8IncludeDir(){ return buildPath(v8Dir(), "include"); }
string v8Archive()          { return buildPath(vendorDir(), "node-headers.tar.gz"); }
string v8PrebuiltArchive()  { return buildPath(vendorDir(), "v8-prebuilt" ~ v8PrebuiltExt()); }
string sqliteDir()          { return buildPath(vendorDir(), "sqlite"); }
string sqliteArchive()      { return buildPath(vendorDir(), "sqlite.tar.gz"); }

string v8PrebuiltExt()
{
    version (Windows) return ".7z";
    else              return ".tar.xz";
}

/// Return the kuoruan/libv8 archive URL for the current platform + arch.
string v8PrebuiltUrl()
{
    version (Windows)
    {
        return V8_PREBUILT_BASE_URL ~ "v8_Windows_x64.7z";
    }
    else version (OSX)
    {
        version (AArch64)
            return V8_PREBUILT_BASE_URL ~ "v8_macOS_arm64.tar.xz";
        else
            return V8_PREBUILT_BASE_URL ~ "v8_macOS_x64.tar.xz";
    }
    else // Linux
    {
        version (AArch64)
            return V8_PREBUILT_BASE_URL ~ "v8_Linux_aarch64.tar.xz";
        else
            return V8_PREBUILT_BASE_URL ~ "v8_Linux_x64.tar.xz";
    }
}

/// Build the download URL for Node.js headers tarball.
/// Node.js headers contain V8's public API headers (v8.h, libplatform/, cppgc/).
string nodeHeadersUrl()
{
    return "https://nodejs.org/dist/" ~ V8_NODE_VERSION
         ~ "/node-" ~ V8_NODE_VERSION ~ "-headers.tar.gz";
}

// ════════════════════════════════════════════════════════════════════
// Platform Detection
// ════════════════════════════════════════════════════════════════════

/// Detect the current build platform at runtime.
Platform detectPlatform()
{
    version (linux)   return Platform.linux;
    version (OSX)     return Platform.macos;
    version (FreeBSD) return Platform.freebsd;
    version (Windows) return Platform.windows;
    return Platform.unknown;
}

/// Human-readable platform name.
string platformName(Platform p)
{
    final switch (p)
    {
        case Platform.linux:   return "Linux";
        case Platform.macos:   return "macOS";
        case Platform.freebsd: return "FreeBSD";
        case Platform.windows: return "Windows";
        case Platform.unknown: return "Unknown";
    }
}

/// Detect the number of CPU cores for parallel builds.
int detectCpuCount()
{
    // Try /proc/cpuinfo on Linux
    version (linux)
    {
        try
        {
            auto content = readText("/proc/cpuinfo");
            int count = 0;
            foreach (line; content.lineSplitter())
            {
                if (line.startsWith("processor"))
                    count++;
            }
            if (count > 0) return count;
        }
        catch (Exception) {}
    }

    // Windows: NUMBER_OF_PROCESSORS environment variable
    version (Windows)
    {
        auto np = environment.get("NUMBER_OF_PROCESSORS", "");
        if (np.length > 0)
        {
            try { return np.to!int; }
            catch (ConvException) {}
        }
    }

    // Fallback: nproc / sysctl
    version (Windows)
        auto r = executeShell("echo %NUMBER_OF_PROCESSORS%");
    else
        auto r = executeShell("nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4");

    if (r.status == 0)
    {
        try
        {
            return r.output.strip().to!int;
        }
        catch (ConvException)
        {
            return 4;
        }
    }
    return 4;
}

/// Detect CPU architecture for prebuilt binary downloads.
string detectArch()
{
    // Windows: use PROCESSOR_ARCHITECTURE
    version (Windows)
    {
        auto arch = environment.get("PROCESSOR_ARCHITECTURE", "AMD64");
        if (arch == "AMD64" || arch == "x86_64")
            return "amd64";
        if (arch == "ARM64" || arch == "aarch64")
            return "arm64";
        return arch.toLower();
    }
    else
    {
        auto r = executeShell("uname -m 2>/dev/null");
        if (r.status == 0)
        {
            string arch = r.output.strip();
            if (arch == "x86_64" || arch == "amd64")
                return "amd64";
            if (arch == "aarch64" || arch == "arm64")
                return "arm64";
            return arch;
        }
        return "amd64";
    }
}

/// Build the download URL for prebuilt JSC from oven-sh/WebKit releases.
string jscPrebuiltUrl(Platform platform, string arch)
{
    string os;
    final switch (platform)
    {
        case Platform.linux:   os = "linux";   break;
        case Platform.macos:   os = "macos";   break;
        case Platform.freebsd: os = "freebsd"; break;
        case Platform.windows: os = "windows"; break;
        case Platform.unknown: return "";
    }
    return "https://github.com/oven-sh/WebKit/releases/download/autobuild-"
         ~ JSC_WEBKIT_VERSION ~ "/bun-webkit-" ~ os ~ "-" ~ arch ~ ".tar.gz";
}

// ════════════════════════════════════════════════════════════════════
// Toolchain Detection (sokol-d findProgram pattern)
// ════════════════════════════════════════════════════════════════════

/// Result of searching for a program on PATH.
struct ProgramInfo
{
    string name;     /// Canonical name searched for
    string path;     /// Absolute path if found, empty if not
    bool   found;    /// Whether the program was located

    string toString() const
    {
        if (found)
            return name ~ " => " ~ path;
        else
            return name ~ " => NOT FOUND";
    }
}

/**
 * Search PATH for a program by trying multiple candidate names.
 * Returns the first match found. Mirrors sokol-d's `findProgram`.
 *
 * Examples:
 *   findProgram("cmake")
 *   findProgram("g++", "c++", "clang++")
 *   findProgram("gmake", "make")
 */
ProgramInfo findProgram(string[] names...)
{
    string pathEnv = environment.get("PATH", "");
    version (Windows) enum pathSep = ";";
    else              enum pathSep = ":";

    foreach (name; names)
    {
        // Try `which` / `where` first (handles aliases, etc.)
        version (Windows)
            auto r = executeShell("where " ~ name ~ " 2>NUL");
        else
            auto r = executeShell("which " ~ name ~ " 2>/dev/null");

        if (r.status == 0)
        {
            string p = r.output.strip().lineSplitter().front;
            if (p.length > 0)
                return ProgramInfo(names[0], p, true);
        }

        // Manual PATH search as fallback
        foreach (dir; pathEnv.splitter(pathSep))
        {
            auto candidate = buildPath(dir, name);
            if (exists(candidate))
                return ProgramInfo(names[0], candidate, true);
        }
    }

    return ProgramInfo(names[0], "", false);
}

/// All tools needed by the build system.
struct Toolchain
{
    ProgramInfo cmake;
    ProgramInfo make;
    ProgramInfo cxx;       // C++ compiler (g++, clang++, c++)
    ProgramInfo cc;        // C compiler (gcc, clang, cc)
    ProgramInfo ar;        // Archiver
    ProgramInfo pkgConfig; // pkg-config
    ProgramInfo curl;      // Download tool
    ProgramInfo wget;      // Fallback download tool

    Platform platform;
    int      cpuCount;

    /// Pretty-print the detected toolchain.
    void report()
    {
        writeln("┌─────────────────────────────────────────────────");
        writeln("│ DunJS Build — Toolchain Report");
        writeln("│ Platform: ", platformName(platform),
                " (", cpuCount, " cores)");
        writeln("├─────────────────────────────────────────────────");
        writeln("│ cmake      : ", cmake);
        writeln("│ make       : ", make);
        writeln("│ C compiler : ", cc);
        writeln("│ C++ comp.  : ", cxx);
        writeln("│ ar         : ", ar);
        writeln("│ pkg-config : ", pkgConfig);
        writeln("│ curl       : ", curl);
        writeln("│ wget       : ", wget);
        writeln("└─────────────────────────────────────────────────");
    }

    /// Check if we have a working download tool (curl or wget).
    bool hasDownloader() const
    {
        return curl.found || wget.found;
    }

    /// Get the make command name (prefer gmake on BSD).
    string makeName() const
    {
        return make.found ? make.name : "make";
    }
}

/// Detect the full toolchain.
Toolchain detectToolchain()
{
    Toolchain tc;
    tc.platform = detectPlatform();
    tc.cpuCount = detectCpuCount();

    // On BSDs, prefer gmake over make
    if (tc.platform == Platform.freebsd)
        tc.make = findProgram("gmake", "make");
    else if (tc.platform == Platform.windows)
        tc.make = findProgram("nmake", "make", "mingw32-make");
    else
        tc.make = findProgram("make", "gmake");

    tc.cmake = findProgram("cmake");

    if (tc.platform == Platform.windows)
    {
        tc.cc  = findProgram("cl", "clang-cl", "gcc", "cc");
        tc.cxx = findProgram("cl", "clang-cl", "g++", "c++");
        tc.ar  = findProgram("lib", "llvm-lib", "ar", "llvm-ar");
    }
    else
    {
        tc.cc  = findProgram("cc", "gcc", "clang");
        tc.cxx = findProgram("c++", "g++", "clang++");
        tc.ar  = findProgram("ar", "llvm-ar");
    }

    tc.pkgConfig = findProgram("pkg-config", "pkgconf");
    tc.curl      = findProgram("curl");
    tc.wget      = findProgram("wget");

    return tc;
}

// ════════════════════════════════════════════════════════════════════
// Build Options
// ════════════════════════════════════════════════════════════════════

struct BuildOptions
{
    Backend   backend       = Backend.quickjs;
    Verbosity verbosity     = Verbosity.normal;
    bool      clean         = false;
    bool      force         = false;
    bool      exitRequested = false;
    int       exitCode      = 0;
    int       jobs          = 0; // 0 = auto-detect
    string    qjsUrl        = QJS_URL_TAGGED;
}

BuildOptions parseArgs(string[] args)
{
    BuildOptions opts;

    foreach (arg; args[1 .. $])
    {
        if (arg.startsWith("--backend="))
        {
            auto val = arg["--backend=".length .. $];
            switch (val)
            {
                case "quickjs": opts.backend = Backend.quickjs; break;
                case "jsc":     opts.backend = Backend.jsc;     break;
                case "v8":      opts.backend = Backend.v8;      break;
                case "all":     opts.backend = Backend.all;     break;
                default:
                    stderr.writeln("ERROR: Unknown backend '", val, "'");
                    stderr.writeln("  Valid backends: quickjs, jsc, v8, all");
                    opts.exitRequested = true;
                    opts.exitCode = 1;
                    return opts;
            }
        }
        else if (arg == "--verbose" || arg == "-v")
        {
            opts.verbosity = Verbosity.verbose;
        }
        else if (arg == "--clean")
        {
            opts.clean = true;
        }
        else if (arg == "--force" || arg == "-f")
        {
            opts.force = true;
        }
        else if (arg.startsWith("--jobs=") || arg.startsWith("-j"))
        {
            string val;
            if (arg.startsWith("--jobs="))
                val = arg["--jobs=".length .. $];
            else
                val = arg["-j".length .. $];
            try
            {
                opts.jobs = val.to!int;
            }
            catch (ConvException)
            {
                stderr.writeln("WARNING: Invalid --jobs value '", val,
                               "', using auto-detect");
            }
        }
        else if (arg == "--master")
        {
            opts.qjsUrl = QJS_URL_MASTER;
        }
        else if (arg == "--help" || arg == "-h")
        {
            printUsage();
            opts.exitRequested = true;
            return opts;
        }
        else
        {
            stderr.writeln("WARNING: Unknown argument '", arg, "' (ignored)");
        }
    }

    return opts;
}

void printUsage()
{
    writeln("Usage: rdmd build.d [OPTIONS]");
    writeln();
    writeln("Options:");
    writeln("  --backend=BACKEND   Build backend (quickjs|jsc|v8|all) [default: quickjs]");
    writeln("  --clean             Remove vendor build artifacts");
    writeln("  --force, -f         Force rebuild even if up-to-date");
    writeln("  --verbose, -v       Verbose output");
    writeln("  --jobs=N, -jN       Override parallel job count");
    writeln("  --master            Use QuickJS-NG master branch instead of tagged release");
    writeln("  --help, -h          Show this help");
}

// ════════════════════════════════════════════════════════════════════
// Logging
// ════════════════════════════════════════════════════════════════════

Verbosity g_verbosity = Verbosity.normal;

void logInfo(string tag, lazy string msg)
{
    writeln("[", tag, "] ", msg);
    stdout.flush();
}

void logVerbose(string tag, lazy string msg)
{
    if (g_verbosity == Verbosity.verbose)
    {
        writeln("[", tag, "] (verbose) ", msg);
        stdout.flush();
    }
}

void logError(string tag, lazy string msg)
{
    stderr.writeln("[", tag, "] ERROR: ", msg);
    stderr.flush();
}

void logWarning(string tag, lazy string msg)
{
    stderr.writeln("[", tag, "] WARNING: ", msg);
    stderr.flush();
}

void logStep(string tag, int step, int total, lazy string msg)
{
    writeln("[", tag, "] [", step, "/", total, "] ", msg);
    stdout.flush();
}

// ════════════════════════════════════════════════════════════════════
// Process Execution
// ════════════════════════════════════════════════════════════════════

/// Run a command in a given working directory.
/// Returns exit code. Prints output on failure (or always in verbose mode).
int runCmd(string[] cmd, string workDir, string tag = "build")
{
    logVerbose(tag, "exec: " ~ cmd.join(" "));
    logVerbose(tag, "  in: " ~ workDir);

    auto startTime = MonoTime.currTime;

    try
    {
        auto r = execute(cmd, null, Config.none, size_t.max, workDir);

        auto elapsed = MonoTime.currTime - startTime;

        if (r.status != 0)
        {
            auto elapsedStr = fmtSecs(elapsed.total!"msecs");
            logError(tag, "Command failed (exit " ~ r.status.to!string
                        ~ ", " ~ elapsedStr ~ "): " ~ cmd.join(" "));
            if (r.output.length > 0)
                stderr.writeln(r.output);
            return r.status;
        }

        logVerbose(tag, "  ok (" ~ fmtSecs(elapsed.total!"msecs") ~ ")");

        if (g_verbosity == Verbosity.verbose && r.output.length > 0)
            write(r.output);

        return 0;
    }
    catch (ProcessException e)
    {
        logError(tag, "Failed to execute: " ~ cmd.join(" "));
        logError(tag, e.msg);
        return -1;
    }
}

/// Run a shell command string. For simple one-liners.
int runShell(string cmd, string tag = "build")
{
    logVerbose(tag, "shell: " ~ cmd);
    auto r = executeShell(cmd);
    if (r.status != 0 && g_verbosity == Verbosity.verbose)
        stderr.writeln(r.output);
    return r.status;
}

// ════════════════════════════════════════════════════════════════════
// Download with Retry Logic
// ════════════════════════════════════════════════════════════════════

/// Download a URL to a local file, with retry logic.
/// Tries curl first, falls back to wget.
bool downloadFile(ref const Toolchain tc, string url, string dest, string tag = "download")
{
    logInfo(tag, "Downloading: " ~ url);
    logVerbose(tag, "  -> " ~ dest);

    // Ensure parent directory exists
    auto parentDir = dirName(dest);
    if (!exists(parentDir))
        mkdirRecurse(parentDir);

    for (int attempt = 1; attempt <= DOWNLOAD_MAX_RETRIES; attempt++)
    {
        if (attempt > 1)
        {
            logWarning(tag, "Retry " ~ attempt.to!string ~ "/"
                          ~ DOWNLOAD_MAX_RETRIES.to!string
                          ~ " after " ~ DOWNLOAD_RETRY_DELAY_SECS.to!string
                          ~ " second delay...");
            Thread.sleep(dur!"seconds"(DOWNLOAD_RETRY_DELAY_SECS));
        }

        int status;

        if (tc.curl.found)
        {
            // curl: -S show errors, -L follow redirects, -f fail on HTTP errors,
            //       --connect-timeout 30, --retry 0 (we handle retries)
            string cmd = tc.curl.path ~ " -SLf --connect-timeout 30 --retry 0 -o "
                       ~ shellQuote(dest) ~ " " ~ shellQuote(url);
            status = runShell(cmd, tag);
        }
        else if (tc.wget.found)
        {
            string cmd = tc.wget.path ~ " -q --timeout=30 -O "
                       ~ shellQuote(dest) ~ " " ~ shellQuote(url);
            status = runShell(cmd, tag);
        }
        else
        {
            logError(tag, "No download tool found (need curl or wget)");
            return false;
        }

        if (status == 0 && exists(dest))
        {
            // Verify the file is not empty
            auto sz = getSize(dest);
            if (sz > 0)
            {
                logInfo(tag, "Downloaded " ~ baseName(dest)
                           ~ " (" ~ fmtKB(sz) ~ ")");
                return true;
            }
            else
            {
                logWarning(tag, "Downloaded file is empty, retrying...");
                std.file.remove(dest);
            }
        }
        else
        {
            // Clean up partial download
            if (exists(dest))
                std.file.remove(dest);
        }
    }

    logError(tag, "Download failed after " ~ DOWNLOAD_MAX_RETRIES.to!string
                 ~ " attempts: " ~ url);
    return false;
}

/// Quote a string for shell use.
string shellQuote(string s)
{
    version (Windows)
    {
        // Windows cmd: wrap in double quotes, escape internal double quotes
        return "\"" ~ s.replace("\"", "\\\"") ~ "\"";
    }
    else
    {
        // POSIX: wrap in single quotes, escape internal single quotes
        return "'" ~ s.replace("'", "'\\''") ~ "'";
    }
}

// ════════════════════════════════════════════════════════════════════
// Shared Download & Extract Helper
// ════════════════════════════════════════════════════════════════════

/**
 * Download a source tarball from a URL and extract it into a destination
 * directory.  Skips the download when `marker` (a path relative to `destDir`)
 * already exists, indicating a previous successful extraction.
 *
 * This is the common pattern used by every backend that fetches vendor
 * sources from GitHub:
 *   1. If marker file exists → skip (already extracted).
 *   2. Remove any stale `destDir`.
 *   3. Download the tarball to `archive`.
 *   4. Extract with `tar --strip-components=1`.
 *   5. Verify the marker file appeared.
 *   6. Delete the archive.
 *
 * Params:
 *   tc       = Detected toolchain (for download tool).
 *   url      = Remote URL of the .tar.gz archive.
 *   archive  = Local path for the downloaded archive.
 *   destDir  = Directory to extract into.
 *   marker   = Relative path inside `destDir` whose existence proves success.
 *   tag      = Logging tag (e.g. "quickjs", "jsc", "v8").
 *
 * Returns: `true` on success (or if already present), `false` on failure.
 */
bool downloadAndExtract(ref const Toolchain tc, string url, string archive,
                         string destDir, string marker, string tag)
{
    immutable markerPath = buildPath(destDir, marker);

    if (exists(markerPath))
    {
        logInfo(tag, "Source already present -- skipping download");
        return true;
    }

    // Require a download tool
    if (!tc.hasDownloader())
    {
        logError(tag, "No download tool (curl/wget) found.");
        return false;
    }

    // Clean any partial previous download
    if (exists(destDir))
    {
        logVerbose(tag, "Removing stale source directory...");
        rmdirRecurse(destDir);
    }

    mkdirRecurse(vendorDir());

    // Download the tarball
    if (!downloadFile(tc, url, archive, tag))
        return false;

    // Extract (tar is built into Windows 10+ and all POSIX systems)
    logVerbose(tag, "Extracting archive...");
    mkdirRecurse(destDir);

    int exStatus = runCmd(
        ["tar", "-xzf", archive, "--strip-components=1", "-C", destDir],
        vendorDir(), tag);

    if (exStatus != 0)
    {
        logError(tag, "Failed to extract archive");
        return false;
    }

    // Clean up archive
    if (exists(archive))
        std.file.remove(archive);

    // Verify extraction
    if (!exists(markerPath))
    {
        logError(tag, "Extraction succeeded but " ~ marker ~ " not found -- "
                    ~ "archive structure may have changed");
        return false;
    }

    logInfo(tag, "Source downloaded and extracted");
    return true;
}

// ════════════════════════════════════════════════════════════════════
// SQLite (cross-cutting dependency, used by all backends)
// ════════════════════════════════════════════════════════════════════

bool buildSqlite(ref const Toolchain tc, ref const BuildOptions opts)
{
    enum tag = "sqlite";
    immutable headerPath = buildPath(sqliteDir(), "sqlite3.h");
    version (Windows)
        immutable libName = "sqlite3.lib";
    else
        immutable libName = "libsqlite3.a";
    immutable libPath = buildPath(sqliteDir(), libName);

    if (!opts.force && exists(headerPath) && exists(libPath))
    {
        logInfo(tag, libName ~ " already built -- skipping (use --force to rebuild)");
        return true;
    }

    // If header already present (e.g. from system or previous download) but no lib, just compile
    if (!exists(headerPath))
    {
        logInfo(tag, "Downloading SQLite amalgamation " ~ SQLITE_VERSION ~ "...");

        if (!tc.hasDownloader())
        {
            // Fallback: try system header
            if (exists("/usr/include/sqlite3.h"))
            {
                logInfo(tag, "Using system sqlite3.h as fallback");
                mkdirRecurse(sqliteDir());
                runShell("cp /usr/include/sqlite3.h " ~ shellQuote(headerPath), tag);
                // Create ImportC bridge
                auto bridgePath = buildPath(sqliteDir(), "sqlite3_api.c");
                if (!exists(bridgePath))
                {
                    import std.file : write;
                    write(bridgePath,
                        "// ImportC bridge: processes sqlite3.h declarations for D import\n"
                        ~ "#include \"sqlite3.h\"\n");
                }
                logInfo(tag, "sqlite3.h installed (system fallback, linking against -lsqlite3)");
                return true;
            }
            logError(tag, "No download tool (curl/wget) found and no system sqlite3.h");
            return false;
        }

        if (!downloadAndExtract(tc, SQLITE_URL, sqliteArchive(),
                                 sqliteDir(), SQLITE_SRC_MARKER, tag))
            return false;
    }

    // Create ImportC bridge if not present
    auto bridgePath = buildPath(sqliteDir(), "sqlite3_api.c");
    if (!exists(bridgePath))
    {
        import std.file : write;
        write(bridgePath,
            "// ImportC bridge: processes sqlite3.h declarations for D import\n"
            ~ "#include \"sqlite3.h\"\n");
    }

    // Compile sqlite3.c if present (amalgamation download includes it)
    auto sqliteC = buildPath(sqliteDir(), "sqlite3.c");
    if (exists(sqliteC) && !exists(libPath))
    {
        logInfo(tag, "Compiling sqlite3.c -> " ~ libName ~ " ...");

        if (!tc.cc.found)
        {
            logWarning(tag, "No C compiler found; will link against system -lsqlite3");
            return true;
        }

        auto objFile = buildPath(sqliteDir(), "sqlite3.o");
        int rc = runCmd([tc.cc.path, "-c", "-fPIC", "-O2", "-DSQLITE_THREADSAFE=0",
                         "-DSQLITE_OMIT_LOAD_EXTENSION", sqliteC, "-o", objFile],
                         sqliteDir(), tag);
        if (rc != 0)
        {
            logError(tag, "Failed to compile sqlite3.c");
            return false;
        }

        rc = runCmd(["ar", "rcs", libPath, objFile], sqliteDir(), tag);
        if (rc != 0)
        {
            logError(tag, "Failed to create " ~ libName);
            return false;
        }

        // Clean up .o file
        if (exists(objFile))
            std.file.remove(objFile);

        logInfo(tag, libName ~ " built successfully");
    }

    return true;
}

// ════════════════════════════════════════════════════════════════════
// QuickJS-NG Backend
// ════════════════════════════════════════════════════════════════════

/**
 * Build QuickJS-NG from source using CMake.
 *
 * Steps:
 *   1. Download source tarball from github.com/quickjs-ng/quickjs
 *   2. Extract to vendor/quickjs/
 *   3. Configure with CMake (static library, PIC, Release)
 *   4. Build with make → libqjs.a
 */
bool buildQuickJS(ref const Toolchain tc, ref const BuildOptions opts)
{
    enum tag = "quickjs";
    immutable libPath = buildPath(qjsBuildDir(), QJS_LIB_NAME);

    // Skip if already built (unless --force)
    if (!opts.force && exists(libPath))
    {
        logInfo(tag, QJS_LIB_NAME ~ " already built -- skipping (use --force to rebuild)");
        return true;
    }

    logInfo(tag, "Building QuickJS-NG " ~ QJS_VERSION ~ "...");
    auto startTime = MonoTime.currTime;

    // ── Step 1: Validate required tools ────────────────────────────
    logStep(tag, 1, 4, "Checking required tools...");

    if (!tc.cmake.found)
    {
        logError(tag, "CMake not found. Install cmake (e.g., apt install cmake).");
        return false;
    }
    if (!tc.make.found && tc.platform != Platform.windows)
    {
        logError(tag, "Make not found. Install make (e.g., apt install make).");
        return false;
    }
    // On Windows, cmake finds MSVC via registry; CC in PATH is optional
    if (!tc.cc.found && tc.platform != Platform.windows)
    {
        logError(tag, "C compiler not found. Install gcc or clang.");
        return false;
    }
    if (!tc.hasDownloader())
    {
        logError(tag, "No download tool (curl/wget) found.");
        return false;
    }

    logVerbose(tag, "cmake: " ~ tc.cmake.path);
    logVerbose(tag, "make:  " ~ tc.make.path);
    logVerbose(tag, "cc:    " ~ tc.cc.path);

    // ── Step 2: Download source ────────────────────────────────────
    logStep(tag, 2, 4, "Downloading source...");

    if (!downloadAndExtract(tc, opts.qjsUrl, qjsArchive(),
                             qjsDir(), QJS_SRC_MARKER, tag))
        return false;

    // ── Step 3: Configure with CMake ───────────────────────────────
    logStep(tag, 3, 4, "Configuring with CMake...");

    immutable bDir = qjsBuildDir();

    // If forcing, clean old build directory
    if (opts.force && exists(bDir))
    {
        logVerbose(tag, "Cleaning old build directory (--force)...");
        rmdirRecurse(bDir);
    }

    mkdirRecurse(bDir);

    // Detect if Ninja is available (preferred on Windows for single-config builds)
    bool useNinja = false;
    if (tc.platform == Platform.windows)
    {
        auto ninjaCheck = executeShell("ninja --version 2>NUL");
        useNinja = (ninjaCheck.status == 0);
        if (useNinja)
            logInfo(tag, "Using Ninja generator (single-config)");
        else
            logInfo(tag, "Using default CMake generator (multi-config, --config Release)");
    }

    string[] cmakeArgs = [
        tc.cmake.path,
        "..",
        "-DBUILD_SHARED_LIBS=OFF",
        "-DBUILD_EXAMPLES=OFF",
    ];

    if (tc.platform == Platform.windows)
    {
        // LDC links with the static CRT (/MT). QuickJS must match to avoid
        // unresolved __imp_* math symbols (acosh, asinh, fesetround, etc.)
        // CMP0091 (CMake 3.15) must be NEW for CMAKE_MSVC_RUNTIME_LIBRARY to work;
        // QuickJS sets cmake_minimum_required(3.10), so the policy defaults to OLD.
        cmakeArgs ~= "-DCMAKE_POLICY_DEFAULT_CMP0091=NEW";
        cmakeArgs ~= "-DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded";
        // Belt-and-suspenders: force /MT via C flags in case CMP0091 doesn't
        // take effect (e.g. QuickJS CMakeLists overrides flags manually).
        cmakeArgs ~= `-DCMAKE_C_FLAGS=/MT /O2 /DNDEBUG`;
        cmakeArgs ~= `-DCMAKE_C_FLAGS_RELEASE=/MT /O2 /DNDEBUG`;
        cmakeArgs ~= `-DCMAKE_C_FLAGS_DEBUG=/MTd /Od`;

        if (useNinja)
        {
            // Ninja is single-config, so CMAKE_BUILD_TYPE works correctly
            cmakeArgs ~= "-G";
            cmakeArgs ~= "Ninja";
            cmakeArgs ~= "-DCMAKE_BUILD_TYPE=Release";
        }
        // For Visual Studio (multi-config), CMAKE_BUILD_TYPE is ignored;
        // we pass --config Release on the cmake --build step instead
    }
    else
    {
        cmakeArgs ~= "-DCMAKE_BUILD_TYPE=Release";
        cmakeArgs ~= "-DCMAKE_C_FLAGS=-fPIC -O2 -Wno-discarded-qualifiers";

        // Use detected C compiler
        if (tc.cc.found)
            cmakeArgs ~= "-DCMAKE_C_COMPILER=" ~ tc.cc.path;
    }

    // macOS: set minimum deployment target
    if (tc.platform == Platform.macos)
        cmakeArgs ~= "-DCMAKE_OSX_DEPLOYMENT_TARGET=11.0";

    if (g_verbosity == Verbosity.verbose)
        cmakeArgs ~= "-DCMAKE_VERBOSE_MAKEFILE=ON";

    if (runCmd(cmakeArgs, bDir, tag) != 0)
    {
        logError(tag, "CMake configuration failed");
        logError(tag, "  Check that cmake >= 3.15 is installed");
        return false;
    }

    // ── Step 4: Build ──────────────────────────────────────────────
    int jobCount = opts.jobs > 0 ? opts.jobs : tc.cpuCount;
    logStep(tag, 4, 4, "Compiling with " ~ jobCount.to!string ~ " parallel jobs...");

    // Use cmake --build for cross-platform compatibility (works with Make, Ninja, MSVC)
    string[] buildCmd = [
        tc.cmake.path, "--build", ".",
        "--target", "qjs",
        "-j", jobCount.to!string,
    ];

    // For multi-config generators (Visual Studio), must pass --config Release
    if (tc.platform == Platform.windows && !useNinja)
    {
        buildCmd ~= "--config";
        buildCmd ~= "Release";
    }

    if (runCmd(buildCmd, bDir, tag) != 0)
    {
        // Retry with single job for clearer error output
        logWarning(tag, "Parallel build failed, retrying with -j 1...");
        string[] retryCmd = [
            tc.cmake.path, "--build", ".",
            "--target", "qjs",
            "-j", "1",
        ];

        if (tc.platform == Platform.windows && !useNinja)
        {
            retryCmd ~= "--config";
            retryCmd ~= "Release";
        }

        if (runCmd(retryCmd, bDir, tag) != 0)
        {
            logError(tag, "QuickJS-NG compilation failed");
            return false;
        }
    }

    // ── Verify ─────────────────────────────────────────────────────
    // MSVC multi-config generators put output in Release/ subdirectory
    if (!exists(libPath))
    {
        auto releasePath = buildPath(bDir, "Release", QJS_LIB_NAME);
        if (exists(releasePath))
        {
            logVerbose(tag, "Copying from Release/ subdirectory...");
            copy(releasePath, libPath);
        }
    }

    if (!exists(libPath))
    {
        // Search the build tree and copy to expected location
        logVerbose(tag, "Searching build tree for " ~ QJS_LIB_NAME ~ "...");
        version (Windows)
            auto findResult = executeShell(
                "where /R " ~ shellQuote(bDir) ~ " " ~ QJS_LIB_NAME ~ " 2>NUL");
        else
            auto findResult = executeShell(
                "find " ~ shellQuote(bDir) ~ " -name '" ~ QJS_LIB_NAME ~ "' 2>/dev/null");
        if (findResult.status == 0 && findResult.output.strip().length > 0)
        {
            auto foundPath = findResult.output.strip().lineSplitter().front;
            logInfo(tag, "Found at " ~ foundPath ~ ", copying to " ~ libPath);
            copy(foundPath, libPath);
        }
    }

    if (!exists(libPath))
    {
        logError(tag, QJS_LIB_NAME ~ " not found anywhere in build tree: " ~ bDir);
        return false;
    }

    auto elapsed = MonoTime.currTime - startTime;
    auto libSize = getSize(libPath);

    logInfo(tag, "Built " ~ QJS_LIB_NAME ~ " (" ~ fmtKB(libSize) ~ ") in "
               ~ fmtSecs(elapsed.total!"msecs"));
    logInfo(tag, "  " ~ libPath);

    return true;
}

// ════════════════════════════════════════════════════════════════════
// JavaScriptCore Backend
// ════════════════════════════════════════════════════════════════════

/**
 * Check JSC system availability and optionally download WebKitGTK source.
 *
 * On Linux:  Prefers libjavascriptcoregtk-4.1-dev via pkg-config.
 *            Falls back to downloading WebKitGTK source from GitHub when
 *            system packages are unavailable and a download tool exists.
 * On macOS:  Uses system JavaScriptCore.framework.
 */
/**
 * Build/fetch JSC static libraries.
 *
 * Resolution order:
 *   1. Vendor dir already populated → skip
 *   2. Download prebuilt from oven-sh/WebKit releases (Bun's approach)
 *   3. System packages via pkg-config (libjavascriptcoregtk)
 *   4. macOS system framework
 */
bool checkJSC(ref const Toolchain tc, ref const BuildOptions opts)
{
    enum tag = "jsc";
    immutable markerPath = buildPath(jscDir(), JSC_LIB_MARKER);

    // Already fetched
    if (!opts.force && exists(markerPath))
    {
        logInfo(tag, "Prebuilt JSC already present -- skipping (use --force to re-download)");
        return true;
    }

    logInfo(tag, "Setting up JavaScriptCore...");

    // ── macOS: system framework is sufficient ─────────────────────
    if (tc.platform == Platform.macos)
    {
        if (exists("/System/Library/Frameworks/JavaScriptCore.framework"))
        {
            logInfo(tag, "Using system JavaScriptCore.framework");
            return true;
        }
    }

    // ── Try prebuilt download (Bun's oven-sh/WebKit releases) ─────
    if (tc.hasDownloader())
    {
        string arch = detectArch();
        string url = jscPrebuiltUrl(tc.platform, arch);

        if (url.length > 0)
        {
            logInfo(tag, "Downloading prebuilt JSC (" ~ platformName(tc.platform)
                       ~ "/" ~ arch ~ ")...");

            if (downloadAndExtract(tc, url, jscArchive(),
                                    jscDir(), JSC_LIB_MARKER, tag))
            {
                auto libPath = buildPath(jscDir(), "lib", "libJavaScriptCore.a");
                if (exists(libPath))
                    logInfo(tag, "JSC static library: " ~ fmtKB(getSize(libPath)));
                logInfo(tag, "Prebuilt JSC ready at " ~ jscDir());
                return true;
            }

            logWarning(tag, "Prebuilt download failed -- trying system packages");
        }
    }

    // ── System packages fallback (Linux/FreeBSD) ──────────────────
    if (tc.platform == Platform.linux || tc.platform == Platform.freebsd)
        return checkJSCSystem(tc, tag);

    logError(tag, "JSC not available on " ~ platformName(tc.platform));
    return false;
}

bool checkJSCSystem(ref const Toolchain tc, string tag)
{
    if (tc.pkgConfig.found)
    {
        foreach (pkgName; JSC_PKG_NAMES)
        {
            auto r = executeShell(
                tc.pkgConfig.path ~ " --exists " ~ pkgName ~ " 2>/dev/null");
            if (r.status == 0)
            {
                auto ver = executeShell(
                    tc.pkgConfig.path ~ " --modversion " ~ pkgName);
                logInfo(tag, "Found system " ~ pkgName ~ " version "
                           ~ ver.output.strip());
                return true;
            }
        }
    }

    if (exists("/usr/include/webkitgtk-4.1/jsc/jsc.h") ||
        exists("/usr/include/webkitgtk-6.0/jsc/jsc.h"))
    {
        logInfo(tag, "Found JSC headers via direct path check");
        return true;
    }

    logError(tag, "JavaScriptCore not found. Install system packages:");
    logError(tag, "  Ubuntu/Debian: apt install libjavascriptcoregtk-4.1-dev");
    logError(tag, "  Fedora:        dnf install webkit2gtk4.1-devel");
    logError(tag, "  Arch:          pacman -S webkit2gtk-4.1");
    return false;
}

// ════════════════════════════════════════════════════════════════════
// V8 Shim Backend
// ════════════════════════════════════════════════════════════════════

/**
 * Locate V8 runtime libraries and stage them in vendor/v8/lib/ so DUB can
 * link against them regardless of where they live on the host system.
 *
 * Search order:
 *   1. Already staged in vendor/v8/lib/ (previous run)
 *   2. libv8_monolith.a — single-archive build used by Arch AUR, Android NDK
 *   3. Split libv8.a + libv8_libplatform.a — Debian/Ubuntu libv8-dev
 *   4. pkg-config v8 / v8-314 / libv8
 *
 * When the monolith is found the function creates:
 *   vendor/v8/lib/libv8.a          -> symlink to monolith
 *   vendor/v8/lib/libv8_libplatform.a -> empty stub (symbols are in monolith)
 *
 * Returns true if V8 libs are now in vendor/v8/lib/, false otherwise.
 */
bool checkV8Libs(ref const Toolchain tc, ref const BuildOptions opts)
{
    enum tag = "v8";
    immutable libDir = buildPath(v8Dir(), "lib");
    immutable stagedV8   = buildPath(libDir, "libv8.a");
    immutable stagedPlat = buildPath(libDir, "libv8_libplatform.a");

    // Already staged from a previous run
    if (exists(stagedV8) && exists(stagedPlat) && !opts.force)
    {
        logInfo(tag, "V8 libs already staged in vendor/v8/lib/ -- skipping");
        return true;
    }

    mkdirRecurse(libDir);

    // Helper: symlink or copy a file
    bool stageFile(string src, string dst)
    {
        if (exists(dst)) remove(dst);
        version (Posix)
        {
            import core.sys.posix.unistd : symlink;
            import std.string : toStringz;
            if (symlink(src.toStringz, dst.toStringz) != 0)
            {
                std.file.copy(src, dst);
            }
        }
        else
        {
            std.file.copy(src, dst);
        }
        return exists(dst);
    }

    // Helper: create a minimal empty archive stub
    bool createEmptyArchive(string path)
    {
        if (!tc.ar.found) return false;
        // Write a tiny stub .o, archive it, then remove the .o
        immutable stubO = path ~ ".stub.o";
        version (Posix)
        {
            import std.process : executeShell;
            // Write an empty C source and compile it to a tiny .o
            auto r = executeShell(
                "printf 'void __v8_platform_stub(void){}' | " ~
                tc.cxx.path ~ " -x c -O0 -c - -o " ~ stubO ~ " 2>/dev/null");
            if (r.status != 0) return false;
            r = executeShell(tc.ar.path ~ " rcs " ~ path ~ " " ~ stubO ~ " 2>/dev/null");
            remove(stubO);
            return r.status == 0;
        }
        else
        {
            return false;
        }
    }

    // --- Search for monolith ----------------------------------------
    static immutable string[] monolithCandidates = [
        "/usr/lib/libv8_monolith.a",
        "/usr/local/lib/libv8_monolith.a",
        "/usr/lib/x86_64-linux-gnu/libv8_monolith.a",
        "/usr/lib/aarch64-linux-gnu/libv8_monolith.a",
    ];

    foreach (candidate; monolithCandidates)
    {
        if (exists(candidate))
        {
            logInfo(tag, "Found V8 monolith: " ~ candidate);
            if (stageFile(candidate, stagedV8) && createEmptyArchive(stagedPlat))
            {
                logInfo(tag, "V8 libs staged from monolith in vendor/v8/lib/");
                return true;
            }
        }
    }

    // --- Search for split libs --------------------------------------
    static immutable string[][] splitCandidatePairs = [
        ["/usr/lib/libv8.a",                    "/usr/lib/libv8_libplatform.a"],
        ["/usr/local/lib/libv8.a",              "/usr/local/lib/libv8_libplatform.a"],
        ["/usr/lib/x86_64-linux-gnu/libv8.a",   "/usr/lib/x86_64-linux-gnu/libv8_libplatform.a"],
        ["/usr/lib/aarch64-linux-gnu/libv8.a",  "/usr/lib/aarch64-linux-gnu/libv8_libplatform.a"],
    ];

    foreach (pair; splitCandidatePairs)
    {
        if (exists(pair[0]) && exists(pair[1]))
        {
            logInfo(tag, "Found V8 split libs: " ~ pair[0]);
            if (stageFile(pair[0], stagedV8) && stageFile(pair[1], stagedPlat))
            {
                logInfo(tag, "V8 libs staged in vendor/v8/lib/");
                return true;
            }
        }
    }

    // --- Try pkg-config ---------------------------------------------
    version (Posix)
    if (tc.pkgConfig.found)
    {
        foreach (pcName; ["v8", "v8-314", "libv8"])
        {
            import std.process : executeShell;
            auto r = executeShell(tc.pkgConfig.path ~ " --libs-only-L " ~ pcName ~ " 2>/dev/null");
            if (r.status == 0)
            {
                // Extract -L paths and search there for the libs
                import std.algorithm : filter, map;
                import std.array : array;
                foreach (token; r.output.split())
                {
                    if (token.length > 2 && token[0 .. 2] == "-L")
                    {
                        string libPath = token[2 .. $];
                        string v8a   = buildPath(libPath, "libv8.a");
                        string platA = buildPath(libPath, "libv8_libplatform.a");
                        if (exists(v8a) && exists(platA))
                        {
                            logInfo(tag, "Found V8 via pkg-config (" ~ pcName ~ "): " ~ libPath);
                            if (stageFile(v8a, stagedV8) && stageFile(platA, stagedPlat))
                            {
                                logInfo(tag, "V8 libs staged in vendor/v8/lib/");
                                return true;
                            }
                        }
                        string mono = buildPath(libPath, "libv8_monolith.a");
                        if (exists(mono))
                        {
                            logInfo(tag, "Found V8 monolith via pkg-config (" ~ pcName ~ "): " ~ mono);
                            if (stageFile(mono, stagedV8) && createEmptyArchive(stagedPlat))
                            {
                                logInfo(tag, "V8 libs staged from monolith in vendor/v8/lib/");
                                return true;
                            }
                        }
                    }
                }
            }
        }
    }

    // --- Try auto-download from kuoruan/libv8 prebuilt ---------------
    logInfo(tag, "Attempting auto-download of V8 prebuilt from github.com/kuoruan/libv8...");
    if (downloadV8Prebuilt(tc, opts) && exists(stagedV8) && exists(stagedPlat))
    {
        logInfo(tag, "V8 libs ready via prebuilt download");
        return true;
    }

    // --- Nothing found — print instructions and fail ----------------
    logError(tag, "V8 runtime libraries not found. Install them for your platform:");
    logError(tag, "");
    logError(tag, "  Arch Linux (AUR):    yay -S v8         (provides libv8_monolith.a)");
    logError(tag, "  Debian/Ubuntu:       apt install libv8-dev");
    logError(tag, "  Fedora/RHEL:         dnf install v8-devel");
    logError(tag, "  macOS (Homebrew):    brew install v8");
    logError(tag, "");
    logError(tag, "  Or manually place libv8.a + libv8_libplatform.a in vendor/v8/lib/");
    logError(tag, "  (libv8_monolith.a is also accepted as a single-archive alternative)");
    return false;
}

/**
 * Build the V8 shim library (a thin C++ wrapper around V8's C++ API).
 *
 * Prefers system-installed libv8-dev headers.  When system headers are
 * absent and a download tool is available, falls back to downloading V8
 * source from GitHub for the headers.
 *
 * Compiles vendor/v8shim/v8shim.cpp → libv8shim.a
 */
bool buildV8Shim(ref const Toolchain tc, ref const BuildOptions opts)
{
    enum tag = "v8";
    immutable srcPath = buildPath(v8shimDir(), "v8shim.cpp");
    version (Windows)
        immutable libPath = buildPath(v8shimDir(), "v8shim.lib");
    else
        immutable libPath = buildPath(v8shimDir(), "libv8shim.a");
    immutable objPath = buildPath(v8shimDir(), "v8shim.o");

    // Skip if already built (unless --force)
    if (!opts.force && exists(libPath))
    {
        logInfo(tag, "libv8shim.a already built -- skipping (use --force to rebuild)");
        return true;
    }

    logInfo(tag, "Building V8 shim...");
    auto startTime = MonoTime.currTime;

    // ── Validate ───────────────────────────────────────────────────
    if (!exists(srcPath))
    {
        logError(tag, "v8shim.cpp not found at: " ~ srcPath);
        logError(tag, "  The V8 shim source must be placed in vendor/v8shim/");
        return false;
    }

    if (!tc.cxx.found)
    {
        logError(tag, "C++ compiler not found. Install g++ or clang++.");
        return false;
    }

    if (!tc.ar.found)
    {
        logError(tag, "Archiver (ar) not found.");
        return false;
    }

    // ── Locate V8 headers ─────────────────────────────────────────
    // Resolution order:
    //   1. Vendored headers (vendor/v8/include/) — downloaded from Node.js
    //   2. System headers (/usr/include/v8) — libv8-dev
    //   3. pkg-config v8
    //   4. Download from Node.js headers tarball (node method)
    string v8Includes = "";
    bool v8PkgConfig = false;

    if (exists(buildPath(v8IncludeDir(), "v8.h")))
    {
        v8Includes = v8IncludeDir();
        logVerbose(tag, "V8 headers found (vendored): " ~ v8Includes);
    }
    else if (exists(buildPath(V8_SYSTEM_INCLUDE, "v8.h")))
    {
        v8Includes = V8_SYSTEM_INCLUDE;
        logVerbose(tag, "V8 headers found (system): " ~ V8_SYSTEM_INCLUDE);
    }
    else if (tc.pkgConfig.found)
    {
        auto r = executeShell(
            tc.pkgConfig.path ~ " --exists v8 2>/dev/null");
        if (r.status == 0)
        {
            v8PkgConfig = true;
            logVerbose(tag, "V8 found via pkg-config");
        }
    }

    // Download V8 headers from Node.js if not found locally
    if (v8Includes.length == 0 && !v8PkgConfig)
    {
        logInfo(tag, "V8 headers not found locally — downloading from Node.js...");
        if (downloadV8Headers(tc))
        {
            v8Includes = v8IncludeDir();
            logInfo(tag, "V8 headers vendored at " ~ v8Includes);
        }
        else
        {
            logError(tag, "V8 headers not available. Options:");
            logError(tag, "  1. Install libv8-dev (apt install libv8-dev)");
            logError(tag, "  2. Ensure curl/wget available for auto-download");
            return false;
        }
    }

    logVerbose(tag, "C++ compiler: " ~ tc.cxx.path);
    logVerbose(tag, "Archiver:     " ~ tc.ar.path);

    // ── Build: prefer CMake when available, fallback to manual ────
    immutable cmakeLists = buildPath(v8shimDir(), "CMakeLists.txt");
    bool useCMake = tc.cmake.found && exists(cmakeLists);

    if (useCMake)
    {
        logInfo(tag, "Building v8shim via CMake...");

        immutable bDir = buildPath(v8shimDir(), "build");

        if (opts.force && exists(bDir))
            rmdirRecurse(bDir);

        mkdirRecurse(bDir);

        string[] cmakeArgs = [
            tc.cmake.path, "..",
            "-DCMAKE_BUILD_TYPE=Release",
        ];

        if (v8Includes.length > 0)
            cmakeArgs ~= "-DV8_INCLUDE_DIR=" ~ v8Includes;

        if (tc.platform == Platform.windows)
        {
            cmakeArgs ~= "-DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded";
            // Detect Ninja for single-config builds
            auto ninjaCheck = executeShell("ninja --version 2>NUL");
            if (ninjaCheck.status == 0)
            {
                cmakeArgs ~= "-G";
                cmakeArgs ~= "Ninja";
            }
        }

        logStep(tag, 1, 2, "Configuring with CMake...");
        if (runCmd(cmakeArgs, bDir, tag) != 0)
        {
            logWarning(tag, "CMake configure failed -- falling back to manual build");
            useCMake = false;
        }

        if (useCMake)
        {
            logStep(tag, 2, 2, "Compiling...");
            int jobCount = opts.jobs > 0 ? opts.jobs : tc.cpuCount;
            string[] buildCmd = [
                tc.cmake.path, "--build", ".", "-j", jobCount.to!string,
            ];

            if (tc.platform == Platform.windows)
            {
                auto ninjaCheck = executeShell("ninja --version 2>NUL");
                if (ninjaCheck.status != 0)
                {
                    buildCmd ~= "--config";
                    buildCmd ~= "Release";
                }
            }

            if (runCmd(buildCmd, bDir, tag) != 0)
            {
                logWarning(tag, "CMake build failed -- falling back to manual build");
                useCMake = false;
            }
            else
            {
                // Copy built library to expected location
                version (Windows)
                    immutable builtLib = buildPath(bDir, "v8shim.lib");
                else
                    immutable builtLib = buildPath(bDir, "libv8shim.a");

                if (exists(builtLib))
                    std.file.copy(builtLib, libPath);

                // Also check Release/ subdirectory (MSVC multi-config)
                if (!exists(libPath))
                {
                    version (Windows)
                        immutable releaseLib = buildPath(bDir, "Release", "v8shim.lib");
                    else
                        immutable releaseLib = buildPath(bDir, "Release", "libv8shim.a");
                    if (exists(releaseLib))
                        std.file.copy(releaseLib, libPath);
                }
            }
        }
    }

    if (!useCMake)
    {
        // ── Manual compile + archive fallback ─────────────────────
        logStep(tag, 1, 2, "Compiling v8shim.cpp...");

        string[] compileCmd;
        bool isMSVC = tc.cxx.name == "cl" || tc.cxx.name == "clang-cl";

        if (isMSVC)
        {
            compileCmd = [
                tc.cxx.path,
                "/std:c++20",
                "/EHsc",
                "/O2",
                "/c",
                "v8shim.cpp",
                "/Fov8shim.obj",
            ];
            if (v8Includes.length > 0)
                compileCmd ~= "/I" ~ v8Includes;
        }
        else
        {
            compileCmd = [
                tc.cxx.path,
                "-std=c++20",
                "-fPIC",
                "-O2",
                "-c",
                "v8shim.cpp",
                "-o", "v8shim.o",
            ];
            if (v8Includes.length > 0)
                compileCmd ~= "-I" ~ v8Includes;
        }

        // Try pkg-config cflags (POSIX only)
        if (!isMSVC && tc.pkgConfig.found)
        {
            auto r = executeShell(tc.pkgConfig.path ~ " --cflags v8 2>/dev/null");
            if (r.status == 0 && r.output.strip().length > 0)
            {
                foreach (flag; r.output.strip().splitter(" "))
                {
                    auto f = flag.strip();
                    if (f.length > 0)
                        compileCmd ~= f;
                }
            }
        }

        if (runCmd(compileCmd, v8shimDir(), tag) != 0)
        {
            logError(tag, "Compilation failed -- is libv8-dev installed?");
            return false;
        }

        // ── Archive ───────────────────────────────────────────────
        logStep(tag, 2, 2, "Creating static library...");

        if (isMSVC)
        {
            if (runCmd([tc.ar.path, "/OUT:v8shim.lib", "v8shim.obj"],
                       v8shimDir(), tag) != 0)
            {
                logError(tag, "Failed to create static library");
                return false;
            }
            auto msvcObj = buildPath(v8shimDir(), "v8shim.obj");
            if (exists(msvcObj))
                std.file.remove(msvcObj);
        }
        else
        {
            if (runCmd([tc.ar.path, "rcs", "libv8shim.a", "v8shim.o"],
                       v8shimDir(), tag) != 0)
            {
                logError(tag, "Failed to create static library");
                return false;
            }
            if (exists(objPath))
                std.file.remove(objPath);
        }
    }

    auto elapsed = MonoTime.currTime - startTime;
    auto libSize = getSize(libPath);

    logInfo(tag, "Built libv8shim.a (" ~ fmtKB(libSize) ~ ") in "
               ~ fmtSecs(elapsed.total!"msecs"));
    logInfo(tag, "  " ~ libPath);

    return true;
}

// ════════════════════════════════════════════════════════════════════
// V8 Header Download (Node.js method)
// ════════════════════════════════════════════════════════════════════

/**
 * Download V8 headers from Node.js headers tarball.
 *
 * Node.js distributes a lightweight headers-only tarball (~8MB) that
 * contains V8's complete public API headers.  This is the same approach
 * Node.js native addons use (node-gyp downloads these headers).
 *
 * The tarball structure is:
 *   node-vX.Y.Z/include/node/{v8.h, v8-*.h, libplatform/, cppgc/, ...}
 *
 * We extract the include/node/ subtree to vendor/v8/include/.
 */
bool downloadV8Headers(ref const Toolchain tc)
{
    enum tag = "v8";
    immutable markerPath = buildPath(v8IncludeDir(), V8_HEADERS_MARKER);

    if (exists(markerPath))
    {
        logInfo(tag, "V8 headers already present -- skipping download");
        return true;
    }

    if (!tc.hasDownloader())
    {
        logError(tag, "No download tool (curl/wget) available");
        return false;
    }

    string url = nodeHeadersUrl();
    logInfo(tag, "Downloading Node.js " ~ V8_NODE_VERSION ~ " headers...");

    mkdirRecurse(vendorDir());

    // Download tarball
    if (!downloadFile(tc, url, v8Archive(), tag))
        return false;

    // Extract only the include/node/ subtree
    mkdirRecurse(v8IncludeDir());

    // The tarball has structure: node-vX.Y.Z/include/node/...
    // We use --strip-components=3 to extract contents directly into v8/include/
    string stripPrefix = "node-" ~ V8_NODE_VERSION ~ "/include/node";
    int exStatus = runCmd(
        ["tar", "-xzf", v8Archive(),
         "--strip-components=3", "-C", v8IncludeDir(),
         stripPrefix ~ "/"],
        vendorDir(), tag);

    if (exStatus != 0)
    {
        logError(tag, "Failed to extract V8 headers from Node.js tarball");
        return false;
    }

    // Clean up archive
    if (exists(v8Archive()))
        std.file.remove(v8Archive());

    // Verify
    if (!exists(markerPath))
    {
        logError(tag, "V8 headers extraction failed — v8.h not found");
        return false;
    }

    logInfo(tag, "V8 headers ready at " ~ v8IncludeDir());
    return true;
}

/**
 * Download the kuoruan/libv8 pre-built monolith archive and extract:
 *   vendor/v8/include/   ← V8 headers (used to compile v8shim.cpp)
 *   vendor/v8/lib/libv8_monolith.a
 *
 * Also creates:
 *   vendor/v8/lib/libv8.a          (symlink → libv8_monolith.a on POSIX)
 *   vendor/v8/lib/libv8_libplatform.a (empty stub — symbols are in monolith)
 *
 * Archive layout (flat root): include/ + libv8_monolith.a + gn-args_*.txt
 * Source: https://github.com/kuoruan/libv8/releases
 */
bool downloadV8Prebuilt(ref const Toolchain tc, ref const BuildOptions opts)
{
    enum tag = "v8";
    immutable libDir     = buildPath(v8Dir(), "lib");
    immutable monolithDst = buildPath(libDir, "libv8_monolith.a");
    immutable stagedV8   = buildPath(libDir, "libv8.a");
    immutable stagedPlat = buildPath(libDir, "libv8_libplatform.a");
    immutable markerH    = buildPath(v8IncludeDir(), "v8.h");

    if (!opts.force && exists(monolithDst) && exists(markerH))
    {
        logInfo(tag, "V8 prebuilt already downloaded -- skipping");
        return true;
    }

    immutable url     = v8PrebuiltUrl();
    immutable archive = v8PrebuiltArchive();

    logInfo(tag, "Downloading V8 prebuilt " ~ V8_PREBUILT_VERSION ~ " for this platform...");
    logInfo(tag, "URL: " ~ url);

    if (!downloadFile(tc, url, archive))
    {
        logError(tag, "Failed to download V8 prebuilt archive from: " ~ url);
        return false;
    }

    logInfo(tag, "Extracting V8 prebuilt archive...");
    mkdirRecurse(v8IncludeDir());
    mkdirRecurse(libDir);

    version (Windows)
    {
        // 7z e archive.7z -o<dir> — requires 7z in PATH
        auto r = executeShell("7z x \"" ~ archive ~ "\" -o\"" ~ v8Dir() ~ "\" -y 2>&1");
        if (r.status != 0)
        {
            logError(tag, "7z extraction failed: " ~ r.output);
            return false;
        }
        // On Windows the monolith may land as v8_monolith.lib
        foreach (candidate; ["libv8_monolith.a", "v8_monolith.lib"])
        {
            string src = buildPath(v8Dir(), candidate);
            if (exists(src))
            {
                std.file.copy(src, monolithDst);
                break;
            }
        }
    }
    else
    {
        // tar -xJf archive.tar.xz -C vendor/v8 --strip-components=0
        auto r = executeShell(
            "tar -xJf \"" ~ archive ~ "\" -C \"" ~ v8Dir() ~ "\" 2>&1");
        if (r.status != 0)
        {
            logError(tag, "tar extraction failed: " ~ r.output);
            return false;
        }
        // monolith should now be at vendor/v8/libv8_monolith.a; move to lib/
        string extracted = buildPath(v8Dir(), "libv8_monolith.a");
        if (!exists(extracted))
        {
            logError(tag, "libv8_monolith.a not found after extraction");
            logError(tag, "Expected: " ~ extracted);
            return false;
        }
        rename(extracted, monolithDst);

        // include/ lands at vendor/v8/include/ — already the right place
        // (the extraction target is v8Dir() and archive root has include/)
    }

    if (!exists(monolithDst))
    {
        logError(tag, "libv8_monolith.a missing after extraction");
        return false;
    }

    // Create libv8.a symlink / copy
    if (exists(stagedV8)) remove(stagedV8);
    version (Posix)
    {
        import core.sys.posix.unistd : symlink;
        import std.string : toStringz;
        symlink(monolithDst.toStringz, stagedV8.toStringz);
    }
    else
    {
        std.file.copy(monolithDst, stagedV8);
    }

    // Create empty libv8_libplatform.a stub (symbols are in monolith)
    if (tc.ar.found && tc.cxx.found)
    {
        if (exists(stagedPlat)) remove(stagedPlat);
        auto stubO = stagedPlat ~ ".stub.o";
        auto rStub = executeShell(
            "printf 'void __v8_platform_stub(void){}' | " ~
            tc.cxx.path ~ " -x c -O0 -c - -o \"" ~ stubO ~ "\" 2>/dev/null && " ~
            tc.ar.path ~ " rcs \"" ~ stagedPlat ~ "\" \"" ~ stubO ~ "\" 2>/dev/null");
        if (exists(stubO)) remove(stubO);
    }

    logInfo(tag, "V8 prebuilt ready:");
    logInfo(tag, "  headers : " ~ v8IncludeDir());
    logInfo(tag, "  library : " ~ monolithDst);
    return true;
}

// ════════════════════════════════════════════════════════════════════
// Clean
// ════════════════════════════════════════════════════════════════════

void doClean()
{
    enum tag = "clean";
    logInfo(tag, "Removing vendor build artifacts...");

    struct CleanTarget
    {
        string path;
        bool   isDirectory;
    }

    CleanTarget[] targets = [
        CleanTarget(qjsBuildDir(), true),
        CleanTarget(qjsArchive(), false),
        CleanTarget(jscArchive(), false),
        CleanTarget(v8Archive(), false),
        CleanTarget(buildPath(v8shimDir(), "libv8shim.a"), false),
        CleanTarget(buildPath(v8shimDir(), "v8shim.o"), false),
    ];

    int removed = 0;
    foreach (t; targets)
    {
        if (exists(t.path))
        {
            if (t.isDirectory)
                rmdirRecurse(t.path);
            else
                std.file.remove(t.path);
            logInfo(tag, "  removed: " ~ t.path);
            removed++;
        }
    }

    if (removed == 0)
        logInfo(tag, "  (nothing to clean)");

    logInfo(tag, "Done");
}

/// Deep clean: remove all vendor sources too (not just build artifacts).
void doDeepClean()
{
    enum tag = "clean";
    logInfo(tag, "Deep cleaning -- removing all vendor sources...");

    foreach (dir; [qjsDir(), jscDir(), v8Dir()])
    {
        if (exists(dir))
        {
            rmdirRecurse(dir);
            logInfo(tag, "  removed: " ~ dir);
        }
    }

    doClean();
}

// ════════════════════════════════════════════════════════════════════
// Helpers
// ════════════════════════════════════════════════════════════════════

/**
 * We avoid std.format with floating-point arguments because Phobos's
 * printFloat triggers an internal "more than one mutable reference"
 * error under `-preview=all` with LDC 1.42.0 / DMD 2.112.
 * Instead we use integer arithmetic with these helpers.
 */

/// Format milliseconds as "N.Ns" string (avoids float formatting).
string fmtSecs(long ms)
{
    if (ms < 0) ms = 0;
    string whole = to!string(ms / 1000);
    string frac  = to!string((ms % 1000) / 100); // one decimal
    return whole ~ "." ~ frac ~ "s";
}

/// Format bytes as "N.N KB" string (avoids float formatting).
string fmtKB(ulong bytes)
{
    ulong kb = bytes / 1024;
    ulong frac = ((bytes % 1024) * 10) / 1024; // one decimal
    return to!string(kb) ~ "." ~ to!string(frac) ~ " KB";
}

/// Read first line of text file, or empty string.
string readFirstLine(string path)
{
    try
    {
        auto content = readText(path);
        foreach (line; content.lineSplitter())
            return line.strip();
    }
    catch (Exception) {}
    return "";
}

// ════════════════════════════════════════════════════════════════════
// Entry Point
// ════════════════════════════════════════════════════════════════════

int main(string[] args)
{
    // Parse command-line arguments
    auto opts = parseArgs(args);
    if (opts.exitRequested)
        return opts.exitCode;

    g_verbosity = opts.verbosity;

    // Handle --clean early
    if (opts.clean)
    {
        doClean();
        return 0;
    }

    // Detect toolchain
    auto tc = detectToolchain();
    if (opts.jobs > 0)
        tc.cpuCount = opts.jobs;

    if (g_verbosity == Verbosity.verbose)
        tc.report();

    // Build SQLite (cross-cutting dependency, all backends need it)
    buildSqlite(tc, opts);

    // Build requested backend(s)
    bool success = true;

    final switch (opts.backend)
    {
        case Backend.quickjs:
            success = buildQuickJS(tc, opts);
            break;

        case Backend.jsc:
            success = checkJSC(tc, opts);
            break;

        case Backend.v8:
            // Download prebuilt first so its headers are available for v8shim compilation
            checkV8Libs(tc, opts);  // may populate vendor/v8/include/ and vendor/v8/lib/
            success = buildV8Shim(tc, opts) && checkV8Libs(tc, opts);
            break;

        case Backend.all:
            // Build all backends; don't stop on first failure
            bool qjsOk  = buildQuickJS(tc, opts);
            bool jscOk   = checkJSC(tc, opts);
            bool v8Ok    = buildV8Shim(tc, opts) && checkV8Libs(tc, opts);

            writeln();
            logInfo("all", "Build summary:");
            logInfo("all", "  QuickJS-NG : " ~ (qjsOk  ? "OK" : "FAILED"));
            logInfo("all", "  JSC        : " ~ (jscOk   ? "OK" : "FAILED"));
            logInfo("all", "  V8 shim    : " ~ (v8Ok    ? "OK" : "FAILED"));

            success = qjsOk; // QuickJS is the critical one
            break;
    }

    if (!success)
    {
        logError("build", "Build failed");
        return 1;
    }

    return 0;
}
