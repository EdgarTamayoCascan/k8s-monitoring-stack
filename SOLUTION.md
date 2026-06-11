# Solution Overview — Isomorphic Labs Take-Home

**Author:** Edgar Tamayo Cascan  
**Stack:** Grafana 11.6 + Prometheus 3.4 + Loki 3.5 + OpenTelemetry Collector  
**Runtime:** kind (Kubernetes in Docker) on macOS

---

## What I Built

A local observability stack on Kubernetes that demonstrates **metrics** (Prometheus), **logs** (Loki), and **visualization** (Grafana) — all deployed from raw manifests with zero manual UI configuration.

A custom **Monte Carlo Pi simulator** serves as the demo workload: it exposes Prometheus metrics on `:8080/metrics`, emits structured JSON logs to stdout, and runs as a 2-replica Deployment so dashboards can show per-pod convergence.

**Access after deploy:**
- Grafana: http://localhost:3000 (`admin` / `admin`)
- Prometheus: http://localhost:9090

---

## Architecture

```
Monte Carlo Pi (2 replicas)
    ├── metrics ──► Prometheus ──► Grafana dashboards
    └── stdout  ──► CRI logs ──► OTel Collector (DaemonSet) ──► Loki ──► Grafana log panels
```

Grafana datasources and dashboards are provisioned via ConfigMaps at startup. Prometheus uses Kubernetes service discovery to auto-scrape pods annotated with `prometheus.io/scrape: "true"`.

---

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Local K8s | **kind** | Fast, CI-friendly, explicit host port mappings, no VM overhead |
| Manifests | **Raw YAML** (no pre-made Helm charts) | Assignment requirement; shows understanding of each resource |
| Log pipeline | **OTel Collector** → Loki (OTLP) | Vendor-neutral, CNCF-standard; one agent for logs/metrics/traces |
| Demo workload | **Monte Carlo Pi** | Tells a visual story (π converging); exercises both metrics and logs |
| Grafana access | **NodePort 30300** via kind port mapping | Evaluators can open http://localhost:3000 without port-forward |
| Prometheus access | **NodePort 30900** via kind port mapping | Same rationale — direct browser access for target inspection |
| Storage | **PVCs on kind local-path** | Persists data across pod restarts within a cluster lifetime |
| Auth | **admin/admin + anonymous Viewer** | Acceptable for local demo; would use OAuth/SSO in production |

---

## Assumptions

- Single-node kind cluster is sufficient for evaluation (no HA required)
- ~4 GB RAM available on the host machine
- Docker (Desktop or Colima) is running before deploy scripts execute
- Evaluator has macOS + Homebrew, or can adapt scripts for Linux
- Default Grafana credentials are acceptable for a take-home (not production)

---

## Limitations (Local Dev Only)

- **Single replica** for Grafana, Prometheus, and Loki — no high availability
- **`Recreate` deploy strategy** for stateful components — brief downtime on config changes
- **Filesystem storage** — data lost when the kind cluster is deleted
- **No alerting** — Alertmanager not included
- **Credentials in ConfigMaps** — `admin/admin` in plaintext (not suitable for production)
- **Anonymous auth enabled** — convenient for demo, would disable in production
- **`insecure_skip_verify: true`** on kubelet scraping — common in local clusters without proper kubelet certs
- **No NetworkPolicies** — all pods in `monitoring` namespace can talk freely

---

## How to Evaluate

```bash
./scripts/00-prerequisites.sh   # Install Docker, kubectl, kind
./scripts/01-create-cluster.sh    # Create kind cluster
./scripts/02-deploy-stack.sh      # Deploy full stack
./scripts/03-verify.sh            # Automated health checks
```

Open http://localhost:3000 → **Monte Carlo Pi Estimation** dashboard (set as home dashboard). Watch π converge and JSON dart-throw logs stream in the Loki panel.

Teardown: `./scripts/99-teardown.sh`
