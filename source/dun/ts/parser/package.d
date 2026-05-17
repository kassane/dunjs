module dun.ts.parser;

// AST parser port from oven-sh/bun's `src/js_parser/` (Zig, MIT).
// Currently lexer-only; see TS-PARSER-PORT.md for the project plan.
// Bun parses TS/JS in a single pass with a tokenizer matching the
// `T.t_*` enum in lexer.d; the parser layer (when ported) sits on top.
public import dun.ts.parser.lexer;
