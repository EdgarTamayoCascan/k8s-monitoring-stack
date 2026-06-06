#!/usr/bin/env bash
set -euo pipefail

# Install prerequisites for the monitoring stack on macOS.
# Idempotent — skips tools that are already installed.

BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

log()  { printf "${GREEN}[+]${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}[!]${NC} %s\n" "$*"; }

check_and_install() {
    local tool=$1
    local brew_pkg=${2:-$1}
    if command -v "$tool" &>/dev/null; then
        log "$tool is already installed: $(command -v "$tool")"
    else
        warn "$tool not found — installing via Homebrew..."
        brew install "$brew_pkg"
        log "$tool installed successfully"
    fi
}

printf "${BOLD}=== Monitoring Stack Prerequisites ===${NC}\n\n"

if ! command -v brew &>/dev/null; then
    echo "ERROR: Homebrew is required. Install from https://brew.sh"
    exit 1
fi

check_and_install docker   "docker"
check_and_install kubectl  "kubernetes-cli"
check_and_install kind     "kind"

printf "\n${BOLD}Checking Docker daemon...${NC}\n"
if docker info &>/dev/null; then
    log "Docker daemon is running"
else
    warn "Docker daemon is not running. Please start Docker Desktop and re-run this script."
    exit 1
fi

printf "\n${GREEN}All prerequisites are ready.${NC}\n"
