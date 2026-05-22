# DunJS Container — CIS-hardened, multi-backend, multi-platform
#
# CIS Docker Benchmark coverage (image scope):
#   4.1   non-root USER                            ✓
#   4.2   pinned base image (tag + digest)         ✓
#   4.3   --no-install-recommends                  ✓
#   4.6   HEALTHCHECK                              ✓
#   4.7   apt-get update + install in same RUN     ✓
#   4.8   strip SUID/SGID bits                     ✓
#   4.9   COPY over ADD                            ✓
#   4.10  no secrets in build context              ✓
#   4.11  sha256-verify downloaded toolchain       ✓
#
# Recommended runtime flags (CIS section 5, image-side reminder):
#   docker run --read-only --tmpfs /tmp \
#     --cap-drop=ALL --security-opt no-new-privileges:true \
#     --pids-limit 256 --memory=512m dunjs:quickjs run script.js
#
# Usage:
#   docker build --build-arg BACKEND=quickjs -t dunjs:quickjs .
#   docker build --build-arg BACKEND=jsc -t dunjs:jsc .
#   docker build --build-arg BACKEND=v8 -t dunjs:v8 .
#
# Multi-platform:
#   docker buildx build --platform linux/amd64,linux/arm64 \
#     --build-arg BACKEND=quickjs -t dunjs:quickjs .

# ─── Stage 1: Build ───────────────────────────────────────────
# CIS 4.2 — base image pinned by digest. Update with:
#   docker pull debian:bookworm-slim && docker inspect debian:bookworm-slim | jq -r .[0].RepoDigests
FROM debian:bookworm-slim@sha256:67b30a61dc87758f0caf819646104f29ecbda97d920aaf5edc834128ac8493d3 AS build

ARG BACKEND=quickjs
ARG LDC_VERSION=1.42.0
# TARGETARCH is set automatically by buildx: "amd64" or "arm64"
ARG TARGETARCH

# CIS 4.11 — sha256s for the LDC toolchain tarballs.
# Override at build time if you need a newer release:
#   docker build --build-arg LDC_VERSION=... --build-arg LDC_SHA256_AMD64=... --build-arg LDC_SHA256_ARM64=... .
ARG LDC_SHA256_AMD64=a7bc9c956138f558cadf9c962352f59d41c80df6eb3ae3f8039f25be14a69303
ARG LDC_SHA256_ARM64=687707c3e20ff910528eb2d92f27a98cb0960284de3b026e6bf20284ac1c8511

# g++ is required to compile vendor/v8shim/v8shim.cpp (V8 C++ shim)
# V8 14.9+ uses CREL relocations; linking handled by LDC --link-internally (LLVM 21)
# build.d auto-detects CRT paths for Debian/Ubuntu/Arch/RHEL via gcc -dumpmachine
# kassane/libv8 provides prebuilt binaries for both linux-x64 and linux-arm64
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl xz-utils tar gcc g++ cmake make pkg-config git bash \
    libxml2-dev libssl-dev \
    && rm -rf /var/lib/apt/lists/*

# Install LDC: download, verify sha256, extract.
RUN case "${TARGETARCH}" in \
      arm64) LDC_ARCH=aarch64; LDC_SHA="${LDC_SHA256_ARM64}" ;; \
      *)     LDC_ARCH=x86_64;  LDC_SHA="${LDC_SHA256_AMD64}" ;; \
    esac \
    && TARBALL="ldc2-${LDC_VERSION}-linux-${LDC_ARCH}.tar.xz" \
    && curl -sLO --fail "https://github.com/ldc-developers/ldc/releases/download/v${LDC_VERSION}/${TARBALL}" \
    && echo "${LDC_SHA}  ${TARBALL}" | sha256sum -c - \
    && tar -xJf "${TARBALL}" --directory /opt \
    && rm "${TARBALL}" \
    && ln -s /opt/ldc2-${LDC_VERSION}-linux-${LDC_ARCH}/bin/ldc2             /usr/bin/ldc2 \
    && ln -s /opt/ldc2-${LDC_VERSION}-linux-${LDC_ARCH}/bin/ldmd2            /usr/bin/ldmd2 \
    && ln -s /opt/ldc2-${LDC_VERSION}-linux-${LDC_ARCH}/bin/dub              /usr/bin/dub \
    && ln -s /opt/ldc2-${LDC_VERSION}-linux-${LDC_ARCH}/bin/ldc-build-plugin /usr/bin/ldc-build-plugin \
    && ln -s /opt/ldc2-${LDC_VERSION}-linux-${LDC_ARCH}/bin/ldc-build-runtime /usr/bin/ldc-build-runtime

WORKDIR /src
COPY . .
RUN mkdir -p vendor/sqlite vendor/v8/lib vendor/v8/include

# Download and compile vendor deps (build.d selects linux-x64 or linux-arm64 prebuilt automatically)
RUN ldc2 -run build.d --backend=${BACKEND} --force

# Per-arch -mcpu / -mattr baselines. Mirrors Zig std.Target defaults
# on LLVM 21 so we get a deterministic, portable CPU floor instead of
# leaving features '' (per ldc-developers/ldc#4919, named generic
# CPUs like x86-64-v3 resolve to empty feature sets).
#   amd64: Haswell+ baseline (AVX2 + FMA + BMI2)
#   arm64: ARMv8.0 + NEON, Cortex-A53 / Apple Silicon compatible
RUN case "${TARGETARCH:-amd64}" in \
      arm64) export DFLAGS="--mcpu=generic -mattr=+enable-select-opt,+ete,+fp-armv8,+fuse-adrp-add,+fuse-aes,+neon,+trbe,+use-postra-scheduler" ;; \
      *)     export DFLAGS="--mcpu=x86-64-v3 -mattr=+64bit,+avx,+avx2,+bmi,+bmi2,+cmov,+crc32,+cx16,+cx8,+f16c,+fma,+fxsr,+lzcnt,+mmx,+movbe,+popcnt,+sahf,+sse,+sse2,+sse3,+sse4.1,+sse4.2,+ssse3,+x87,+xsave,+allow-light-256-bit,+false-deps-lzcnt-tzcnt,+false-deps-popcnt,+fast-15bytenop,+fast-scalar-fsqrt,+fast-shld-rotate,+fast-variable-crosslane-shuffle,+fast-variable-perlane-shuffle,+idivq-to-divl,+macrofusion,+nopl,+slow-3ops-lea,+vzeroupper" ;; \
    esac \
    && echo "DFLAGS=${DFLAGS}" \
    && dub build -c ${BACKEND} -b release \
    && strip build/dun \
    && ls -la build/dun \
    && touch build/icudtl.dat

# CIS 4.8 — strip any SUID/SGID bits the build pulled in.
RUN find build/dun -perm /6000 -exec chmod a-s {} \; 2>/dev/null || true

# Collect shared library dependencies
RUN mkdir -p /deps/lib \
    && case "${BACKEND}" in \
      jsc) \
        for lib in vendor/jsc/lib/*.so*; do \
          [ -f "$lib" ] && cp -a "$lib" /deps/lib/; \
        done ;; \
    esac \
    && ldd build/dun 2>/dev/null | grep "=> /" | awk '{print $3}' | while read lib; do \
      [ -f "$lib" ] && cp -aL "$lib" /deps/lib/ 2>/dev/null || true; \
    done \
    && find /deps/lib -perm /6000 -exec chmod a-s {} \; 2>/dev/null || true \
    && ls -la /deps/lib/ 2>/dev/null || true

# ─── Stage 2: Runtime ────────────────────────────────────────
FROM debian:bookworm-slim@sha256:67b30a61dc87758f0caf819646104f29ecbda97d920aaf5edc834128ac8493d3

ARG BACKEND=quickjs

# CIS-friendly OCI metadata. `created`/`revision`/`version` are passed in
# at build time by CI to make the resulting image reproducible.
ARG BUILD_DATE="unknown"
ARG VCS_REF="unknown"
ARG VERSION="0.3.0"
LABEL org.opencontainers.image.title="DunJS" \
      org.opencontainers.image.description="Secure JavaScript/TypeScript runtime (${BACKEND} backend)" \
      org.opencontainers.image.url="https://github.com/kassane/dunjs" \
      org.opencontainers.image.source="https://github.com/kassane/dunjs" \
      org.opencontainers.image.documentation="https://github.com/kassane/dunjs#readme" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.vendor="kassane" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.version="${VERSION}-${BACKEND}" \
      org.opencontainers.image.base.name="debian:bookworm-slim"

# Install runtime libs and create the non-root account in one layer.
# UID/GID are fixed at 1001 so Kubernetes `runAsNonRoot: true` and
# `runAsUser: 1001` policies can match it without an entrypoint dance.
RUN apt-get update && apt-get install -y --no-install-recommends \
    libstdc++6 libgcc-s1 libssl3 tini \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd -r -g 1001 dun \
    && useradd -r -u 1001 -g 1001 -d /app -s /usr/sbin/nologin -c "DunJS runtime user" dun \
    && mkdir -p /app \
    && chown -R 1001:1001 /app

# --chown on COPY avoids an extra `RUN chown -R` layer (CIS-favourable
# layering: minimal mutable state on top of read-only image).
COPY --from=build --chown=1001:1001 /src/build/dun /usr/local/bin/dun
COPY --from=build --chown=1001:1001 /deps/lib/      /usr/local/lib/

# V8 ICU data table — copied next to the binary so V8's
# `InitializeICUDefaultLocation(argv[0])` finds it without further
# configuration. The build stage `touch build/icudtl.dat` ensures
# this COPY also succeeds for QJS/JSC images (the touched file is
# empty + harmless because those backends don't load ICU).
# Without this, `docker run dunjs:v8 run any-Intl-script.js` errors
# with `Internal error. Icu error.` from V8's CheckICUOK.
COPY --from=build --chown=1001:1001 /src/build/icudtl.dat /usr/local/bin/icudtl.dat

# CIS 4.8 — make sure no SUID/SGID bits slipped through the copy.
RUN find /usr/local/bin/dun /usr/local/lib -xdev -perm /6000 -exec chmod a-s {} \; 2>/dev/null || true \
    && chmod 0555 /usr/local/bin/dun \
    && chmod 0444 /usr/local/bin/icudtl.dat \
    && ldconfig

WORKDIR /app
USER 1001:1001

# CIS 4.6 — non-zero exit means broken image. We exercise the engine
# rather than just checking that the binary starts.
HEALTHCHECK --interval=30s --timeout=5s --start-period=2s --retries=2 \
    CMD ["/usr/local/bin/dun", "eval", "2+2===4 || process.exit(1)"]

# Forward SIGTERM cleanly via tini, then to dun. dun's signal handlers
# drain timers + close server sockets before exit.
STOPSIGNAL SIGTERM

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/dun"]
