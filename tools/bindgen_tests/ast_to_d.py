#!/usr/bin/env python3
"""
C -> D bindgen via clang -ast-dump=json (sokol-d pattern)
Parses clang AST JSON and generates D extern(C) declarations.

Usage: clang -Xclang -ast-dump=json -fsyntax-only header.h | python3 ast_to_d.py header.h
"""

import json
import sys

TARGET_FILE = sys.argv[1] if len(sys.argv) > 1 else ""

C_TO_D_TYPES = {
    "void": "void",
    "int": "int",
    "unsigned int": "uint",
    "char": "char",
    "unsigned char": "ubyte",
    "short": "short",
    "unsigned short": "ushort",
    "long": "long",
    "unsigned long": "ulong",
    "long long": "long",
    "unsigned long long": "ulong",
    "float": "float",
    "double": "double",
    "size_t": "size_t",
    "int32_t": "int",
    "uint32_t": "uint",
    "int64_t": "long",
    "uint64_t": "ulong",
    "_Bool": "bool",
    "bool": "bool",
}

def c_type_to_d(ctype):
    """Convert a C type string to D equivalent."""
    ctype = ctype.strip()

    # Pointer types
    if ctype.endswith("*"):
        inner = ctype[:-1].strip()
        if inner == "const char":
            return "const(char)*"
        if inner == "void":
            return "void*"
        d_inner = c_type_to_d(inner)
        return f"{d_inner}*"

    # const qualifier
    if ctype.startswith("const "):
        inner = ctype[6:].strip()
        return f"const({c_type_to_d(inner)})"

    # Known type mappings
    if ctype in C_TO_D_TYPES:
        return C_TO_D_TYPES[ctype]

    # Struct/typedef pass-through
    if ctype.startswith("struct "):
        return ctype[7:]

    return ctype

def is_from_target(node):
    """Check if a node originates from the target file."""
    loc = node.get("loc", {})
    file = loc.get("file", loc.get("includedFrom", {}).get("file", ""))
    return TARGET_FILE in file

def extract_functions(ast):
    """Extract function declarations from clang AST."""
    functions = []
    typedefs = []
    opaques = []

    def visit(nodes):
        for node in nodes:
            kind = node.get("kind")
            name = node.get("name", "")

            # Recurse into LinkageSpecDecl (extern "C" blocks)
            if kind == "LinkageSpecDecl":
                visit(node.get("inner", []))
                continue

            if kind == "RecordDecl" and name and not node.get("inner"):
                opaques.append(name)

            elif kind == "TypedefDecl" and name:
                typedef_type = node.get("type", {}).get("qualType", "")
                if "(*)" in typedef_type:
                    # Function pointer callback typedef
                    typedefs.append(("funcptr", name, typedef_type))
                elif typedef_type.startswith("struct "):
                    target = typedef_type.replace("struct ", "")
                    if target == name:
                        # typedef struct Foo Foo; -> opaque struct
                        opaques.append(name)
                    else:
                        typedefs.append(("alias", name, target))
                else:
                    typedefs.append(("type", name, typedef_type))

            elif kind == "FunctionDecl" and name:
                ret_type = node.get("type", {}).get("qualType", "")
                paren = ret_type.find("(")
                if paren > 0:
                    ret = ret_type[:paren].strip()
                else:
                    ret = ret_type

                params = []
                for child in node.get("inner", []):
                    if child.get("kind") == "ParmVarDecl":
                        pname = child.get("name", "")
                        ptype = child.get("type", {}).get("qualType", "")
                        params.append((ptype, pname))

                functions.append((name, ret, params))

    # Clang AST JSON only emits 'file' when it changes from the previous decl.
    # Track current file and include nodes that belong to the target.
    current_file = [""]  # mutable container for closure
    target_nodes = []

    def get_file(node):
        """Extract file from node loc, checking multiple possible keys."""
        loc = node.get("loc", {})
        for key in ("file", "spellingLoc", "expansionLoc"):
            v = loc.get(key, "")
            if isinstance(v, dict):
                v = v.get("file", "")
            if v:
                return v
        return ""

    def collect_from(nodes, parent_file=""):
        """Collect target declarations, tracking file context."""
        for node in nodes:
            f = get_file(node)
            if f:
                current_file[0] = f
            elif parent_file:
                current_file[0] = parent_file

            if node.get("kind") == "LinkageSpecDecl":
                # Propagate file from LinkageSpecDecl to children
                collect_from(node.get("inner", []), current_file[0])
            elif TARGET_FILE in current_file[0]:
                target_nodes.append(node)

    collect_from(ast.get("inner", []))
    visit(target_nodes)

    return opaques, typedefs, functions

def generate_d(opaques, typedefs, functions, module_name="bindings"):
    """Generate D source from extracted declarations."""
    lines = [f"module {module_name};", "", "extern(C) nothrow @nogc:", ""]

    # Opaque types
    if opaques:
        for name in opaques:
            lines.append(f"struct {name};")
        lines.append("")

    # Typedefs / aliases
    for kind, name, target in typedefs:
        if kind == "alias":
            lines.append(f"alias {name} = {target}*;")
        elif kind == "funcptr":
            lines.append(f"// TODO: function pointer typedef {name}")
        else:
            d_type = c_type_to_d(target)
            lines.append(f"alias {name} = {d_type};")
    if typedefs:
        lines.append("")

    # Functions
    for name, ret, params in functions:
        d_ret = c_type_to_d(ret)
        d_params = []
        for ptype, pname in params:
            d_type = c_type_to_d(ptype)
            d_params.append(f"{d_type} {pname}" if pname else d_type)
        param_str = ", ".join(d_params)
        lines.append(f"{d_ret} {name}({param_str});")

    return "\n".join(lines) + "\n"

# Main
ast = json.load(sys.stdin)
opaques, typedefs, functions = extract_functions(ast)
print(generate_d(opaques, typedefs, functions))
print(f"// Generated: {len(opaques)} opaque types, {len(typedefs)} typedefs, {len(functions)} functions")
