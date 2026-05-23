#!/bin/bash
# Real-world HTTP benchmark using wrk
# Compares: Node.js, Deno, Bun, DunJS (QuickJS/JSC/V8)
#
# Usage:
#   bash tests/benchmarks/http_bench/run.sh              # All runtimes
#   bash tests/benchmarks/http_bench/run.sh node bun      # Specific runtimes
#   WRK_DURATION=30s WRK_THREADS=4 WRK_CONNS=256 bash tests/benchmarks/http_bench/run.sh
#
# Endpoints tested:
#   /plaintext  — minimal response (throughput ceiling)
#   /json       — JSON serialization
#   /echo       — request parsing + JSON response
#   /compute    — CPU-bound fibonacci + JSON response

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR/../../.."

# wrk parameters (tunable via env)
DURATION="${WRK_DURATION:-10s}"
THREADS="${WRK_THREADS:-2}"
CONNECTIONS="${WRK_CONNS:-64}"
BASE_PORT=9100

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

command -v wrk >/dev/null 2>&1 || { echo "ERROR: wrk not found. Install: apt-get install wrk"; exit 1; }

ENDPOINTS=("plaintext" "json" "echo" "compute")

# Result storage: runtime -> endpoint -> req/s
declare -A RESULTS
declare -A LATENCY_AVG
declare -A LATENCY_P99
RUNTIME_ORDER=()

# ── Helpers ──────────────────────────────────────────────────────────

wait_for_ready() {
    local port=$1 timeout=10 elapsed=0
    while ! curl -s "http://127.0.0.1:${port}/" >/dev/null 2>&1; do
        sleep 0.1
        elapsed=$((elapsed + 1))
        if [ "$elapsed" -ge "$((timeout * 10))" ]; then
            return 1
        fi
    done
    return 0
}

kill_server() {
    local pid=$1
    if kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null
        wait "$pid" 2>/dev/null || true
    fi
}

run_wrk() {
    local url=$1 label=$2
    local output
    output=$(wrk -t"$THREADS" -c"$CONNECTIONS" -d"$DURATION" --latency "$url" 2>&1)

    local rps avg_lat p99_lat transfer errors
    rps=$(echo "$output" | grep "Requests/sec" | awk '{print $2}')
    avg_lat=$(echo "$output" | grep -E "^\s+Latency" | awk '{print $2}')
    p99_lat=$(echo "$output" | grep "99%" | awk '{print $2}')
    transfer=$(echo "$output" | grep "Transfer/sec" | awk '{print $2}')
    errors=$(echo "$output" | grep -c "Socket errors\|Non-2xx" || true)

    if [ -z "$rps" ]; then
        printf "    %-14s  ${RED}FAIL${NC}\n" "/$label"
        RESULTS["${label}"]="FAIL"
        return
    fi

    local rps_int=${rps%%.*}
    if [ "$errors" -gt 0 ]; then
        local err_detail
        err_detail=$(echo "$output" | grep -E "Socket errors|Non-2xx" | head -1)
        printf "    %-14s  ${YELLOW}%'10d${NC} req/s  avg %-8s  p99 %-8s  %s/s  ${RED}%s${NC}\n" \
            "/$label" "$rps_int" "$avg_lat" "${p99_lat:-N/A}" "$transfer" "$err_detail"
    else
        printf "    %-14s  ${GREEN}%'10d${NC} req/s  avg %-8s  p99 %-8s  %s/s\n" \
            "/$label" "$rps_int" "$avg_lat" "${p99_lat:-N/A}" "$transfer"
    fi
    RESULTS["${label}"]="$rps_int"
    LATENCY_AVG["${label}"]="$avg_lat"
    LATENCY_P99["${label}"]="${p99_lat:-N/A}"
}

bench_runtime() {
    local name=$1 cmd=$2 server_file=$3 port=$4

    printf "\n${CYAN}──── %s ────${NC}\n" "$name"
    RUNTIME_ORDER+=("$name")

    # Start server
    $cmd "$server_file" "$port" >/dev/null 2>&1 &
    local pid=$!

    if ! wait_for_ready "$port"; then
        kill_server "$pid"
        printf "  ${RED}Server failed to start on port ${port}${NC}\n"
        for ep in "${ENDPOINTS[@]}"; do
            RESULTS["${name}|${ep}"]="FAIL"
        done
        return
    fi

    # Warmup: 3s with moderate concurrency
    wrk -t1 -c16 -d3s "http://127.0.0.1:${port}/plaintext" >/dev/null 2>&1

    for ep in "${ENDPOINTS[@]}"; do
        run_wrk "http://127.0.0.1:${port}/${ep}" "${name}|${ep}"
    done

    kill_server "$pid"
    sleep 0.5
}

# ── Main ─────────────────────────────────────────────────────────────

export PATH="/tmp/ldc2-1.42.0-linux-x86_64/bin:$PATH"

echo ""
echo -e "${BOLD}════════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}  Real-World HTTP Benchmark (wrk)${NC}"
echo -e "${BOLD}════════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  Config: ${THREADS} threads, ${CONNECTIONS} connections, ${DURATION} per endpoint"
echo -e "  Endpoints: ${ENDPOINTS[*]}"
echo ""

# Ensure DunJS release binaries exist
build_dun_if_needed() {
    local backend=$1 binname=$2
    if [ ! -f "$PROJECT_DIR/build/$binname" ]; then
        echo -e "  ${YELLOW}Building DunJS ($backend) release...${NC}"
        if (cd "$PROJECT_DIR" && dub build -c "$backend" -b release 2>/dev/null); then
            cp "$PROJECT_DIR/build/dun" "$PROJECT_DIR/build/$binname"
        else
            echo -e "  ${RED}Build failed for $backend${NC}"
            return 1
        fi
    fi
    return 0
}

# Determine which runtimes to test
SELECTED=("$@")
if [ ${#SELECTED[@]} -eq 0 ]; then
    SELECTED=("node" "deno" "bun" "dun_quickjs" "dun_jsc" "dun_v8")
fi

PORT=$BASE_PORT

for rt in "${SELECTED[@]}"; do
    case "$rt" in
        node)
            if command -v node >/dev/null 2>&1; then
                bench_runtime "Node $(node --version)" "node" \
                    "$SCRIPT_DIR/server_node.js" "$PORT"
                PORT=$((PORT + 1))
            else
                echo "SKIP: node not found"
            fi
            ;;
        deno)
            if command -v deno >/dev/null 2>&1; then
                bench_runtime "Deno $(deno --version | head -1 | awk '{print $2}')" \
                    "deno run --allow-net --allow-env" \
                    "$SCRIPT_DIR/server_deno.ts" "$PORT"
                PORT=$((PORT + 1))
            else
                echo "SKIP: deno not found"
            fi
            ;;
        bun)
            if command -v bun >/dev/null 2>&1; then
                bench_runtime "Bun $(bun --version)" "bun run" \
                    "$SCRIPT_DIR/server_bun.js" "$PORT"
                PORT=$((PORT + 1))
            else
                echo "SKIP: bun not found"
            fi
            ;;
        dun_quickjs|dun-quickjs|quickjs)
            if build_dun_if_needed quickjs dun-quickjs; then
                bench_runtime "DunJS QuickJS" "$PROJECT_DIR/build/dun-quickjs run --allow-net" \
                    "$SCRIPT_DIR/server_dun.js" "$PORT"
                PORT=$((PORT + 1))
            fi
            ;;
        dun_jsc|dun-jsc|jsc)
            if build_dun_if_needed jsc dun-jsc; then
                bench_runtime "DunJS JSC" "$PROJECT_DIR/build/dun-jsc run --allow-net" \
                    "$SCRIPT_DIR/server_dun.js" "$PORT"
                PORT=$((PORT + 1))
            fi
            ;;
        dun_v8|dun-v8|v8)
            if build_dun_if_needed v8 dun-v8; then
                bench_runtime "DunJS V8" "$PROJECT_DIR/build/dun-v8 run --allow-net" \
                    "$SCRIPT_DIR/server_dun.js" "$PORT"
                PORT=$((PORT + 1))
            fi
            ;;
        *)
            echo "Unknown runtime: $rt (available: node, deno, bun, dun_quickjs, dun_jsc, dun_v8)"
            ;;
    esac
done

# ── Summary Table ────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}════════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}  Summary: Requests/sec by Endpoint${NC}"
echo -e "${BOLD}════════════════════════════════════════════════════════════════${NC}"
echo ""

# Header
printf "  ${BOLD}%-22s${NC}" "Runtime"
for ep in "${ENDPOINTS[@]}"; do
    printf "  %12s" "$ep"
done
echo ""
printf "  %-22s" "──────────────────────"
for ep in "${ENDPOINTS[@]}"; do
    printf "  %12s" "──────────"
done
echo ""

# Data rows
for rt in "${RUNTIME_ORDER[@]}"; do
    printf "  %-22s" "$rt"
    for ep in "${ENDPOINTS[@]}"; do
        val="${RESULTS["${rt}|${ep}"]:-N/A}"
        if [ "$val" = "FAIL" ]; then
            printf "  ${RED}%12s${NC}" "FAIL"
        elif [ "$val" != "N/A" ]; then
            printf "  %'12d" "$val"
        else
            printf "  %12s" "N/A"
        fi
    done
    echo ""
done

# ── Latency Table ────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}  Latency: avg / p99 (plaintext endpoint)${NC}"
echo ""
printf "  ${BOLD}%-22s${NC}  %12s  %12s\n" "Runtime" "avg" "p99"
printf "  %-22s  %12s  %12s\n" "──────────────────────" "──────────" "──────────"

for rt in "${RUNTIME_ORDER[@]}"; do
    avg="${LATENCY_AVG["${rt}|plaintext"]:-N/A}"
    p99="${LATENCY_P99["${rt}|plaintext"]:-N/A}"
    printf "  %-22s  %12s  %12s\n" "$rt" "$avg" "$p99"
done

echo ""
echo "Done."
