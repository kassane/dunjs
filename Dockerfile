# DunJS Container — hardened, multi-backend, multi-platform
# Usage:
#   docker build --build-arg BACKEND=quickjs -t dunjs:quickjs .
#   docker build --build-arg BACKEND=jsc -t dunjs:jsc .
#   docker build --build-arg BACKEND=v8 -t dunjs:v8 .
#   docker run --rm dunjs:quickjs run script.js
#   docker run --rm dunjs:quickjs eval "1+1"
#
# Multi-platform:
#   docker buildx build --platform linux/amd64,linux/arm64 --build-arg BACKEND=quickjs -t dunjs:quickjs .
#   docker buildx build --platform linux/amd64,linux/arm64 --build-arg BACKEND=v8 -t dunjs:v8 .

# ─── Stage 1: Build ───────────────────────────────────────────
FROM debian:bookworm-slim AS build

ARG BACKEND=quickjs
ARG LDC_VERSION=1.42.0
# TARGETARCH is set automatically by buildx: "amd64" or "arm64"
ARG TARGETARCH

# g++ is required to compile vendor/v8shim/v8shim.cpp (V8 C++ shim)
# V8 14.9+ uses CREL relocations; linking handled by LDC --link-internally (LLVM 21)
# build.d auto-detects CRT paths for Debian/Ubuntu/Arch/RHEL via gcc -dumpmachine
# kassane/libv8 provides prebuilt binaries for both linux-x64 and linux-arm64
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl xz-utils tar gcc g++ cmake make pkg-config git bash \
    libxml2-dev libssl-dev \
    && rm -rf /var/lib/apt/lists/*

# Install LDC (arch-aware: amd64→x86_64, arm64→aarch64)
RUN case "${TARGETARCH}" in \
      arm64) LDC_ARCH=aarch64 ;; \
      *)     LDC_ARCH=x86_64  ;; \
    esac \
    && curl -sLO --fail https://github.com/ldc-developers/ldc/releases/download/v${LDC_VERSION}/ldc2-${LDC_VERSION}-linux-${LDC_ARCH}.tar.xz \
    && tar -xJf ldc2-${LDC_VERSION}-linux-${LDC_ARCH}.tar.xz --directory /opt \
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

RUN dub build -c ${BACKEND} -b release \
    && strip build/dun \
    && ls -la build/dun

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
    && ls -la /deps/lib/ 2>/dev/null || true

# ─── Stage 2: Runtime ────────────────────────────────────────
FROM debian:bookworm-slim

ARG BACKEND=quickjs

LABEL org.opencontainers.image.title="DunJS" \
      org.opencontainers.image.description="Secure JavaScript/TypeScript runtime (${BACKEND} backend)" \
      org.opencontainers.image.url="https://github.com/kassane/dunjs" \
      org.opencontainers.image.source="https://github.com/kassane/dunjs"

RUN apt-get update && apt-get install -y --no-install-recommends \
    libstdc++6 libgcc-s1 libssl3 \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd -r dun && useradd -r -g dun -u 1001 -m -d /app dun

COPY --from=build /src/build/dun /usr/local/bin/dun
COPY --from=build /deps/lib/ /usr/local/lib/

RUN ldconfig

WORKDIR /app
RUN chown dun:dun /app
USER dun

ENTRYPOINT ["/usr/local/bin/dun"]
