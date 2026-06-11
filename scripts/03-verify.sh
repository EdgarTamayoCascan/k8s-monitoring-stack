#!/usr/bin/env bash
set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

pass() { printf "${GREEN}[PASS]${NC} %s\n" "$*"; }
fail() { printf "${RED}[FAIL]${NC} %s\n" "$*"; FAILURES=$((FAILURES + 1)); }

FAILURES=0

printf "${BOLD}=== Monitoring Stack Verification ===${NC}\n\n"

# 1. Check all pods are running
printf "${BOLD}--- Pod Status ---${NC}\n"
PODS=$(kubectl get pods -n monitoring --no-headers 2>/dev/null)
if [ -z "$PODS" ]; then
    fail "No pods found in monitoring namespace"
else
    echo "$PODS"
    NOT_RUNNING=$(echo "$PODS" | grep -cv "Running" || true)
    if [ "$NOT_RUNNING" -eq 0 ]; then
        pass "All pods are running"
    else
        fail "${NOT_RUNNING} pod(s) not in Running state"
    fi
fi

printf "\n${BOLD}--- Service Endpoints ---${NC}\n"
kubectl get svc -n monitoring

# 2. Grafana health check
printf "\n${BOLD}--- Grafana Health ---${NC}\n"
GRAFANA_HEALTH=$(kubectl exec -n monitoring deploy/grafana -- \
    wget -qO- http://localhost:3000/api/health 2>/dev/null || echo "unreachable")
if echo "$GRAFANA_HEALTH" | grep -q '"database": "ok"'; then
    pass "Grafana API is healthy"
else
    fail "Grafana API health check failed: ${GRAFANA_HEALTH}"
fi

# 3. Prometheus health check
printf "\n${BOLD}--- Prometheus Health ---${NC}\n"
PROM_HEALTH=$(kubectl exec -n monitoring deploy/prometheus -- \
    wget -qO- http://localhost:9090/-/healthy 2>/dev/null || echo "unreachable")
if echo "$PROM_HEALTH" | grep -qi "healthy"; then
    pass "Prometheus is healthy"
else
    fail "Prometheus health check failed: ${PROM_HEALTH}"
fi

# 4. Loki readiness
printf "\n${BOLD}--- Loki Readiness ---${NC}\n"
LOKI_READY=$(kubectl exec -n monitoring deploy/loki -- \
    wget -qO- http://localhost:3100/ready 2>/dev/null || echo "unreachable")
if echo "$LOKI_READY" | grep -qi "ready"; then
    pass "Loki is ready"
else
    fail "Loki readiness check failed: ${LOKI_READY}"
fi

# 5. Grafana datasources
printf "\n${BOLD}--- Grafana Datasources ---${NC}\n"
DATASOURCES=$(kubectl exec -n monitoring deploy/grafana -- \
    wget -qO- --header="Authorization: Basic YWRtaW46YWRtaW4=" \
    http://localhost:3000/api/datasources 2>/dev/null || echo "[]")
echo "$DATASOURCES" | python3 -m json.tool 2>/dev/null || echo "$DATASOURCES"

DS_COUNT=$(echo "$DATASOURCES" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")
if [ "$DS_COUNT" -ge 2 ]; then
    pass "Found ${DS_COUNT} datasources configured"
else
    fail "Expected at least 2 datasources, found ${DS_COUNT}"
fi

# 6. Grafana dashboards
printf "\n${BOLD}--- Grafana Dashboards ---${NC}\n"
DASHBOARDS=$(kubectl exec -n monitoring deploy/grafana -- \
    wget -qO- --header="Authorization: Basic YWRtaW46YWRtaW4=" \
    http://localhost:3000/api/search 2>/dev/null || echo "[]")
DASH_COUNT=$(echo "$DASHBOARDS" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")
if [ "$DASH_COUNT" -ge 1 ]; then
    pass "Found ${DASH_COUNT} dashboard(s) provisioned"
else
    fail "No dashboards found"
fi

# 7. Prometheus targets (Monte Carlo simulator should be UP)
printf "\n${BOLD}--- Prometheus Targets ---${NC}\n"
PROM_TARGETS=$(kubectl exec -n monitoring deploy/prometheus -- \
    wget -qO- http://localhost:9090/api/v1/targets 2>/dev/null || echo "{}")
UP_COUNT=$(echo "$PROM_TARGETS" | python3 -c "
import sys, json
data = json.load(sys.stdin)
targets = data.get('data', {}).get('activeTargets', [])
up = [t for t in targets if t.get('health') == 'up']
print(len(up))
" 2>/dev/null || echo "0")
if [ "$UP_COUNT" -ge 3 ]; then
    pass "Found ${UP_COUNT} Prometheus target(s) UP"
else
    fail "Expected at least 3 UP targets, found ${UP_COUNT}"
fi

# 8. Monte Carlo metrics flowing
printf "\n${BOLD}--- Monte Carlo Metrics ---${NC}\n"
METRIC_VALUE=$(kubectl exec -n monitoring deploy/prometheus -- \
    wget -qO- 'http://localhost:9090/api/v1/query?query=monte_carlo_throws_total' 2>/dev/null || echo "{}")
THROWS=$(echo "$METRIC_VALUE" | python3 -c "
import sys, json
data = json.load(sys.stdin)
results = data.get('data', {}).get('result', [])
total = sum(float(r['value'][1]) for r in results)
print(int(total))
" 2>/dev/null || echo "0")
if [ "$THROWS" -gt 0 ]; then
    pass "Monte Carlo simulator has recorded ${THROWS} throws"
else
    fail "No monte_carlo_throws_total metrics found"
fi

# 9. Loki log ingestion smoke test
printf "\n${BOLD}--- Loki Log Ingestion ---${NC}\n"
if date -u -v-10M +%s >/dev/null 2>&1; then
    LOKI_START=$(date -u -v-10M +%s)000000000
else
    LOKI_START=$(date -u -d '10 minutes ago' +%s)000000000
fi
LOKI_END=$(date -u +%s)000000000
LOKI_LOGS=$(kubectl exec -n monitoring deploy/loki -- \
    wget -qO- --post-data='query={service_name="simulator"}&limit=5' \
    "http://localhost:3100/loki/api/v1/query_range?start=${LOKI_START}&end=${LOKI_END}" 2>/dev/null || echo "{}")
LOG_COUNT=$(echo "$LOKI_LOGS" | python3 -c "
import sys, json
data = json.load(sys.stdin)
streams = data.get('data', {}).get('result', [])
count = sum(len(s.get('values', [])) for s in streams)
print(count)
" 2>/dev/null || echo "0")
if [ "$LOG_COUNT" -gt 0 ]; then
    pass "Loki received ${LOG_COUNT} log line(s) from simulator"
else
    fail "No simulator logs found in Loki"
fi

# 10. External access via kind port mappings (local clusters only)
printf "\n${BOLD}--- External Access ---${NC}\n"
if curl -sf http://localhost:3000/api/health >/dev/null 2>&1; then
    pass "Grafana reachable at http://localhost:3000"
else
    fail "Grafana not reachable at http://localhost:3000"
fi

PROM_EXT=$(curl -sf http://localhost:9090/-/healthy 2>/dev/null || echo "unreachable")
if echo "$PROM_EXT" | grep -qi "healthy"; then
    pass "Prometheus reachable at http://localhost:9090"
else
    fail "Prometheus not reachable at http://localhost:9090"
fi

# Summary
printf "\n${BOLD}=== Summary ===${NC}\n"
if [ "$FAILURES" -eq 0 ]; then
    printf "${GREEN}All checks passed!${NC}\n"
else
    printf "${RED}${FAILURES} check(s) failed.${NC}\n"
    exit 1
fi
