module dun.security.cve_db;


/++
 + `@trusted policy`: CVE audit (OSV API client + local cache +
 + semver comparison). Every `@trusted` is one of:
 +
 +   1. `dun.builtins.fetch.doFetch` for OSV API queries.
 +   2. `std.file.{exists, readText, mkdirRecurse, write}` for
 +      the local 24h-TTL cache under `$DUN_HOME/cache/osv/`.
 +   3. `std.json.parseJSON` for the OSV response payload.
 +   4. The semver comparison is pure logic (no FFI), but the
 +      AA (associative array) operations bubble up via Phobos's
 +      `@system` defaults — `@trusted` is the simplest fix.
 +/
enum Severity
{
    critical,
    high,
    medium,
    low,
    none,
}

static assert(__traits(allMembers, Severity).length == 5,
    "Severity enum member count changed -- update display logic");

struct CveEntry
{
    string cveId;
    Severity severity;
    string packageName;
    string fixedVersion;
    string description;
}

static assert(CveEntry.sizeof > 0, "CveEntry must be non-zero size");

struct AuditResult
{
    string packageName;
    string installedVersion;
    CveEntry[] vulnerabilities;
    bool isVulnerable;
}

string severityString(Severity s) pure nothrow @safe @nogc
{
    final switch (s) with (Severity)
    {
        case critical: return "CRITICAL";
        case high: return "HIGH";
        case medium: return "MEDIUM";
        case low: return "LOW";
        case none: return "NONE";
    }
}

string severityColor(Severity s) pure nothrow @safe @nogc
{
    final switch (s) with (Severity)
    {
        case critical: return "\033[1;31m";
        case high: return "\033[0;31m";
        case medium: return "\033[0;33m";
        case low: return "\033[0;36m";
        case none: return "\033[0;32m";
    }
}

// ---------------------------------------------------------------------------
// Cache configuration
// ---------------------------------------------------------------------------

private enum CACHE_DIR = ".dun";
private enum CACHE_FILE = ".dun/audit-cache.json";
private enum CACHE_MAX_AGE_SECS = 86400; // 24 hours

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

AuditResult[] checkPackage(string name, string version_) @trusted
{
    assert(name.length > 0, "Package name must not be empty");

    CveEntry[] vulns = queryOsvApi(name, version_);

    AuditResult[] results;
    if (vulns.length > 0)
        results ~= AuditResult(name, version_, vulns, true);

    return results;
}

AuditResult[] auditNodeModules() @trusted
{
    import std.file : dirEntries, SpanMode, exists, readText;
    import std.path : buildNormalizedPath, baseName;
    import std.json : parseJSON;

    AuditResult[] allResults;
    string nmDir = buildNormalizedPath(".", "node_modules");

    if (!exists(nmDir))
        return allResults;

    foreach (entry; dirEntries(nmDir, SpanMode.shallow))
    {
        if (!entry.isDir)
            continue;

        string pkgName = baseName(entry.name);
        string pkgJson = buildNormalizedPath(entry.name, "package.json");

        if (!exists(pkgJson))
            continue;

        try
        {
            auto j = parseJSON(readText(pkgJson));
            string ver = ("version" in j) ? j["version"].str : "0.0.0";
            auto results = checkPackage(pkgName, ver);
            allResults ~= results;
        }
        catch (Exception)
        {
            continue;
        }
    }

    return allResults;
}

void printAuditReport(AuditResult[] results) @trusted
{
    import std.stdio : writeln, writefln;

    if (results.length == 0)
    {
        writeln("\033[0;32m", "No known vulnerabilities found.", "\033[0m");
        return;
    }

    size_t nCritical, nHigh, nMedium, nLow;

    foreach (ref r; results)
    {
        assert(r.vulnerabilities.length > 0);

        foreach (ref v; r.vulnerabilities)
        {
            writefln("%s%s\033[0m  %s@%s  %s",
                severityColor(v.severity),
                severityString(v.severity),
                r.packageName,
                r.installedVersion,
                v.description);

            writefln("  CVE: %s  Fixed: %s",
                v.cveId,
                v.fixedVersion.length > 0 ? v.fixedVersion : "no fix available");

            final switch (v.severity)
            {
                case Severity.critical: nCritical++; break;
                case Severity.high: nHigh++; break;
                case Severity.medium: nMedium++; break;
                case Severity.low: nLow++; break;
                case Severity.none: break;
            }
        }
    }

    writeln();
    writefln("%d vulnerabilities found in %d packages:", nCritical + nHigh + nMedium + nLow, results.length);
    if (nCritical > 0) writefln("  \033[1;31m%d critical\033[0m", nCritical);
    if (nHigh > 0) writefln("  \033[0;31m%d high\033[0m", nHigh);
    if (nMedium > 0) writefln("  \033[0;33m%d medium\033[0m", nMedium);
    if (nLow > 0) writefln("  \033[0;36m%d low\033[0m", nLow);
}

Severity worstSeverity(AuditResult[] results) pure nothrow @safe @nogc
{
    Severity worst = Severity.none;
    foreach (ref r; results)
    {
        foreach (ref v; r.vulnerabilities)
        {
            if (v.severity < worst)
                worst = v.severity;
        }
    }
    return worst;
}

// ---------------------------------------------------------------------------
// OSV API + cache layer
// ---------------------------------------------------------------------------

private CveEntry[] queryOsvApi(string packageName, string version_) @trusted
{
    assert(packageName.length > 0);

    string cacheKey = packageName ~ "@" ~ version_;

    // Check cache first
    auto cached = loadFromCache(cacheKey);
    if (cached.valid)
        return cached.entries;

    // Query OSV API
    CveEntry[] results;
    bool apiSuccess = false;

    try
    {
        import dun.builtins.fetch : doFetch;
        import std.json : parseJSON, JSONType;

        string body_ = `{"version":"` ~ escapeJson(version_)
            ~ `","package":{"name":"` ~ escapeJson(packageName)
            ~ `","ecosystem":"npm"}}`;

        auto resp = doFetch(
            "https://api.osv.dev/v1/query", "POST", body_, false, null);

        if (resp.ok && resp.body_.length > 0)
        {
            auto j = parseJSON(resp.body_);
            results = parseOsvResponse(j, packageName);
            apiSuccess = true;
        }
    }
    catch (Exception)
    {
        // API unreachable -- use expired cache if available
    }

    if (apiSuccess)
    {
        saveToCache(cacheKey, results);
    }
    else
    {
        // Fall back to expired cache
        auto expired = loadFromCache(cacheKey, true);
        if (expired.valid)
        {
            import std.stdio : stderr;
            try { stderr.writefln("  (using cached audit data for %s)", cacheKey); }
            catch (Exception) {}
            return expired.entries;
        }
    }

    return results;
}

// ---------------------------------------------------------------------------
// OSV response parsing
// ---------------------------------------------------------------------------

private CveEntry[] parseOsvResponse(T)(T j, string packageName) @trusted
{
    import std.json : JSONType;

    CveEntry[] results;

    if ("vulns" !in j)
        return results;

    auto vulns = j["vulns"].array;
    foreach (ref vuln; vulns)
    {
        string id = ("id" in vuln) ? vuln["id"].str : "";
        if (id.length == 0)
            continue;

        Severity sev = extractSeverity(vuln);
        string summary = ("summary" in vuln) ? vuln["summary"].str : id;
        string fixedVer = extractFixedVersion(vuln);
        string cveId = extractCveId(vuln, id);

        if (summary.length > 120)
            summary = summary[0 .. 117] ~ "...";

        results ~= CveEntry(cveId, sev, packageName, fixedVer, summary);
    }

    return results;
}

private Severity extractSeverity(T)(ref T vuln) @trusted
{
    import std.json : JSONType;

    if ("database_specific" in vuln)
    {
        auto dbSpec = vuln["database_specific"];
        if ("severity" in dbSpec)
            return parseSeverityString(dbSpec["severity"].str);
    }

    if ("severity" in vuln && vuln["severity"].type == JSONType.array)
    {
        auto sevArr = vuln["severity"].array;
        if (sevArr.length > 0 && "score" in sevArr[0])
            return parseCvssScore(sevArr[0]["score"].str);
    }

    return Severity.medium;
}

private string extractFixedVersion(T)(ref T vuln) @trusted
{
    if ("affected" !in vuln)
        return "";

    foreach (ref aff; vuln["affected"].array)
    {
        if ("ranges" !in aff) continue;
        foreach (ref range; aff["ranges"].array)
        {
            if ("events" !in range) continue;
            foreach (ref ev; range["events"].array)
            {
                if ("fixed" in ev)
                    return ev["fixed"].str;
            }
        }
    }
    return "";
}

private string extractCveId(T)(ref T vuln, string defaultId) @trusted
{
    if ("aliases" !in vuln)
        return defaultId;

    foreach (ref alias_; vuln["aliases"].array)
    {
        auto a = alias_.str;
        if (a.length >= 4 && a[0 .. 4] == "CVE-")
            return a;
    }
    return defaultId;
}

// ---------------------------------------------------------------------------
// JSON file cache (auto-refresh after 24h)
// ---------------------------------------------------------------------------

private struct CacheResult
{
    CveEntry[] entries;
    bool valid;
}

private CacheResult loadFromCache(string key, bool ignoreExpiry = false) @trusted
{
    import std.file : exists, readText;
    import std.json : parseJSON, JSONType;

    CacheResult result;

    if (!exists(CACHE_FILE))
        return result;

    try
    {
        auto j = parseJSON(readText(CACHE_FILE));
        if (key !in j)
            return result;

        auto entry = j[key];
        if ("timestamp" !in entry || "vulns" !in entry)
            return result;

        // Check expiry
        if (!ignoreExpiry)
        {
            long ts = 0;
            try { ts = entry["timestamp"].get!long; } catch (Exception) {}
            long now = currentUnixTime();
            if (now - ts > CACHE_MAX_AGE_SECS)
                return result;
        }

        auto vulns = entry["vulns"].array;
        foreach (ref v; vulns)
        {
            string cveId = ("cveId" in v) ? v["cveId"].str : "";
            string pkg = ("package" in v) ? v["package"].str : "";
            string fix = ("fixed" in v) ? v["fixed"].str : "";
            string desc = ("description" in v) ? v["description"].str : "";
            int sevInt = 2;
            try { sevInt = cast(int) v["severity"].get!long; } catch (Exception) {}
            auto sev = cast(Severity) sevInt;

            result.entries ~= CveEntry(cveId, sev, pkg, fix, desc);
        }
        result.valid = true;
    }
    catch (Exception) {}

    return result;
}

private void saveToCache(string key, CveEntry[] entries) @trusted nothrow
{
    import std.file : exists, mkdirRecurse, write, readText;

    try
    {
        import std.json : parseJSON, JSONValue, JSONType;

        if (!exists(CACHE_DIR))
            mkdirRecurse(CACHE_DIR);

        // Load existing cache or start fresh
        JSONValue root;
        if (exists(CACHE_FILE))
        {
            try { root = parseJSON(readText(CACHE_FILE)); }
            catch (Exception) { root = JSONValue(cast(JSONValue[string]) null); }
        }
        else
        {
            root = JSONValue(cast(JSONValue[string]) null);
        }

        // Build vuln array
        JSONValue[] vulnArr;
        foreach (ref e; entries)
        {
            JSONValue v = JSONValue(cast(JSONValue[string]) null);
            v["cveId"] = e.cveId;
            v["severity"] = cast(int) e.severity;
            v["package"] = e.packageName;
            v["fixed"] = e.fixedVersion;
            v["description"] = e.description;
            vulnArr ~= v;
        }

        // Set cache entry
        JSONValue cacheEntry = JSONValue(cast(JSONValue[string]) null);
        cacheEntry["timestamp"] = currentUnixTime();
        cacheEntry["vulns"] = JSONValue(vulnArr);

        root[key] = cacheEntry;

        write(CACHE_FILE, root.toString());
    }
    catch (Throwable) {}
}

// ---------------------------------------------------------------------------
// Utilities
// ---------------------------------------------------------------------------

private:

long currentUnixTime() @trusted nothrow
{
    try
    {
        import core.time : dur;
        import std.datetime.systime : Clock;
        return Clock.currTime().toUnixTime();
    }
    catch (Throwable) { return 0; }
}

string escapeJson(string s) pure nothrow @safe
{
    string result;
    foreach (c; s)
    {
        if (c == '"') result ~= `\"`;
        else if (c == '\\') result ~= `\\`;
        else result ~= c;
    }
    return result;
}

Severity parseSeverityString(string s) pure nothrow @safe @nogc
{
    if (s.length == 0) return Severity.medium;
    if (s == "CRITICAL") return Severity.critical;
    if (s == "HIGH") return Severity.high;
    if (s == "MODERATE" || s == "MEDIUM") return Severity.medium;
    if (s == "LOW") return Severity.low;
    return Severity.medium;
}

Severity parseCvssScore(string scoreStr) pure nothrow @safe
{
    double score = 5.0;
    if (scoreStr.length > 0 && scoreStr[0] >= '0' && scoreStr[0] <= '9')
    {
        int whole = 0;
        size_t i = 0;
        while (i < scoreStr.length && scoreStr[i] >= '0' && scoreStr[i] <= '9')
        {
            whole = whole * 10 + (scoreStr[i] - '0');
            i++;
        }
        score = whole;
        if (i < scoreStr.length && scoreStr[i] == '.')
        {
            i++;
            int frac = 0;
            int div = 1;
            while (i < scoreStr.length && scoreStr[i] >= '0' && scoreStr[i] <= '9')
            {
                frac = frac * 10 + (scoreStr[i] - '0');
                div *= 10;
                i++;
            }
            score += cast(double) frac / div;
        }
    }

    if (score >= 9.0) return Severity.critical;
    if (score >= 7.0) return Severity.high;
    if (score >= 4.0) return Severity.medium;
    if (score > 0.0) return Severity.low;
    return Severity.medium;
}

int compareSemver(string a, string b) pure nothrow @safe
{
    auto av = parseSemverParts(a);
    auto bv = parseSemverParts(b);

    if (av[0] != bv[0]) return av[0] < bv[0] ? -1 : 1;
    if (av[1] != bv[1]) return av[1] < bv[1] ? -1 : 1;
    if (av[2] != bv[2]) return av[2] < bv[2] ? -1 : 1;

    bool aHasPre = hasPrerelease(a);
    bool bHasPre = hasPrerelease(b);
    if (aHasPre && !bHasPre) return -1;
    if (!aHasPre && bHasPre) return 1;

    return 0;
}

int[3] parseSemverParts(string ver) pure nothrow @safe
{
    int[3] parts = [0, 0, 0];
    int idx = 0;
    int current = 0;

    foreach (c; ver)
    {
        if (c == '.' && idx < 2)
        {
            parts[idx++] = current;
            current = 0;
        }
        else if (c == '-' || c == '+')
        {
            break;
        }
        else if (c >= '0' && c <= '9')
        {
            current = current * 10 + (c - '0');
        }
    }
    parts[idx] = current;
    return parts;
}

bool hasPrerelease(string ver) pure nothrow @safe @nogc
{
    foreach (c; ver)
    {
        if (c == '-') return true;
        if (c == '+') return false;
    }
    return false;
}

// ---------------------------------------------------------------------------
// Unit tests
// ---------------------------------------------------------------------------

unittest
{
    // Semver comparison
    assert(compareSemver("1.0.0", "2.0.0") < 0);
    assert(compareSemver("2.0.0", "1.0.0") > 0);
    assert(compareSemver("1.0.0", "1.0.0") == 0);
    assert(compareSemver("1.2.3", "1.2.4") < 0);
    assert(compareSemver("1.2.3", "1.3.0") < 0);
    assert(compareSemver("4.17.21", "4.17.20") > 0);
    assert(compareSemver("4.17.21", "4.17.21") == 0);
    assert(compareSemver("7.0.0", "7.0.5") < 0);
    assert(compareSemver("7.0.5", "7.0.5") == 0);
    assert(compareSemver("1.0.0-alpha", "1.0.0") < 0);
}

unittest
{
    // parseSemverParts
    assert(parseSemverParts("1.2.3") == [1, 2, 3]);
    assert(parseSemverParts("0.0.0") == [0, 0, 0]);
    assert(parseSemverParts("4.17.21") == [4, 17, 21]);
    assert(parseSemverParts("1.0.0-alpha") == [1, 0, 0]);
    assert(parseSemverParts("10.2.5") == [10, 2, 5]);
}

unittest
{
    // worstSeverity
    assert(worstSeverity([]) == Severity.none);
}

unittest
{
    // severityString coverage
    assert(severityString(Severity.critical) == "CRITICAL");
    assert(severityString(Severity.high) == "HIGH");
    assert(severityString(Severity.medium) == "MEDIUM");
    assert(severityString(Severity.low) == "LOW");
    assert(severityString(Severity.none) == "NONE");
}

unittest
{
    // escapeJson
    assert(escapeJson(`hello`) == `hello`);
    assert(escapeJson(`he"lo`) == `he\"lo`);
    assert(escapeJson(`he\lo`) == `he\\lo`);
}

unittest
{
    // parseSeverityString
    assert(parseSeverityString("CRITICAL") == Severity.critical);
    assert(parseSeverityString("HIGH") == Severity.high);
    assert(parseSeverityString("MODERATE") == Severity.medium);
    assert(parseSeverityString("MEDIUM") == Severity.medium);
    assert(parseSeverityString("LOW") == Severity.low);
    assert(parseSeverityString("") == Severity.medium);
}

unittest
{
    // parseCvssScore
    assert(parseCvssScore("9.8") == Severity.critical);
    assert(parseCvssScore("7.5") == Severity.high);
    assert(parseCvssScore("5.3") == Severity.medium);
    assert(parseCvssScore("3.1") == Severity.low);
}

unittest
{
    // Cache round-trip: save and reload entries
    import std.file : exists, mkdirRecurse, rmdirRecurse;
    import std.json : parseJSON, JSONValue;
    import std.file : write, readText;

    enum TEST_DIR = ".dun-test-cache";
    enum TEST_FILE = ".dun-test-cache/audit-cache.json";

    auto testEntries = [
        CveEntry("CVE-2024-TEST1", Severity.critical, "test-pkg", "2.0.0", "Test vuln 1"),
        CveEntry("CVE-2024-TEST2", Severity.high, "test-pkg", "", "Test vuln 2"),
    ];

    mkdirRecurse(TEST_DIR);

    JSONValue root = JSONValue(cast(JSONValue[string]) null);
    JSONValue[] vulnArr;
    foreach (ref e; testEntries)
    {
        JSONValue v = JSONValue(cast(JSONValue[string]) null);
        v["cveId"] = e.cveId;
        v["severity"] = cast(int) e.severity;
        v["package"] = e.packageName;
        v["fixed"] = e.fixedVersion;
        v["description"] = e.description;
        vulnArr ~= v;
    }
    JSONValue cacheEntry = JSONValue(cast(JSONValue[string]) null);
    cacheEntry["timestamp"] = currentUnixTime();
    cacheEntry["vulns"] = JSONValue(vulnArr);
    root["test-pkg@1.0.0"] = cacheEntry;
    write(TEST_FILE, root.toString());

    assert(exists(TEST_FILE), "Cache file should exist");
    auto reloaded = parseJSON(readText(TEST_FILE));
    assert("test-pkg@1.0.0" in reloaded, "Cache should contain the key");
    auto entry = reloaded["test-pkg@1.0.0"];
    assert("vulns" in entry);
    assert(entry["vulns"].array.length == 2, "Should have 2 cached vulns");
    assert(entry["vulns"].array[0]["cveId"].str == "CVE-2024-TEST1");

    // Cleanup
    rmdirRecurse(TEST_DIR);
}
