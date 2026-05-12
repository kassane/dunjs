# DunJS Alpine Container — hardened, multi-backend
# Usage:
#   docker build --build-arg BACKEND=quickjs -t dunjs:quickjs .
#   docker build --build-arg BACKEND=jsc -t dunjs:jsc .
#   docker build --build-arg BACKEND=v8 -t dunjs:v8 .
#   docker run --rm dunjs:quickjs run script.js
#   docker run --rm dunjs:quickjs eval "1+1"

# ─── Stage 1: Build ───────────────────────────────────────────
FROM alpine:3.20 AS build

ARG BACKEND=quickjs
ARG LDC_VERSION=1.42.0

RUN apk add --no-cache \
    ca-certificates curl xz gcc g++ cmake make pkgconf git bash \
    libxml2-dev openssl-dev musl-dev linux-headers \
    gcompat libstdc++

# Install LDC via ldcup (same as CI)
RUN curl -sSf https://raw.githubusercontent.com/kassane/ldcup/main/scripts/install.sh | sh
ENV PATH="/root/.ldcup/bin:${PATH}"
RUN ldcup install ldc2-${LDC_VERSION}

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
    && ldd build/dun 2>/dev/null | grep "=> /" | awk '{print $3}' | while read lib; do \
      [ -f "$lib" ] && cp -aL "$lib" /deps/lib/ 2>/dev/null || true; \
    done \
    && ls -la /deps/lib/ 2>/dev/null || true

# ─── Stage 2: Alpine runtime ─────────────────────────────────
FROM alpine:3.20

ARG BACKEND=quickjs

LABEL org.opencontainers.image.title="DunJS" \
      org.opencontainers.image.description="Secure JavaScript/TypeScript runtime (${BACKEND} backend)" \
      org.opencontainers.image.url="https://github.com/kassane/dunjs" \
      org.opencontainers.image.source="https://github.com/kassane/dunjs"

RUN apk add --no-cache gcompat libstdc++ libgcc

COPY --from=build /src/build/dun /usr/local/bin/dun
COPY --from=build /deps/lib/ /usr/local/lib/

ENV LD_LIBRARY_PATH="/usr/local/lib"

WORKDIR /app

ENTRYPOINT ["/usr/local/bin/dun"]
