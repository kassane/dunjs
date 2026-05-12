module dun.security.cve_db;

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

private immutable CveEntry[] CVE_DATABASE = [
    // ---- CRITICAL ----
    CveEntry("CVE-2023-26920", Severity.critical, "jsonpath", "",
        "Arbitrary code execution via unsafe eval of JSONPath expressions"),
    CveEntry("CVE-2020-36632", Severity.critical, "flat", "5.0.1",
        "Prototype pollution via crafted object keys"),
    CveEntry("CVE-2020-8203", Severity.critical, "lodash", "4.17.20",
        "Prototype pollution in zipObjectDeep"),
    CveEntry("CVE-2021-23337", Severity.critical, "lodash", "4.17.21",
        "Command injection via template function"),
    CveEntry("CVE-2021-23334", Severity.critical, "static-eval", "",
        "Sandbox escape via FunctionExpression"),

    // ---- HIGH ----
    CveEntry("CVE-2024-21538", Severity.high, "cross-spawn", "7.0.5",
        "ReDoS via crafted string in argument parsing"),
    CveEntry("CVE-2020-28500", Severity.high, "lodash", "4.17.21",
        "ReDoS in toNumber via crafted string"),
    CveEntry("CVE-2021-23358", Severity.high, "underscore", "1.13.0-2",
        "Arbitrary code injection via template()"),
    CveEntry("CVE-2022-46175", Severity.high, "json5", "2.2.2",
        "Prototype pollution via __proto__ key in parse()"),
    CveEntry("CVE-2022-24785", Severity.high, "moment", "2.29.2",
        "Path traversal in moment.locale()"),
    CveEntry("CVE-2022-31129", Severity.high, "moment", "2.29.4",
        "ReDoS via RFC 2822 date parsing"),
    CveEntry("CVE-2022-24999", Severity.high, "qs", "6.10.3",
        "Prototype poisoning via crafted query string"),
    CveEntry("CVE-2017-1000048", Severity.high, "qs", "6.0.4",
        "Prototype pollution via crafted querystring"),
    CveEntry("CVE-2022-3517", Severity.high, "minimatch", "3.0.5",
        "ReDoS via crafted glob pattern"),
    CveEntry("CVE-2020-7788", Severity.high, "ini", "1.3.6",
        "Prototype pollution via crafted INI string"),
    CveEntry("CVE-2022-38900", Severity.high, "decode-uri-component", "0.2.1",
        "Denial of service via crafted encoded URI"),
    CveEntry("CVE-2025-23061", Severity.high, "mongoose", "8.9.5",
        "Search injection via crafted query object"),

    // ---- MEDIUM ----
    CveEntry("CVE-2022-25883", Severity.medium, "semver", "7.5.2",
        "ReDoS via crafted semver string"),
    CveEntry("CVE-2020-15366", Severity.medium, "ajv", "6.12.3",
        "Prototype pollution via crafted schema"),
    CveEntry("CVE-2021-29060", Severity.medium, "color-string", "1.5.5",
        "ReDoS via crafted color string"),

    // ---- LOW ----
    CveEntry("CVE-2017-16137", Severity.low, "debug", "4.3.1",
        "ReDoS via crafted debug string"),
    CveEntry("CVE-2024-47764", Severity.low, "cookie", "0.7.0",
        "Cookie value parsing bypass"),
];

static assert(CVE_DATABASE.length >= 20,
    "CVE database must contain at least 20 entries");

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

AuditResult[] checkPackage(string name, string version_, bool useApi = false) @trusted
{
    assert(name.length > 0, "Package name must not be empty");

    CveEntry[] vulns;

    // Check static database first (always available, no network needed)
    foreach (ref entry; CVE_DATABASE)
    {
        if (entry.packageName != name)
            continue;

        if (entry.fixedVersion.length == 0)
        {
            vulns ~= CveEntry(entry.cveId, entry.severity,
                entry.packageName, entry.fixedVersion, entry.description);
            continue;
        }

        if (isVersionVulnerable(version_, entry.fixedVersion))
            vulns ~= CveEntry(entry.cveId, entry.severity,
                entry.packageName, entry.fixedVersion, entry.description);
    }

    // Query OSV API for live vulnerability data
    if (useApi)
    {
        auto apiVulns = queryOsvApi(name, version_);
        foreach (ref av; apiVulns)
        {
            bool duplicate = false;
            foreach (ref existing; vulns)
            {
                if (existing.cveId == av.cveId)
                {
                    duplicate = true;
                    break;
                }
            }
            if (!duplicate)
                vulns ~= av;
        }
    }

    AuditResult[] results;
    if (vulns.length > 0)
        results ~= AuditResult(name, version_, vulns, true);

    return results;
}

AuditResult[] auditNodeModules(bool useApi = false) @trusted
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
            auto results = checkPackage(pkgName, ver, useApi);
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
// OSV API integration (https://api.osv.dev)
// ---------------------------------------------------------------------------

private CveEntry[] queryOsvApi(string packageName, string version_) @trusted
{
    assert(packageName.length > 0);

    CveEntry[] results;

    try
    {
        import dun.builtins.fetch : doFetch;
        import std.json : parseJSON, JSONType;

        string body_ = `{"version":"` ~ escapeJson(version_)
            ~ `","package":{"name":"` ~ escapeJson(packageName)
            ~ `","ecosystem":"npm"}}`;

        auto resp = doFetch(
            "https://api.osv.dev/v1/query", "POST", body_, false, null);

        if (!resp.ok || resp.body_.length == 0)
            return results;

        auto j = parseJSON(resp.body_);
        if ("vulns" !in j)
            return results;

        auto vulns = j["vulns"].array;
        foreach (ref vuln; vulns)
        {
            string id = ("id" in vuln) ? vuln["id"].str : "";
            if (id.length == 0)
                continue;

            // Extract severity from database_specific or severity array
            Severity sev = Severity.medium;
            if ("database_specific" in vuln)
            {
                auto dbSpec = vuln["database_specific"];
                if ("severity" in dbSpec)
                {
                    auto sevStr = dbSpec["severity"].str;
                    sev = parseSeverityString(sevStr);
                }
            }
            if ("severity" in vuln && vuln["severity"].type == JSONType.array)
            {
                auto sevArr = vuln["severity"].array;
                if (sevArr.length > 0 && "score" in sevArr[0])
                {
                    auto scoreStr = sevArr[0]["score"].str;
                    sev = parseCvssScore(scoreStr);
                }
            }

            // Extract summary
            string summary = ("summary" in vuln) ? vuln["summary"].str : id;

            // Extract fixed version from affected[].ranges[].events[]
            string fixedVer;
            if ("affected" in vuln)
            {
                auto affected = vuln["affected"].array;
                foreach (ref aff; affected)
                {
                    if ("ranges" !in aff) continue;
                    foreach (ref range; aff["ranges"].array)
                    {
                        if ("events" !in range) continue;
                        foreach (ref ev; range["events"].array)
                        {
                            if ("fixed" in ev)
                            {
                                fixedVer = ev["fixed"].str;
                                break;
                            }
                        }
                        if (fixedVer.length > 0) break;
                    }
                    if (fixedVer.length > 0) break;
                }
            }

            // Prefer CVE alias over GHSA ID
            string cveId = id;
            if ("aliases" in vuln)
            {
                foreach (ref alias_; vuln["aliases"].array)
                {
                    auto a = alias_.str;
                    if (a.length >= 4 && a[0 .. 4] == "CVE-")
                    {
                        cveId = a;
                        break;
                    }
                }
            }

            // Truncate long summaries
            if (summary.length > 120)
                summary = summary[0 .. 117] ~ "...";

            results ~= CveEntry(cveId, sev, packageName, fixedVer, summary);
        }
    }
    catch (Exception)
    {
        // API unavailable -- fall back to static database silently
    }

    return results;
}

private:

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
    // Parse CVSS vector to extract score, or just map known ranges
    // CVSS 3.x: "CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H" -> 9.8
    // We'll parse the numeric score if present, otherwise estimate from vector
    double score = 5.0;
    // Try to find a raw numeric score at the start
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

bool isVersionVulnerable(string installed, string fixedIn) pure nothrow @safe
{
    if (installed.length == 0 || fixedIn.length == 0)
        return true;
    return compareSemver(installed, fixedIn) < 0;
}

int compareSemver(string a, string b) pure nothrow @safe
{
    auto av = parseSemverParts(a);
    auto bv = parseSemverParts(b);

    if (av[0] != bv[0]) return av[0] < bv[0] ? -1 : 1;
    if (av[1] != bv[1]) return av[1] < bv[1] ? -1 : 1;
    if (av[2] != bv[2]) return av[2] < bv[2] ? -1 : 1;

    // Pre-release: "1.0.0-alpha" < "1.0.0"
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
    // isVersionVulnerable: version below fix is vulnerable
    assert(isVersionVulnerable("4.17.19", "4.17.20"));
    assert(!isVersionVulnerable("4.17.20", "4.17.20"));
    assert(!isVersionVulnerable("4.17.21", "4.17.20"));
    assert(!isVersionVulnerable("4.18.1", "4.17.20"));
    assert(isVersionVulnerable("7.0.0", "7.0.5"));
    assert(!isVersionVulnerable("7.0.5", "7.0.5"));
}

unittest
{
    // checkPackage: lodash 4.17.19 has known CVEs (static DB)
    auto results = checkPackage("lodash", "4.17.19");
    assert(results.length > 0, "lodash 4.17.19 should have vulnerabilities");
    assert(results[0].isVulnerable);
    assert(results[0].vulnerabilities.length >= 2);
}

unittest
{
    // checkPackage: lodash 4.18.1 is patched (static DB)
    auto results = checkPackage("lodash", "4.18.1");
    assert(results.length == 0, "lodash 4.18.1 should have no vulnerabilities");
}

unittest
{
    // checkPackage: jsonpath has no fix (always vulnerable)
    auto results = checkPackage("jsonpath", "1.3.0");
    assert(results.length > 0, "jsonpath should always be vulnerable");
    assert(results[0].vulnerabilities[0].fixedVersion.length == 0);
    assert(results[0].vulnerabilities[0].severity == Severity.critical);
}

unittest
{
    // checkPackage: cross-spawn 7.0.0 is vulnerable, 7.0.5 is not
    auto r1 = checkPackage("cross-spawn", "7.0.0");
    assert(r1.length > 0, "cross-spawn 7.0.0 should be vulnerable");
    auto r2 = checkPackage("cross-spawn", "7.0.5");
    assert(r2.length == 0, "cross-spawn 7.0.5 should be patched");
}

unittest
{
    // checkPackage: unknown package returns empty (static DB only)
    auto results = checkPackage("unknown-safe-pkg", "1.0.0");
    assert(results.length == 0);
}

unittest
{
    // worstSeverity
    assert(worstSeverity([]) == Severity.none);

    auto r = checkPackage("jsonpath", "1.3.0");
    assert(worstSeverity(r) == Severity.critical);

    auto r2 = checkPackage("debug", "3.0.0");
    assert(worstSeverity(r2) == Severity.low);
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
    // Database integrity: every entry has required fields
    foreach (ref entry; CVE_DATABASE)
    {
        assert(entry.cveId.length > 0, "CVE ID must not be empty");
        assert(entry.packageName.length > 0, "Package name must not be empty");
        assert(entry.description.length > 0, "Description must not be empty");
    }
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
