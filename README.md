# Kubernetes Monitoring Stack — Grafana + Prometheus + Loki

A production-style monitoring stack deployed on a local Kubernetes cluster using **kind** (Kubernetes in Docker). Everything is configuration-as-code — no manual UI steps required.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    kind cluster                         │
│                                                         │
│  ┌──────────┐   scrapes    ┌────────────┐              │
│  │Prometheus │◄────────────│  Grafana    │──► Dashboard │
│  │  :9090    │  metrics    │   :3000     │              │
│  └────┬─────┘             └──────┬──────┘              │
│       │                          │                      │
│       │ scrapes pods             │ queries              │
│       ▼                          ▼                      │
│  ┌──────────┐             ┌──────────┐                 │
│  │  Pods    │             │   Loki   │                 │
│  │ (targets)│             │  :3100   │                 │
│  └──────────┘             └────┬─────┘                 │
│                                │                        │
│                           ┌────┴─────┐                 │
│                           │ Promtail │ (DaemonSet)     │
│                           │ collects │                 │
│                           │ pod logs │                 │
│                           └──────────┘                 │
└─────────────────────────────────────────────────────────┘
```

## Components

| Component   | Version | Purpose                                  | Access                |
|-------------|---------|------------------------------------------|-----------------------|
| Grafana     | 11.6.0  | Dashboards & visualization               | http://localhost:3000  |
| Prometheus  | 3.4.1   | Metrics collection & storage             | http://localhost:9090  |
| Loki        | 3.5.0   | Log aggregation                          | Internal (ClusterIP)  |
| Promtail    | 3.5.0   | Log shipping agent (DaemonSet)           | Internal              |

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
├── dashboards/
│   └── cluster-overview.json          # Pre-provisioned Grafana dashboard
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
│   ├── promtail/
│   │   ├── configmap.yaml             # Static file discovery + label extraction
│   │   ├── rbac.yaml                  # ServiceAccount + ClusterRole
│   │   └── daemonset.yaml             # Promtail DaemonSet
│   └── dummy-app/
│       └── deployment.yaml            # Test workload (2 replicas, logs + metrics)
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
- **Promtail**: Auto-discovers pod logs via Kubernetes SD relabeling

### Security Considerations
- All containers run as non-root users (`runAsNonRoot: true`)
- Dedicated `fsGroup` for volume permissions
- RBAC with least-privilege: Prometheus and Promtail get read-only access to K8s API
- Resource limits set on all containers to prevent runaway usage

### What's NOT automated (manual steps)
- Installing Docker Desktop (requires GUI interaction)
- Starting Docker Desktop (must be running before scripts)
- Changing the Grafana admin password on first login (prompted in UI)

## Testing the Dashboard

Once deployed, the "Cluster Overview" dashboard shows:
1. **Targets Up/Down** — stat panels showing Prometheus target health
2. **Scrape Duration by Job** — time series of how long each scrape takes
3. **Samples Scraped** — stacked bar chart of samples per scrape job
4. **Target Status** — table with color-coded UP/DOWN per target
5. **Recent Logs** — live Loki log stream from the monitoring namespace

## Teardown

```bash
./scripts/99-teardown.sh
```

This deletes the kind cluster and all associated resources. PVCs and data are destroyed.

## Challenges & Reflections

See the [Notion documentation](https://www.notion.so/wayve/Grafana-37703da5d69a80a399dfd076e0eb1dd5) for detailed reflections on the process.
