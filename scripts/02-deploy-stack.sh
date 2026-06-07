#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
MANIFESTS="${PROJECT_DIR}/manifests"
DASHBOARDS="${PROJECT_DIR}/dashboards"

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
NC='\033[0m'
log()  { printf "${GREEN}[+]${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}[!]${NC} %s\n" "$*"; }

printf "${BOLD}=== Deploying Monitoring Stack ===${NC}\n\n"

# 1. Namespace
log "Creating namespace..."
kubectl apply -f "${MANIFESTS}/namespace/"

# 2. Load dashboard JSON into the ConfigMap via kubectl
log "Creating dashboard ConfigMap from JSON files..."
kubectl create configmap grafana-dashboards \
    --from-file="${DASHBOARDS}/" \
    --namespace=monitoring \
    --dry-run=client -o yaml | kubectl apply -f -

# 3. Prometheus (needs RBAC first)
log "Deploying Prometheus..."
kubectl apply -f "${MANIFESTS}/prometheus/rbac.yaml"
kubectl apply -f "${MANIFESTS}/prometheus/configmap.yaml"
kubectl apply -f "${MANIFESTS}/prometheus/pvc.yaml"
kubectl apply -f "${MANIFESTS}/prometheus/deployment.yaml"
kubectl apply -f "${MANIFESTS}/prometheus/service.yaml"

# 4. Loki
log "Deploying Loki..."
kubectl apply -f "${MANIFESTS}/loki/"

# 5. OpenTelemetry Collector (log shipper)
log "Deploying OpenTelemetry Collector..."
kubectl apply -f "${MANIFESTS}/otel-collector/rbac.yaml"
kubectl apply -f "${MANIFESTS}/otel-collector/configmap.yaml"
kubectl apply -f "${MANIFESTS}/otel-collector/daemonset.yaml"

# 6. Grafana (depends on datasources being reachable)
log "Deploying Grafana..."
kubectl apply -f "${MANIFESTS}/grafana/"

# 7. Wait for rollouts
printf "\n${BOLD}Waiting for deployments to become ready...${NC}\n"
kubectl rollout status deployment/prometheus  -n monitoring --timeout=180s
kubectl rollout status deployment/loki        -n monitoring --timeout=180s
kubectl rollout status deployment/grafana     -n monitoring --timeout=180s
kubectl rollout status daemonset/otel-collector -n monitoring --timeout=180s

printf "\n${BOLD}=== Stack Status ===${NC}\n"
kubectl get pods -n monitoring -o wide

printf "\n${GREEN}=== Deployment Complete ===${NC}\n"
printf "Grafana:    http://localhost:3000  (admin/admin)\n"
printf "Prometheus: http://localhost:9090  (via port-forward or NodePort)\n\n"
printf "To port-forward Prometheus:\n"
printf "  kubectl port-forward svc/prometheus 9090:9090 -n monitoring\n\n"
