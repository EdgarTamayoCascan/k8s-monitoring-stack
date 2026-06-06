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

# Summary
printf "\n${BOLD}=== Summary ===${NC}\n"
if [ "$FAILURES" -eq 0 ]; then
    printf "${GREEN}All checks passed!${NC}\n"
else
    printf "${RED}${FAILURES} check(s) failed.${NC}\n"
    exit 1
fi
