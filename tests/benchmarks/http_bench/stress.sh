#!/bin/bash
# Real-world HTTP stress benchmark — microservice patterns
# Compares: Node.js, Bun, DunJS (QuickJS/JSC/V8)
#
# Usage:
#   bash tests/benchmarks/http_bench/stress.sh              # All runtimes
#   bash tests/benchmarks/http_bench/stress.sh node bun      # Specific runtimes
#   WRK_DURATION=30s WRK_THREADS=4 WRK_CONNS=256 bash tests/benchmarks/http_bench/stress.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR/../../.."

DURATION="${WRK_DURATION:-10s}"
THREADS="${WRK_THREADS:-2}"
CONNECTIONS="${WRK_CONNS:-128}"
BASE_PORT=9300

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

command -v wrk >/dev/null 2>&1 || { echo "ERROR: wrk not found"; exit 1; }

ENDPOINTS=("plaintext" "json" "api/users" "api/user/42" "compute" "compute/heavy" "transaction" "middleware" "echo")

declare -A RESULTS
declare -A LATENCY_AVG
declare -A LATENCY_P99
RUNTIME_ORDER=()

wait_for_ready() {
    local port=$1 elapsed=0
    while ! curl -s "http://127.0.0.1:${port}/" >/dev/null 2>&1; do
        sleep 0.1; elapsed=$((elapsed + 1))
        if [ "$elapsed" -ge 100 ]; then return 1; fi
    done
}

kill_server() {
    local pid=$1
    if kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null || true
    fi
}

run_wrk() {
    local url=$1 label=$2
    local output rps avg_lat p99_lat transfer errors
    output=$(wrk -t"$THREADS" -c"$CONNECTIONS" -d"$DURATION" --latency "$url" 2>&1)
    rps=$(echo "$output" | grep "Requests/sec" | awk '{print $2}')
    avg_lat=$(echo "$output" | grep -E "^\s+Latency" | awk '{print $2}')
    p99_lat=$(echo "$output" | grep "99%" | awk '{print $2}')
    errors=$(echo "$output" | grep -c "Socket errors\|Non-2xx" || true)

    if [ -z "$rps" ]; then
        printf "    %-18s  ${RED}FAIL${NC}\n" "/$label"
        RESULTS["${label}"]="FAIL"
        return
    fi

    local rps_int=${rps%%.*}
    if [ "$errors" -gt 0 ]; then
        printf "    %-18s  ${YELLOW}%'10d${NC} req/s  avg %-8s  p99 %-8s\n" \
            "/${label}" "$rps_int" "$avg_lat" "${p99_lat:-N/A}"
    else
        printf "    %-18s  ${GREEN}%'10d${NC} req/s  avg %-8s  p99 %-8s\n" \
            "/${label}" "$rps_int" "$avg_lat" "${p99_lat:-N/A}"
    fi
    RESULTS["${label}"]="$rps_int"
    LATENCY_AVG["${label}"]="$avg_lat"
    LATENCY_P99["${label}"]="${p99_lat:-N/A}"
}

bench_runtime() {
    local name=$1 cmd=$2 server_file=$3 port=$4
    printf "\n${CYAN}──── %s ────${NC}\n" "$name"
    RUNTIME_ORDER+=("$name")

    $cmd "$server_file" "$port" >/dev/null 2>&1 &
    local pid=$!

    if ! wait_for_ready "$port"; then
        kill_server "$pid"
        printf "  ${RED}Server failed to start${NC}\n"
        for ep in "${ENDPOINTS[@]}"; do RESULTS["${name}|${ep}"]="FAIL"; done
        return
    fi

    # Warmup
    wrk -t1 -c16 -d3s "http://127.0.0.1:${port}/plaintext" >/dev/null 2>&1

    for ep in "${ENDPOINTS[@]}"; do
        run_wrk "http://127.0.0.1:${port}/${ep}" "${name}|${ep}"
    done

    kill_server "$pid"
    sleep 0.5
}

export PATH="/tmp/ldc2-1.42.0-linux-x86_64/bin:$PATH"

echo ""
echo -e "${BOLD}════════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}  HTTP Stress Benchmark — Microservice Patterns${NC}"
echo -e "${BOLD}════════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  Config: ${THREADS} threads, ${CONNECTIONS} connections, ${DURATION} per endpoint"
echo -e "  Endpoints: ${#ENDPOINTS[@]} (plaintext, json, users API, compute, transaction, middleware, echo)"
echo ""

build_dun_if_needed() {
    local backend=$1 binname=$2
    if [ ! -f "$PROJECT_DIR/build/$binname" ]; then
        echo -e "  ${YELLOW}Building DunJS ($backend) release...${NC}"
        if (cd "$PROJECT_DIR" && dub build -c "$backend" -b release 2>/dev/null); then
            cp "$PROJECT_DIR/build/dun" "$PROJECT_DIR/build/$binname"
        else
            echo -e "  ${RED}Build failed for $backend${NC}"; return 1
        fi
    fi
}

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
                    "$SCRIPT_DIR/server_stress_node.js" "$PORT"
                PORT=$((PORT + 1))
            fi ;;
        deno)
            if command -v deno >/dev/null 2>&1; then
                bench_runtime "Deno $(deno --version | head -1 | awk '{print $2}')" \
                    "deno run --allow-net --allow-env" \
                    "$SCRIPT_DIR/server_stress_deno.ts" "$PORT"
                PORT=$((PORT + 1))
            fi ;;
        bun)
            if command -v bun >/dev/null 2>&1; then
                bench_runtime "Bun $(bun --version)" "bun run" \
                    "$SCRIPT_DIR/server_stress_bun.js" "$PORT"
                PORT=$((PORT + 1))
            fi ;;
        dun_quickjs|quickjs)
            if build_dun_if_needed quickjs dun-quickjs; then
                bench_runtime "DunJS QuickJS" "$PROJECT_DIR/build/dun-quickjs run" \
                    "$SCRIPT_DIR/server_stress.js" "$PORT"
                PORT=$((PORT + 1))
            fi ;;
        dun_jsc|jsc)
            if build_dun_if_needed jsc dun-jsc; then
                bench_runtime "DunJS JSC" "$PROJECT_DIR/build/dun-jsc run" \
                    "$SCRIPT_DIR/server_stress.js" "$PORT"
                PORT=$((PORT + 1))
            fi ;;
        dun_v8|v8)
            if build_dun_if_needed v8 dun-v8; then
                bench_runtime "DunJS V8" "$PROJECT_DIR/build/dun-v8 run" \
                    "$SCRIPT_DIR/server_stress.js" "$PORT"
                PORT=$((PORT + 1))
            fi ;;
        *) echo "Unknown: $rt" ;;
    esac
done

# Summary Table
echo ""
echo -e "${BOLD}════════════════════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}  Summary: Requests/sec by Endpoint${NC}"
echo -e "${BOLD}════════════════════════════════════════════════════════════════════════════${NC}"
echo ""

printf "  ${BOLD}%-20s${NC}" "Runtime"
for ep in "${ENDPOINTS[@]}"; do
    label="${ep}"
    [ ${#label} -gt 14 ] && label="${label:0:14}"
    printf "  %14s" "$label"
done
echo ""
printf "  %-20s" "────────────────────"
for ep in "${ENDPOINTS[@]}"; do printf "  %14s" "──────────────"; done
echo ""

for rt in "${RUNTIME_ORDER[@]}"; do
    printf "  %-20s" "$rt"
    for ep in "${ENDPOINTS[@]}"; do
        val="${RESULTS["${rt}|${ep}"]:-N/A}"
        if [ "$val" = "FAIL" ]; then
            printf "  ${RED}%14s${NC}" "FAIL"
        elif [ "$val" != "N/A" ]; then
            printf "  %'14d" "$val"
        else
            printf "  %14s" "N/A"
        fi
    done
    echo ""
done

echo ""
echo "Done."
