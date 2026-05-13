// Tiny backend switcher for distroless containers (no shell needed).
// Reads DUN_BACKEND env (default: "quickjs") and exec's /usr/local/bin/dun-<backend>.
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <stdio.h>

int main(int argc, char **argv) {
    const char *backend = getenv("DUN_BACKEND");
    if (!backend || !*backend)
        backend = "quickjs";

    if (strcmp(backend, "quickjs") != 0
        && strcmp(backend, "jsc") != 0
        && strcmp(backend, "v8") != 0) {
        fprintf(stderr, "error: unknown backend '%s' (use quickjs, jsc, or v8)\n", backend);
        return 1;
    }

    char path[256];
    snprintf(path, sizeof(path), "/usr/local/bin/dun-%s", backend);

    argv[0] = path;
    execv(path, argv);

    perror(path);
    return 1;
}
