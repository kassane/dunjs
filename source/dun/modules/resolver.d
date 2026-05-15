/// Import specifier resolution (builtins, paths, node_modules).
module dun.modules.resolver;

/// Resolves import specifiers to absolute paths or built-in names.
struct ModuleResolver
{
    private string[string] builtinMap;

    /// Register a built-in module name.
    void registerBuiltin(string name) @safe
    {
        builtinMap[name] = name;
    }

    /// Resolve an import specifier relative to the importer's path.
    /// Returns the resolved path, or null if unresolved.
    string resolve(string specifier, string importerPath) @safe
    {
        import std.path : isAbsolute, buildNormalizedPath, dirName;
        import std.algorithm : startsWith;

        // 0. node:X -> dun:X compatibility alias
        if (specifier.startsWith("node:"))
            specifier = "dun:" ~ specifier[5 .. $];

        // 1. Built-in modules (dun:fs, dun:path, dun:crypto, etc.)
        if (specifier in builtinMap)
            return specifier;

        // Pass through unknown dun: specifiers — loader will error
        if (specifier.startsWith("dun:"))
            return specifier;

        // 2. Absolute paths
        if (isAbsolute(specifier))
            return buildNormalizedPath(specifier);

        // 3. Relative paths
        if (specifier.startsWith("./") || specifier.startsWith("../")
            || specifier.startsWith(".\\") || specifier.startsWith("..\\"))
        {
            auto base = dirName(importerPath);
            return buildNormalizedPath(base, specifier);
        }

        // 4. URL imports (future)
        if (specifier.startsWith("http://") || specifier.startsWith("https://"))
            return null;

        // 5. node_modules walk (npm compat)
        {
            import dun.modules.require : findNodeModule;
            auto base = dirName(importerPath);
            auto resolved_ = findNodeModule(specifier, base);
            if (resolved_.length > 0) return resolved_;
        }

        return null; // Unresolved
    }
}
