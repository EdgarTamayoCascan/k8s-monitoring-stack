#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="monitoring-lab"
GREEN='\033[0;32m'
NC='\033[0m'

printf "This will delete the kind cluster '${CLUSTER_NAME}' and all its data.\n"
read -p "Continue? [y/N] " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    kind delete cluster --name "${CLUSTER_NAME}"
    printf "${GREEN}Cluster deleted.${NC}\n"
else
    printf "Aborted.\n"
fi
