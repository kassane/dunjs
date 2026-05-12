# DunJS Distroless Container — hardened, multi-backend
# Usage:
#   docker build --build-arg BACKEND=quickjs -t dunjs:quickjs .
#   docker build --build-arg BACKEND=jsc -t dunjs:jsc .
#   docker build --build-arg BACKEND=v8 -t dunjs:v8 .
#   docker run --rm dunjs:quickjs run script.js
#   docker run --rm dunjs:quickjs eval "1+1"

# ─── Stage 1: Build ───────────────────────────────────────────
FROM debian:trixie-slim AS build

ARG BACKEND=quickjs
ARG LDC_VERSION=1.42.0

RUN apt-get update -qq \
    && apt-get install -qq --no-install-recommends \
      ca-certificates \
      curl \
      xz-utils \
      gcc \
      g++ \
      cmake \
      make \
      pkg-config \
      git \
      libxml2 \
      libssl-dev \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install LDC
RUN arch="$(dpkg --print-architecture)" \
    && case "${arch}" in \
      amd64) ldc_arch="linux-x86_64" ;; \
      arm64) ldc_arch="linux-aarch64" ;; \
      *) echo "error: unsupported architecture: $arch"; exit 1 ;; \
    esac \
    && curl -fsSL "https://github.com/ldc-developers/ldc/releases/download/v${LDC_VERSION}/ldc2-${LDC_VERSION}-${ldc_arch}.tar.xz" \
      -o /tmp/ldc.tar.xz \
      --retry 5 \
    && tar -xf /tmp/ldc.tar.xz -C /opt/ \
    && rm /tmp/ldc.tar.xz

ENV PATH="/opt/ldc2-${LDC_VERSION}-linux-x86_64/bin:${PATH}"

WORKDIR /src
COPY . .
RUN mkdir -p vendor/sqlite vendor/v8/lib vendor/v8/include

# Build the selected backend
RUN dub build -c ${BACKEND} -b release 2>&1 \
    && strip build/dun \
    && ls -la build/dun

# Collect shared library dependencies (V8/QuickJS are statically linked)
RUN mkdir -p /deps/lib \
    && case "${BACKEND}" in \
      jsc) \
        for lib in vendor/jsc/lib/*.so*; do \
          [ -f "$lib" ] && cp -a "$lib" /deps/lib/; \
        done ;; \
    esac \
    && ldd build/dun | grep "=> /" | awk '{print $3}' | while read lib; do \
      [ -f "$lib" ] && cp -aL "$lib" /deps/lib/ 2>/dev/null || true; \
    done \
    && ls -la /deps/lib/

# ─── Stage 2: Distroless runtime ──────────────────────────────
FROM gcr.io/distroless/cc-debian12

ARG BACKEND=quickjs

LABEL org.opencontainers.image.title="DunJS" \
      org.opencontainers.image.description="Secure JavaScript/TypeScript runtime (${BACKEND} backend)" \
      org.opencontainers.image.url="https://github.com/kassane/dunjs" \
      org.opencontainers.image.source="https://github.com/kassone/dunjs"

COPY --from=build /src/build/dun /usr/local/bin/dun
COPY --from=build /deps/lib/ /usr/local/lib/

ENV LD_LIBRARY_PATH="/usr/local/lib"

WORKDIR /app

ENTRYPOINT ["/usr/local/bin/dun"]
