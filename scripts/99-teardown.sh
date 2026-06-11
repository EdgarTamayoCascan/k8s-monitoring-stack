#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="monitoring-lab"
GREEN='\033[0;32m'
NC='\033[0m'

if ! kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
    printf "Cluster '${CLUSTER_NAME}' does not exist — nothing to delete.\n"
    exit 0
fi

if [ "${FORCE:-}" = "1" ] || [ ! -t 0 ]; then
    kind delete cluster --name "${CLUSTER_NAME}"
    printf "${GREEN}Cluster deleted.${NC}\n"
    exit 0
fi

printf "This will delete the kind cluster '${CLUSTER_NAME}' and all its data.\n"
read -r -p "Continue? [y/N] " REPLY
if [[ $REPLY =~ ^[Yy]$ ]]; then
    kind delete cluster --name "${CLUSTER_NAME}"
    printf "${GREEN}Cluster deleted.${NC}\n"
else
    printf "Aborted.\n"
fi
