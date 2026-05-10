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

// ════════════════════════════════════════════════════════════════════
// Configuration Constants
// ════════════════════════════════════════════════════════════════════

enum Backend { quickjs, jsc, v8, all }

enum Platform { linux, macos, freebsd, windows, unknown }

/// Verbosity level for build output.
enum Verbosity { normal, verbose }

// QuickJS-NG configuration
enum QJS_VERSION    = "v0.9.0";
enum QJS_URL_TAGGED = "https://github.com/quickjs-ng/quickjs/archive/refs/tags/"
                    ~ QJS_VERSION ~ ".tar.gz";
enum QJS_URL_MASTER = "https://github.com/quickjs-ng/quickjs/archive/refs/heads/master.tar.gz";
enum QJS_LIB_NAME   = "libqjs.a";

// V8 shim configuration
enum V8_INCLUDE_PATH = "/usr/include/v8";

// Download retry configuration
enum DOWNLOAD_MAX_RETRIES = 3;
enum DOWNLOAD_RETRY_DELAY_SECS = 2;

// Derived paths (computed at module init via immutable + CTFE-safe dirName)
immutable PACKAGE_DIR = __FILE_FULL_PATH__.dirName;

string vendorDir()   { return buildPath(PACKAGE_DIR, "vendor"); }
string qjsDir()     { return buildPath(vendorDir(), "quickjs"); }
string qjsBuildDir() { return buildPath(qjsDir(), "build"); }
string qjsArchive() { return buildPath(vendorDir(), "quickjs.tar.gz"); }
string v8shimDir()   { return buildPath(vendorDir(), "v8shim"); }

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

    // Fallback: nproc / sysctl
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
    else
        tc.make = findProgram("make", "gmake");

    tc.cmake     = findProgram("cmake");
    tc.cc        = findProgram("cc", "gcc", "clang");
    tc.cxx       = findProgram("c++", "g++", "clang++");
    tc.ar        = findProgram("ar", "llvm-ar");
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
            // Simple retry delay using sleep command
            executeShell("sleep " ~ DOWNLOAD_RETRY_DELAY_SECS.to!string);
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
    // Simple quoting: wrap in single quotes, escape internal single quotes
    return "'" ~ s.replace("'", "'\\''") ~ "'";
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
    if (!tc.make.found)
    {
        logError(tag, "Make not found. Install make (e.g., apt install make).");
        return false;
    }
    if (!tc.cc.found)
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

    immutable qjsSrcDir = qjsDir();
    immutable qjsSrcMarker = buildPath(qjsSrcDir, "quickjs.h");
    immutable archive = qjsArchive();

    if (!exists(qjsSrcMarker))
    {
        // Clean any partial previous download
        if (exists(qjsSrcDir))
        {
            logVerbose(tag, "Removing stale source directory...");
            rmdirRecurse(qjsSrcDir);
        }

        mkdirRecurse(vendorDir());

        // Download the tarball
        if (!downloadFile(tc, opts.qjsUrl, archive, tag))
            return false;

        // Extract
        logVerbose(tag, "Extracting archive...");
        mkdirRecurse(qjsSrcDir);

        int exStatus = runCmd(
            ["tar", "-xzf", archive, "--strip-components=1", "-C", qjsSrcDir],
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
        if (!exists(qjsSrcMarker))
        {
            logError(tag, "Extraction succeeded but quickjs.h not found -- "
                        ~ "archive structure may have changed");
            return false;
        }

        logInfo(tag, "Source downloaded and extracted");
    }
    else
    {
        logInfo(tag, "Source already present -- skipping download");
    }

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
        "-DCMAKE_BUILD_TYPE=Release",
        "-DCMAKE_C_FLAGS=-fPIC -O2",
        "-DBUILD_SHARED_LIBS=OFF",
        "-DBUILD_EXAMPLES=OFF",
    ];

    // Use detected C compiler
    if (tc.cc.found)
        cmakeArgs ~= "-DCMAKE_C_COMPILER=" ~ tc.cc.path;

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

    // Build the qjs library target (not the full project with executables)
    if (runCmd([tc.make.path, "-j" ~ jobCount.to!string, "qjs"], bDir, tag) != 0)
    {
        // Retry with single job for clearer error output
        logWarning(tag, "Parallel build failed, retrying with -j1...");
        if (runCmd([tc.make.path, "-j1", "qjs"], bDir, tag) != 0)
        {
            logError(tag, "QuickJS-NG compilation failed");
            return false;
        }
    }

    // ── Verify ─────────────────────────────────────────────────────
    if (!exists(libPath))
    {
        logError(tag, QJS_LIB_NAME ~ " not found at expected path: " ~ libPath);

        // Try to find it somewhere in the build tree
        logVerbose(tag, "Searching build tree for " ~ QJS_LIB_NAME ~ "...");
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
 * Check JSC system availability and optionally download headers.
 *
 * On Linux:  Requires libjavascriptcoregtk-4.1-dev (checked via pkg-config)
 * On macOS:  Uses system JavaScriptCore.framework
 */
bool checkJSC(ref const Toolchain tc, ref const BuildOptions opts)
{
    enum tag = "jsc";
    logInfo(tag, "Checking JavaScriptCore availability...");

    final switch (tc.platform)
    {
        case Platform.linux:
        case Platform.freebsd:
            return checkJSCLinux(tc, tag);

        case Platform.macos:
            logInfo(tag, "JavaScriptCore.framework available (system framework)");
            // Verify the framework exists
            if (exists("/System/Library/Frameworks/JavaScriptCore.framework"))
            {
                logInfo(tag, "  /System/Library/Frameworks/JavaScriptCore.framework");
                return true;
            }
            logWarning(tag, "JavaScriptCore.framework not found at expected path");
            return false;

        case Platform.windows:
            logError(tag, "JSC is not supported on Windows");
            return false;

        case Platform.unknown:
            logError(tag, "Cannot detect platform for JSC check");
            return false;
    }
}

bool checkJSCLinux(ref const Toolchain tc, string tag)
{
    if (!tc.pkgConfig.found)
    {
        logWarning(tag, "pkg-config not found -- cannot verify JSC installation");
        logWarning(tag, "  Install pkg-config: apt install pkg-config");
        // Try direct path check as fallback
        if (exists("/usr/include/webkitgtk-4.1/jsc/jsc.h") ||
            exists("/usr/include/webkitgtk-6.0/jsc/jsc.h"))
        {
            logInfo(tag, "Found JSC headers via direct path check");
            return true;
        }
        logError(tag, "JSC headers not found");
        return false;
    }

    // Try multiple pkg-config names (different distro versions)
    string[] pkgNames = [
        "javascriptcoregtk-4.1",
        "javascriptcoregtk-6.0",
        "javascriptcoregtk-4.0",
    ];

    foreach (pkgName; pkgNames)
    {
        auto r = executeShell(
            tc.pkgConfig.path ~ " --exists " ~ pkgName ~ " 2>/dev/null");
        if (r.status == 0)
        {
            // Get version and flags
            auto ver = executeShell(
                tc.pkgConfig.path ~ " --modversion " ~ pkgName);
            auto cflags = executeShell(
                tc.pkgConfig.path ~ " --cflags " ~ pkgName);
            auto libs = executeShell(
                tc.pkgConfig.path ~ " --libs " ~ pkgName);

            logInfo(tag, "Found " ~ pkgName ~ " version "
                       ~ ver.output.strip());
            logVerbose(tag, "  CFLAGS: " ~ cflags.output.strip());
            logVerbose(tag, "  LIBS:   " ~ libs.output.strip());
            return true;
        }
    }

    logError(tag, "JavaScriptCore not found via pkg-config");
    logError(tag, "  Install: apt install libjavascriptcoregtk-4.1-dev");
    logError(tag, "       or: apt install libjavascriptcoregtk-6.0-dev");
    return false;
}

// ════════════════════════════════════════════════════════════════════
// V8 Shim Backend
// ════════════════════════════════════════════════════════════════════

/**
 * Build the V8 shim library (a thin C++ wrapper around V8's C++ API).
 *
 * Requires system-installed libv8-dev.
 * Compiles vendor/v8shim/v8shim.cpp → libv8shim.a
 */
bool buildV8Shim(ref const Toolchain tc, ref const BuildOptions opts)
{
    enum tag = "v8";
    immutable srcPath = buildPath(v8shimDir(), "v8shim.cpp");
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

    // Check V8 headers
    bool hasV8Headers = exists(buildPath(V8_INCLUDE_PATH, "v8.h"));
    if (!hasV8Headers)
    {
        // Try pkg-config
        if (tc.pkgConfig.found)
        {
            auto r = executeShell(
                tc.pkgConfig.path ~ " --exists v8 2>/dev/null");
            hasV8Headers = (r.status == 0);
        }
    }

    if (!hasV8Headers)
    {
        logError(tag, "V8 headers not found at " ~ V8_INCLUDE_PATH);
        logError(tag, "  Install: apt install libv8-dev");
        return false;
    }

    logVerbose(tag, "C++ compiler: " ~ tc.cxx.path);
    logVerbose(tag, "Archiver:     " ~ tc.ar.path);

    // ── Compile ────────────────────────────────────────────────────
    logStep(tag, 1, 2, "Compiling v8shim.cpp...");

    string[] compileCmd = [
        tc.cxx.path,
        "-std=c++17",
        "-fPIC",
        "-O2",
        "-c",
        "v8shim.cpp",
        "-o", "v8shim.o",
    ];

    // Add V8 include path
    if (exists(V8_INCLUDE_PATH))
        compileCmd ~= "-I" ~ V8_INCLUDE_PATH;

    // Try pkg-config cflags
    if (tc.pkgConfig.found)
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

    if (runCmd([tc.ar.path, "rcs", "libv8shim.a", "v8shim.o"],
               v8shimDir(), tag) != 0)
    {
        logError(tag, "Failed to create static library");
        return false;
    }

    // Clean up object file
    if (exists(objPath))
        std.file.remove(objPath);

    auto elapsed = MonoTime.currTime - startTime;
    auto libSize = getSize(libPath);

    logInfo(tag, "Built libv8shim.a (" ~ fmtKB(libSize) ~ ") in "
               ~ fmtSecs(elapsed.total!"msecs"));
    logInfo(tag, "  " ~ libPath);

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

    if (exists(qjsDir()))
    {
        rmdirRecurse(qjsDir());
        logInfo(tag, "  removed: " ~ qjsDir());
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
