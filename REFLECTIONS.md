# Reflections — Take-Home Exercise

## Process

The exercise asked for Grafana on Kubernetes with data source integration — I chose to go beyond the minimum by wiring a full **metrics + logs** pipeline. The Monte Carlo Pi simulator was a deliberate choice: it gives evaluators something visually interesting to watch (π converging toward 3.14159) while exercising both Prometheus scraping and Loki log ingestion in a single workload.

Total effort was within the recommended 5-hour cap. Most time went into the OTel Collector log pipeline (getting metadata extraction and Loki OTLP ingestion right) and building the Grafana dashboards.

---

## Challenges

### 1. OTel Collector → Loki log pipeline

The trickiest part was getting pod logs from `/var/log/pods/` into Loki with usable labels. CRI log file paths encode namespace, pod name, and container name in a specific format. I used OTel's `filelog` receiver with a `container` parser and a custom regex to extract Kubernetes metadata, then exported via OTLP HTTP to Loki's `/otlp` endpoint (supported natively in Loki 3.x).

**Frustration:** OTel Collector config syntax is verbose and error messages can be opaque. A typo in the regex parser silently drops labels rather than failing loudly.

**What I'd do differently:** For a production Loki setup, I'd evaluate **Promtail** first — it's simpler and Loki-native. OTel is the better long-term bet for a unified observability agent, but the config complexity is real.

### 2. Grafana dashboard datasource UIDs

Provisioned dashboards reference `${DS_PROMETHEUS}` and `${DS_LOKI}` template variables. These resolve at dashboard load time by matching datasource type. If datasource provisioning fails silently, panels show "No data." The verify script checks datasource count via the Grafana API to catch this.

### 3. kind port mappings

kind's `extraPortMappings` only work when a Kubernetes Service exposes the matching **nodePort** on the control-plane node. Grafana was straightforward (NodePort 30300). Prometheus initially had a ClusterIP Service while `kind-cluster.yaml` mapped port 30900 — a mismatch that made `localhost:9090` unreachable. Fixed by converting Prometheus to NodePort 30900.

### 4. PVC permissions

Prometheus and Loki run as non-root users but need write access to their data directories. Init containers with `busybox` chown the PVC mount points before the main container starts. This is a common pattern but easy to forget.

### 5. Prometheus kubelet scraping

Scraping kubelet metrics requires HTTPS with the service account token and `insecure_skip_verify: true` on kind clusters. This works locally but would need proper kubelet certificate configuration in production.

---

## What Went Well

- **Fully automated deploy** — four numbered scripts from zero to verified stack
- **Zero manual UI steps** — datasources, dashboards, and config all provisioned via ConfigMaps
- **Automated verification** — `03-verify.sh` checks pods, health endpoints, datasources, and dashboards
- **Security basics** — non-root containers, RBAC, resource limits throughout
- **Memorable demo** — Monte Carlo Pi tells a story that makes the interview presentation easy

---

## What I Would Improve

| Area | Current | Production target |
|---|---|---|
| High availability | Single replica everything | StatefulSets, anti-affinity, multi-AZ |
| Secrets | Plaintext in ConfigMaps | External Secrets Operator + Vault |
| Alerting | None | Alertmanager + PagerDuty/Slack routes |
| Storage | Local filesystem PVCs | S3/GCS object storage backends |
| CI/CD | Manual scripts | GitHub Actions with kind + verify |
| Log shipping | OTel filelog | Evaluate Promtail; add trace support |
| Auth | admin/admin + anonymous | OAuth/SAML, RBAC in Grafana |
| Testing | Shell verify script | Add Loki log ingestion smoke test, Prometheus target UP assertions |
