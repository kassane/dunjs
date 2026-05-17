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

/// Install a package into `installRoot/node_modules/<name>`. The default
/// `"."` mirrors npm's behaviour (cwd-relative). Pass an absolute path
/// like `~/.dun` (expanded) to install into the user-global DunJS store.
bool installPackage(string spec, AuditMode auditMode = AuditMode.warn,
    string installRoot = ".") @trusted
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

    string nmDir = buildNormalizedPath(installRoot, "node_modules", name);
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
                    auto depDir = buildNormalizedPath(installRoot, "node_modules", depName);
                    if (!exists(depDir))
                    {
                        installPackage(depName ~ "@" ~ depRange.str, auditMode, installRoot);
                    }
                }
            }
        }
        catch (Exception) {}
    }

    runLifecycleScripts(nmDir, name);
    createBinLinks(nmDir, name);

    // Record the install in dun.lock + package-lock.json so downstream
    // tooling (CI cache restorers, IDE plugins, other runtimes that
    // honor those formats) can reproduce the resolution. Best-effort —
    // a failure to write the lockfile doesn't fail the install.
    try { recordLockEntry(name, version_, tarballUrl); } catch (Exception) {}

    writefln("installed %s@%s", name, version_);
    return true;
}

/// Append `{ name, version, resolved }` to dun.lock + package-lock.json.
/// Both files are written in node-compatible npm-style format so other
/// tools can consume them.
private void recordLockEntry(string name, string version_, string resolved) @trusted
{
    import std.file : exists, readText, write;
    import std.json : parseJSON, JSONValue, JSONType;
    import std.path : buildPath;

    // dun.lock: { lockfileVersion: 1, packages: { "node_modules/<name>": {...} } }
    string dunLockPath = "dun.lock";
    JSONValue lock;
    if (exists(dunLockPath))
    {
        try { lock = parseJSON(readText(dunLockPath)); }
        catch (Exception) { lock = JSONValue.emptyObject; }
    }
    else lock = JSONValue.emptyObject;

    if ("lockfileVersion" !in lock) lock["lockfileVersion"] = 1;
    if ("packages" !in lock) lock["packages"] = JSONValue.emptyObject;

    auto pkgKey = "node_modules/" ~ name;
    JSONValue entry = JSONValue.emptyObject;
    entry["version"] = version_;
    entry["resolved"] = resolved;
    lock["packages"][pkgKey] = entry;

    try { write(dunLockPath, lock.toPrettyString); } catch (Exception) {}

    // package-lock.json (npm v3 format) — same data, different schema.
    string npmLockPath = "package-lock.json";
    JSONValue npmLock;
    if (exists(npmLockPath))
    {
        try { npmLock = parseJSON(readText(npmLockPath)); }
        catch (Exception) { npmLock = JSONValue.emptyObject; }
    }
    else npmLock = JSONValue.emptyObject;

    if ("name" !in npmLock) npmLock["name"] = "dun-project";
    if ("lockfileVersion" !in npmLock) npmLock["lockfileVersion"] = 3;
    if ("packages" !in npmLock) npmLock["packages"] = JSONValue.emptyObject;

    JSONValue npmEntry = JSONValue.emptyObject;
    npmEntry["version"] = version_;
    npmEntry["resolved"] = resolved;
    npmLock["packages"][pkgKey] = npmEntry;

    try { write(npmLockPath, npmLock.toPrettyString); } catch (Exception) {}
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

void createBinLinks(string pkgDir, string pkgName) @trusted
{
    import std.file : exists, readText, mkdirRecurse;
    import std.json : parseJSON, JSONType;
    import std.path : buildNormalizedPath, absolutePath, relativePath, dirName;

    auto pkgJson = buildNormalizedPath(pkgDir, "package.json");
    if (!exists(pkgJson)) return;

    try
    {
        auto j = parseJSON(readText(pkgJson));
        if ("bin" !in j) return;

        // pkgDir == <installRoot>/node_modules/<name>; .bin sibling.
        auto binDir = buildNormalizedPath(dirName(pkgDir), ".bin");
        mkdirRecurse(binDir);

        if (j["bin"].type == JSONType.string)
        {
            auto target = j["bin"].str;
            auto targetAbs = absolutePath(buildNormalizedPath(pkgDir, target));
            auto linkPath = buildNormalizedPath(binDir, pkgName);
            createSymlinkAndChmod(linkPath, targetAbs);
        }
        else if (j["bin"].type == JSONType.object)
        {
            foreach (binName, binTarget; j["bin"].object)
            {
                auto target = binTarget.str;
                auto targetAbs = absolutePath(buildNormalizedPath(pkgDir, target));
                auto linkPath = buildNormalizedPath(binDir, binName);
                createSymlinkAndChmod(linkPath, targetAbs);
            }
        }
    }
    catch (Exception) {}
}

private void createSymlinkAndChmod(string linkPath, string targetPath) @trusted
{
    import std.file : exists, remove, symlink;
    version (Posix) import core.sys.posix.sys.stat : chmod;

    try
    {
        if (exists(linkPath)) remove(linkPath);
        symlink(targetPath, linkPath);
        version (Posix)
        {
            import std.string : toStringz;
            chmod(toStringz(targetPath), 0b111_101_101); // 0755
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
        import std.algorithm : startsWith;
        auto registryUrl = name.startsWith("@jsr/")
            ? "https://npm.jsr.io/"
            : "https://registry.npmjs.org/";
        auto result = doFetch(
            registryUrl ~ name, "GET", "", false, null);
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

            // Bare major / major.minor: install latest in that range.
            // e.g. "4" -> latest 4.x.x, "4.18" -> latest 4.18.x
            import std.algorithm : count;
            import std.string : indexOf;
            auto dotCount = cleaned.count('.');
            if (dotCount == 0)
            {
                // "4" — synthesize "4.0.0" for findBestMatch in caret mode
                return findBestMatch(versions, cleaned ~ ".0.0", true);
            }
            if (dotCount == 1)
            {
                // "4.18" — synthesize "4.18.0" for findBestMatch in tilde mode
                return findBestMatch(versions, cleaned ~ ".0", false);
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
