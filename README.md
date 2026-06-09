# Kubernetes Monitoring Stack — Grafana + Prometheus + Loki

A production-style monitoring stack deployed on a local Kubernetes cluster using **kind** (Kubernetes in Docker). Everything is configuration-as-code — no manual UI steps required.

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                       kind cluster                           │
│                                                              │
│              ┌────────────┐                                  │
│              │  Grafana    │──► Dashboard                     │
│              │   :3000     │                                  │
│              └──┬─────┬───┘                                  │
│        queries  │     │  queries                             │
│       ┌─────────┘     └──────────┐                           │
│       ▼                          ▼                           │
│  ┌──────────┐             ┌──────────┐                       │
│  │Prometheus │             │   Loki   │                       │
│  │  :9090    │             │  :3100   │                       │
│  └────┬─────┘             └────▲─────┘                       │
│       │                        │ pushes logs (OTLP)          │
│       │ scrapes /metrics  ┌────┴─────┐  tails /var/log/pods  │
│       │                   │   OTel   │◄──────────┐           │
│       │                   │Collector │(DaemonSet)│           │
│       │                   └──────────┘           │           │
│       ▼                                          │           │
│  ┌──────────────┐   stdout/stderr ──► CRI log ───┘           │
│  │ Monte Carlo  │                                            │
│  │  Pi Simulator│  (2 replicas, metrics + logs)              │
│  └──────────────┘                                            │
└──────────────────────────────────────────────────────────────┘
```

## Components

| Component   | Version | Purpose                                  | Access                |
|-------------|---------|------------------------------------------|-----------------------|
| Grafana        | 11.6.0  | Dashboards & visualization               | http://localhost:3000  |
| Prometheus     | 3.4.1   | Metrics collection & storage             | http://localhost:9090  |
| Loki           | 3.5.0   | Log aggregation                          | Internal (ClusterIP)  |
| OTel Collector | 0.127.0 | Log collection agent (DaemonSet, contrib) | Internal              |

## Prerequisites

- **macOS** with Homebrew
- **Docker Desktop** (running)
- ~4 GB RAM available for the cluster

## Quick Start

```bash
# 1. Install prerequisites (Docker, kubectl, kind)
./scripts/00-prerequisites.sh

# 2. Create the kind cluster
./scripts/01-create-cluster.sh

# 3. Deploy the full monitoring stack
./scripts/02-deploy-stack.sh

# 4. Verify everything is working
./scripts/03-verify.sh
```

After deployment:
- **Grafana**: http://localhost:3000 (login: `admin` / `admin`)
- **Prometheus**: `kubectl port-forward svc/prometheus 9090:9090 -n monitoring`

## Project Structure

```
Grafana/
├── kind-cluster.yaml                  # Kind cluster definition with port mappings
├── app/
│   └── simulator.py                   # Monte Carlo Pi estimator (Python source)
├── dashboards/
│   ├── cluster-overview.json          # Infrastructure monitoring dashboard
│   └── monte-carlo-pi.json           # Monte Carlo Pi estimation dashboard
├── manifests/
│   ├── namespace/
│   │   └── namespace.yaml             # monitoring namespace
│   ├── grafana/
│   │   ├── configmap.yaml             # grafana.ini configuration
│   │   ├── dashboard-provisioning.yaml# Dashboard auto-discovery config
│   │   ├── datasource-provisioning.yaml# Prometheus + Loki datasources
│   │   ├── deployment.yaml            # Grafana Deployment
│   │   ├── pvc.yaml                   # Persistent storage
│   │   └── service.yaml               # NodePort service (port 30300→3000)
│   ├── prometheus/
│   │   ├── configmap.yaml             # scrape_configs for self, grafana, loki, k8s
│   │   ├── rbac.yaml                  # ServiceAccount + ClusterRole
│   │   ├── deployment.yaml            # Prometheus Deployment
│   │   ├── pvc.yaml                   # Persistent storage
│   │   └── service.yaml               # ClusterIP service
│   ├── loki/
│   │   ├── configmap.yaml             # Loki server + schema configuration
│   │   ├── deployment.yaml            # Loki Deployment
│   │   ├── pvc.yaml                   # Persistent storage
│   │   └── service.yaml               # ClusterIP service
│   ├── otel-collector/
│   │   ├── configmap.yaml             # Filelog receiver + OTLP exporter to Loki
│   │   ├── rbac.yaml                  # ServiceAccount + ClusterRole
│   │   └── daemonset.yaml             # OTel Collector DaemonSet
│   └── monte-carlo-pi/
│       └── deployment.yaml            # Monte Carlo Pi deployment (mounts app/ via ConfigMap)
└── scripts/
    ├── 00-prerequisites.sh            # Install Docker, kubectl, kind
    ├── 01-create-cluster.sh           # Create kind cluster
    ├── 02-deploy-stack.sh             # Deploy all manifests in order
    ├── 03-verify.sh                   # Health checks & validation
    └── 99-teardown.sh                 # Delete cluster
```

## Design Decisions

### Why kind?
- Runs a full Kubernetes cluster inside Docker containers
- No VM overhead (unlike minikube)
- Supports multi-node clusters, port mappings, and storage
- Widely used in CI/CD for Kubernetes testing

### Why raw manifests instead of Helm charts?
- The assignment explicitly asks to create manifests from scratch
- Demonstrates understanding of each Kubernetes resource type
- No abstraction layer hiding what's actually deployed
- Easier to review and reason about

### Configuration-as-Code
Everything is declarative:
- **Datasources**: Provisioned via ConfigMap → mounted into Grafana's provisioning directory
- **Dashboards**: JSON files loaded via Grafana's file-based provisioning
- **Prometheus scrape targets**: Defined in ConfigMap, with Kubernetes SD for auto-discovery
- **Loki**: Configured via YAML ConfigMap, no manual setup
- **OTel Collector**: Filelog receiver tails pod logs, exports to Loki via OTLP

### Security Considerations
- All containers run as non-root users (`runAsNonRoot: true`)
- Dedicated `fsGroup` for volume permissions
- RBAC with least-privilege: Prometheus and OTel Collector get read-only access to K8s API
- Resource limits set on all containers to prevent runaway usage

### What's NOT automated (manual steps)
- Installing Docker Desktop (requires GUI interaction)
- Starting Docker Desktop (must be running before scripts)
- Changing the Grafana admin password on first login (prompted in UI)

## Dashboards

### Monte Carlo Pi Estimation (home dashboard)

A Monte Carlo simulator throws random darts at a unit circle inscribed in a 2x2 square. The ratio of hits (inside circle) to total throws converges to π/4, giving us an estimate of Pi. The dashboard tells this story in real time:

1. **π Estimate** — current Monte Carlo estimate (should converge to 3.14159...)
2. **True π** — the actual value for reference
3. **Absolute Error** — |estimate − π|, shrinking over time
4. **Hit Rate** — fraction of darts inside the circle (converges to π/4 ≈ 78.54%)
5. **Total Throws / Throws per second** — throughput metrics
6. **π Convergence Over Time** — the estimate approaching true π (with dashed reference line)
7. **Hits vs Misses** — donut chart of cumulative hit/miss counts
8. **Error Over Time** — error magnitude shrinking as more darts are thrown
9. **Hit Rate Over Time** — convergence toward π/4 (with dashed reference line)
10. **Per-Pod π Estimate** — each replica converges independently
11. **Throw Distance Distribution** — histogram of distances from center
12. **Recent Dart Throws** — live structured JSON log stream from Loki

### Cluster Overview

Infrastructure monitoring with Prometheus target health, scrape duration, samples scraped, target status table, and Loki log stream.

## Teardown

```bash
./scripts/99-teardown.sh
```

This deletes the kind cluster and all associated resources. PVCs and data are destroyed.

## Challenges & Reflections

See the [Notion documentation](https://www.notion.so/wayve/Grafana-37703da5d69a80a399dfd076e0eb1dd5) for detailed reflections on the process.
