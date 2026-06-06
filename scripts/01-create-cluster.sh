#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CLUSTER_NAME="monitoring-lab"

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'
log()  { printf "${GREEN}[+]${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}[!]${NC} %s\n" "$*"; }

if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
    warn "Cluster '${CLUSTER_NAME}' already exists — skipping creation"
    kind export kubeconfig --name "${CLUSTER_NAME}"
else
    log "Creating kind cluster '${CLUSTER_NAME}'..."
    kind create cluster --config "${PROJECT_DIR}/kind-cluster.yaml"
fi

log "Waiting for cluster to be ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=120s

log "Cluster info:"
kubectl cluster-info
printf "\n${GREEN}Cluster '${CLUSTER_NAME}' is ready.${NC}\n"
