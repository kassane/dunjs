module dun.platform.sqlite3;

// SQLite3 bindings via ImportC — generated from the real sqlite3.h header.
// The vendor/sqlite/sqlite3_api.c bridge is compiled by ImportC (DUB cSourceFiles),
// which processes #include "sqlite3.h" and makes all declarations available as D symbols.
//
// This replaces manual extern(C) declarations with compiler-verified bindings.

public import sqlite3_api;
