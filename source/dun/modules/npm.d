module dun.modules.npm;

enum AuditMode
{
    warn,
    block,
    off,
}

static assert(__traits(allMembers, AuditMode).length == 3,
    "AuditMode enum member count changed -- update parseAuditFlag");

version (Posix):

import std.stdio : writeln, writefln;

bool installPackage(string spec, AuditMode auditMode = AuditMode.warn) @trusted
{
    import std.string : indexOf;
    import std.file : exists, mkdirRecurse, write;
    import std.path : buildNormalizedPath;

    assert(spec.length > 0, "Package spec must not be empty");

    string name, versionRange;
    auto atIdx = spec.indexOf('@');
    if (atIdx > 0)
    {
        name = spec[0 .. atIdx];
        versionRange = spec[atIdx + 1 .. $];
    }
    else
    {
        name = spec;
        versionRange = "latest";
    }

    writefln("resolving %s@%s...", name, versionRange);

    auto meta = fetchPackageMeta(name);
    if (meta.name.length == 0)
    {
        writeln("error: package not found: ", name);
        return false;
    }

    string version_ = resolveVersion(meta, versionRange);
    if (version_.length == 0)
    {
        writeln("error: no matching version for ", versionRange);
        return false;
    }

    // Pre-download CVE audit (queries OSV API, falls back to cache)
    if (auditMode != AuditMode.off)
    {
        import dun.security.cve_db : checkPackage, worstSeverity, Severity,
            severityString, severityColor;

        auto vulns = checkPackage(name, version_);
        if (vulns.length > 0)
        {
            auto worst = worstSeverity(vulns);
            foreach (ref r; vulns)
            {
                foreach (ref v; r.vulnerabilities)
                {
                    writefln("\033[1;33mWARN\033[0m %s%s\033[0m %s@%s: %s (%s)%s",
                        severityColor(v.severity),
                        severityString(v.severity),
                        name, version_,
                        v.description,
                        v.cveId,
                        v.fixedVersion.length > 0
                            ? " [fixed in " ~ v.fixedVersion ~ "]"
                            : " [no fix available]");
                }
            }

            if (auditMode == AuditMode.block &&
                (worst == Severity.critical || worst == Severity.high))
            {
                writefln("\033[1;31mBLOCKED\033[0m %s@%s has %s severity vulnerability. "
                    ~ "Use --audit=warn to install anyway.", name, version_,
                    severityString(worst));
                return false;
            }
        }
    }

    string tarballUrl = getTarballUrl(meta, version_);
    if (tarballUrl.length == 0)
    {
        writeln("error: no tarball URL for ", name, "@", version_);
        return false;
    }

    writefln("downloading %s@%s...", name, version_);

    auto tarball = downloadTarball(tarballUrl);
    if (tarball.length == 0)
    {
        writeln("error: failed to download tarball");
        return false;
    }

    string nmDir = buildNormalizedPath(".", "node_modules", name);
    writefln("extracting to %s...", nmDir);

    if (!extractTarGz(tarball, nmDir))
    {
        writeln("error: failed to extract package");
        return false;
    }

    // Install dependencies recursively
    auto pkgJson = buildNormalizedPath(nmDir, "package.json");
    if (exists(pkgJson))
    {
        try
        {
            import std.file : readText;
            import std.json : parseJSON;
            auto j = parseJSON(readText(pkgJson));
            if ("dependencies" in j)
            {
                auto deps = j["dependencies"].object;
                foreach (depName, depRange; deps)
                {
                    auto depDir = buildNormalizedPath(".", "node_modules", depName);
                    if (!exists(depDir))
                    {
                        installPackage(depName ~ "@" ~ depRange.str, auditMode);
                    }
                }
            }
        }
        catch (Exception) {}
    }

    runLifecycleScripts(nmDir, name);

    writefln("installed %s@%s", name, version_);
    return true;
}

/// Run a named script from the project's package.json.
/// Returns true if the script was found and executed, false if not found.
bool runPackageScript(string scriptName) @trusted
{
    import std.file : exists, readText;
    import std.json : parseJSON, JSONType;
    import std.process : spawnShell, wait;

    auto pkgPath = "package.json";
    if (!exists(pkgPath))
    {
        writefln("error: no package.json found");
        return false;
    }

    try
    {
        auto j = parseJSON(readText(pkgPath));
        if ("scripts" !in j || j["scripts"].type != JSONType.object)
        {
            writefln("error: no scripts in package.json");
            return false;
        }
        auto scripts = j["scripts"].object;
        if (scriptName !in scripts)
        {
            writefln("error: script '%s' not found in package.json", scriptName);
            writeln("available scripts:");
            foreach (k; scripts.byKey())
                writefln("  %s", k);
            return false;
        }
        auto cmd = scripts[scriptName].str;
        writefln("$ %s", cmd);
        auto pid = spawnShell(cmd);
        auto rc = wait(pid);
        return rc == 0;
    }
    catch (Exception e)
    {
        writefln("error: %s", e.msg);
        return false;
    }
}

private:

void runLifecycleScripts(string pkgDir, string pkgName) @trusted
{
    import std.file : exists, readText;
    import std.json : parseJSON, JSONType;
    import std.path : buildNormalizedPath;
    import std.process : spawnShell, wait, Config;

    auto pkgJson = buildNormalizedPath(pkgDir, "package.json");
    if (!exists(pkgJson)) return;

    try
    {
        auto j = parseJSON(readText(pkgJson));
        if ("scripts" !in j || j["scripts"].type != JSONType.object) return;

        auto scripts = j["scripts"].object;
        static immutable phases = ["preinstall", "install", "postinstall"];
        foreach (phase; phases)
        {
            if (phase in scripts)
            {
                auto cmd = scripts[phase].str;
                writefln("  running %s script for %s: %s", phase, pkgName, cmd);
                auto pid = spawnShell(cmd, null, Config.none, pkgDir);
                auto rc = wait(pid);
                if (rc != 0)
                    writefln("  warning: %s script exited with code %d", phase, rc);
            }
        }
    }
    catch (Exception) {}
}

struct PackageMeta
{
    string name;
    string latestVersion;
    string rawJson;
}

PackageMeta fetchPackageMeta(string name) @trusted
{
    import dun.builtins.fetch : doFetch;

    PackageMeta meta;
    try
    {
        auto result = doFetch(
            "https://registry.npmjs.org/" ~ name, "GET", "", false, null);
        if (!result.ok)
            return meta;

        import std.json : parseJSON;
        auto j = parseJSON(result.body_);
        meta.name = j["name"].str;
        meta.rawJson = result.body_;

        if ("dist-tags" in j && "latest" in j["dist-tags"])
            meta.latestVersion = j["dist-tags"]["latest"].str;
    }
    catch (Exception) {}
    return meta;
}

string resolveVersion(PackageMeta meta, string range) @trusted
{
    if (range == "latest" || range.length == 0)
        return meta.latestVersion;

    // For exact versions, check if they exist
    try
    {
        import std.json : parseJSON;
        auto j = parseJSON(meta.rawJson);
        if ("versions" in j)
        {
            auto versions = j["versions"].object;

            // Strip leading ^ ~ >= from range for simple matching
            string cleaned = range;
            while (cleaned.length > 0 &&
                (cleaned[0] == '^' || cleaned[0] == '~' ||
                 cleaned[0] == '>' || cleaned[0] == '=' ||
                 cleaned[0] == '<' || cleaned[0] == ' '))
                cleaned = cleaned[1 .. $];

            // Try exact match first
            if (cleaned in versions)
                return cleaned;

            // For ^x.y.z, find latest matching major
            if (range.length > 0 && range[0] == '^')
            {
                return findBestMatch(versions, cleaned, true);
            }
            // For ~x.y.z, find latest matching major.minor
            else if (range.length > 0 && range[0] == '~')
            {
                return findBestMatch(versions, cleaned, false);
            }

            // Fallback: try latest
            return meta.latestVersion;
        }
    }
    catch (Exception) {}

    return meta.latestVersion;
}

string findBestMatch(typeof(null)[string] versions, string baseVer, bool caretMode) @trusted
{
    // Intentionally simplified: for ^ ranges, accept latest
    // Full semver implementation would be more complex
    return "";
}

import std.json : JSONValue;

string findBestMatch(JSONValue[string] versions, string baseVer, bool caretMode) @trusted
{
    import std.string : indexOf;
    import std.conv : to;

    auto dotIdx = baseVer.indexOf('.');
    if (dotIdx < 0) return "";

    string major = baseVer[0 .. dotIdx];
    string best;
    int bestMinor = -1, bestPatch = -1;

    foreach (ver, _; versions)
    {
        auto d1 = ver.indexOf('.');
        if (d1 < 0) continue;
        if (ver[0 .. d1] != major) continue;

        auto rest = ver[d1 + 1 .. $];
        auto d2 = rest.indexOf('.');
        if (d2 < 0) continue;

        try
        {
            int minor = rest[0 .. d2].to!int;
            string patchStr = rest[d2 + 1 .. $];
            auto dashIdx = patchStr.indexOf('-');
            if (dashIdx >= 0) patchStr = patchStr[0 .. dashIdx];
            int patch = patchStr.to!int;

            if (minor > bestMinor || (minor == bestMinor && patch > bestPatch))
            {
                bestMinor = minor;
                bestPatch = patch;
                best = ver;
            }
        }
        catch (Exception) { continue; }
    }

    return best;
}

string getTarballUrl(PackageMeta meta, string version_) @trusted
{
    try
    {
        import std.json : parseJSON;
        auto j = parseJSON(meta.rawJson);
        if ("versions" in j && version_ in j["versions"])
        {
            auto vInfo = j["versions"][version_];
            if ("dist" in vInfo && "tarball" in vInfo["dist"])
                return vInfo["dist"]["tarball"].str;
        }
    }
    catch (Exception) {}
    return "";
}

ubyte[] downloadTarball(string url) @trusted
{
    import dun.builtins.fetch : doFetch;

    try
    {
        auto result = doFetch(url, "GET", "", false, null);
        if (!result.ok) return null;
        return cast(ubyte[]) result.body_.dup;
    }
    catch (Exception) { return null; }
}

bool extractTarGz(ubyte[] data, string destDir) @trusted
{
    import std.process : execute;
    import std.file : mkdirRecurse, write, exists, rename, dirEntries, SpanMode;
    import std.path : buildNormalizedPath;

    // Write tarball to temp file, use system tar to extract
    string tmpFile = "/tmp/dun_pkg_" ~ randomHex(8) ~ ".tgz";
    bool ok = false;
    try
    {
        write(tmpFile, data);

        string tmpDir = tmpFile ~ ".d";
        mkdirRecurse(tmpDir);

        auto result = execute(["tar", "xzf", tmpFile, "-C", tmpDir]);
        if (result.status == 0)
        {
            string packageDir = buildNormalizedPath(tmpDir, "package");
            if (!exists(packageDir))
            {
                foreach (entry; dirEntries(tmpDir, SpanMode.shallow))
                {
                    if (entry.isDir) { packageDir = entry.name; break; }
                }
            }

            if (exists(packageDir))
            {
                mkdirRecurse(destDir);
                auto mvResult = execute(["cp", "-r", packageDir ~ "/.", destDir]);
                ok = mvResult.status == 0;
            }
        }
    }
    catch (Exception) {}

    cleanup(tmpFile);
    return ok;
}

private void cleanup(string tmpFile) @trusted nothrow
{
    import std.file : remove, rmdirRecurse;
    try { remove(tmpFile); } catch (Throwable) {}
    try { rmdirRecurse(tmpFile ~ ".d"); } catch (Throwable) {}
}

string randomHex(size_t len) @trusted
{
    import std.random : uniform;
    import std.format : format;
    string result;
    foreach (_; 0 .. len)
    {
        try { result ~= format!"%x"(uniform(0, 16)); }
        catch (Exception) { result ~= "0"; }
    }
    return result;
}
