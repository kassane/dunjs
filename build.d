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
enum QJS_VERSION     = "v0.9.0";
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
// V8 headers are vendored from Node.js headers tarball (same headers Node uses).
// This eliminates the need for system libv8-dev at compile time.
// Linking still requires system V8 libraries (libv8, libv8_libplatform).
enum V8_NODE_VERSION   = "v22.15.0";
enum V8_HEADERS_MARKER = "v8.h";
enum V8_SYSTEM_INCLUDE = "/usr/include/v8";

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
string v8Archive()   { return buildPath(vendorDir(), "node-headers.tar.gz"); }

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

    string[] cmakeArgs = [
        tc.cmake.path,
        "..",
        "-DBUILD_SHARED_LIBS=OFF",
        "-DBUILD_EXAMPLES=OFF",
    ];

    if (tc.platform == Platform.windows)
    {
        // MSVC multi-config: don't set CMAKE_BUILD_TYPE, use --config Release below
    }
    else
    {
        cmakeArgs ~= "-DCMAKE_BUILD_TYPE=Release";
        cmakeArgs ~= "-DCMAKE_C_FLAGS=-fPIC -O2";

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

    if (tc.platform == Platform.windows)
        buildCmd ~= ["--config", "Release"];

    if (runCmd(buildCmd, bDir, tag) != 0)
    {
        // Retry with single job for clearer error output
        logWarning(tag, "Parallel build failed, retrying with -j 1...");
        string[] retryCmd = [
            tc.cmake.path, "--build", ".",
            "--target", "qjs",
            "-j", "1",
        ];
        if (tc.platform == Platform.windows)
            retryCmd ~= ["--config", "Release"];

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
        logError(tag, QJS_LIB_NAME ~ " not found at expected path: " ~ libPath);

        // Try to find it somewhere in the build tree
        logVerbose(tag, "Searching build tree for " ~ QJS_LIB_NAME ~ "...");
        version (Windows)
            auto findResult = executeShell(
                "where /R " ~ shellQuote(bDir) ~ " " ~ QJS_LIB_NAME ~ " 2>NUL");
        else
            auto findResult = executeShell(
                "find " ~ shellQuote(bDir) ~ " -name '" ~ QJS_LIB_NAME ~ "' 2>/dev/null");
        if (findResult.status == 0 && findResult.output.strip().length > 0)
        {
            logError(tag, "Found at: " ~ findResult.output.strip());
            logError(tag, "Build tree layout may have changed");
        }
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

    // ── Compile ────────────────────────────────────────────────────
    logStep(tag, 1, 2, "Compiling v8shim.cpp...");

    string[] compileCmd;
    bool isMSVC = tc.cxx.name == "cl" || tc.cxx.name == "clang-cl";

    if (isMSVC)
    {
        compileCmd = [
            tc.cxx.path,
            "/std:c++17",
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
            "-std=c++17",
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

    // ── Archive ────────────────────────────────────────────────────
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
            success = buildV8Shim(tc, opts);
            break;

        case Backend.all:
            // Build all backends; don't stop on first failure
            bool qjsOk  = buildQuickJS(tc, opts);
            bool jscOk   = checkJSC(tc, opts);
            bool v8Ok    = buildV8Shim(tc, opts);

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
