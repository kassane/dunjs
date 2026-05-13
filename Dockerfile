# DunJS Container — hardened, multi-backend
# Usage:
#   docker build --build-arg BACKEND=quickjs -t dunjs:quickjs .
#   docker build --build-arg BACKEND=jsc -t dunjs:jsc .
#   docker build --build-arg BACKEND=v8 -t dunjs:v8 .
#   docker run --rm dunjs:quickjs run script.js
#   docker run --rm dunjs:quickjs eval "1+1"

# ─── Stage 1: Build ───────────────────────────────────────────
FROM debian:bookworm-slim AS build

ARG BACKEND=quickjs
ARG LDC_VERSION=1.42.0

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl xz-utils tar gcc g++ cmake make pkg-config git bash \
    libxml2-dev libssl-dev linux-headers-amd64 \
    && rm -rf /var/lib/apt/lists/*

# Install LDC
RUN curl -sLO --fail https://github.com/ldc-developers/ldc/releases/download/v${LDC_VERSION}/ldc2-${LDC_VERSION}-linux-x86_64.tar.xz \
    && tar -xJf ldc2-${LDC_VERSION}-linux-x86_64.tar.xz --directory /opt \
    && ln -s /opt/ldc2-${LDC_VERSION}-linux-x86_64/bin/ldc2 /usr/bin/ldc2 \
    && ln -s /opt/ldc2-${LDC_VERSION}-linux-x86_64/bin/ldmd2 /usr/bin/ldmd2 \
    && ln -s /opt/ldc2-${LDC_VERSION}-linux-x86_64/bin/dub /usr/bin/dub \
    && ln -s /opt/ldc2-${LDC_VERSION}-linux-x86_64/bin/ldc-build-plugin /usr/bin/ldc-build-plugin \
    && ln -s /opt/ldc2-${LDC_VERSION}-linux-x86_64/bin/ldc-build-runtime /usr/bin/ldc-build-runtime

WORKDIR /src
COPY . .
RUN mkdir -p vendor/sqlite vendor/v8/lib vendor/v8/include

# Download and compile vendor deps (SQLite, QuickJS, JSC, V8)
RUN ldc2 -run build.d --backend=${BACKEND} --force

# Build the selected backend
RUN dub build -c ${BACKEND} -b release 2>&1 \
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
    && rm -rf /var/lib/apt/lists/*

COPY --from=build /src/build/dun /usr/local/bin/dun
COPY --from=build /deps/lib/ /usr/local/lib/

RUN ldconfig

WORKDIR /app

ENTRYPOINT ["/usr/local/bin/dun"]
