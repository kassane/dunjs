// ImportC stub for QuickJS-NG — follows bdwgc-d pattern.
// dmd-frontend v2.111.0 feature
//
// quickjs.h includes <stdio.h> which triggers the glibc _IO_lock_t
// ImportC bug. We provide minimal shims for the types quickjs.h
// actually needs and skip the real stdio/string/math headers.
#define _STDIO_H 1
#define _STRING_H 1
#define _MATH_H 1

#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

typedef struct _IO_FILE FILE;

#define JS_EXTERN

#pragma attribute(push, nothrow, nogc)

// Shim declarations for libc functions used by quickjs.h inlines
double fmin(double, double);
double fabs(double);
void *memcpy(void *, const void *, size_t);
void *memmove(void *, const void *, size_t);
void *memset(void *, int, size_t);
size_t strlen(const char *);

#include <quickjs.h>

#pragma attribute(pop)
