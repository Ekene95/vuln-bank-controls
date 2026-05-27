# VulnBank — Phase 2: Runtime Security

Phase 1 built the perimeter: Kong controls what gets in, NetworkPolicies
control what can talk to what. Phase 2 builds the interior — controls that
watch and enforce what happens *inside* the cluster once something is running.

```
Phase 1 (complete)          Phase 2 (this module)
──────────────────          ─────────────────────────────────────────────
Kong API Gateway        →   Kyverno: enforce pod security at admission time
NetworkPolicies         →   Falco:   detect suspicious behaviour at runtime
cert-manager TLS        →   Loki + Grafana: make everything visible
Namespace isolation
```

---

## What This Module Adds

| Tool | Layer | What It Does |
|---|---|---|
| **Kyverno** | Admission | Blocks non-compliant pods before they start |
| **Falco** | Runtime | Detects suspicious syscalls inside running containers |
| **Loki + Grafana** | Observability | Aggregates Falco alerts and Kong logs into dashboards |

---

## Directory Structure

```
phase-2/
├── kyverno/
│   ├── install.sh                          Install Kyverno via Helm
│   └── policies/
│       ├── 01-deny-root-pods.yaml          Block containers running as root
│       ├── 02-deny-privileged-containers   Block hostNetwork/PID/IPC/hostPath
│       ├── 04-require-resource-limits      Require CPU/memory/storage limits
│       ├── 05-disable-automount-sa-token   Disable K8s API token mounting
│       ├── 05-require-readonly-rootfs      Require read-only root filesystem
│       ├── 06-deny-capability-escalation   Drop all Linux capabilities
│       ├── 07-restrict-image-registries    Allowlist approved image sources
│       └── 08-generate-default-deny-netpol Auto-create NetworkPolicy on new namespaces
│
├── falco/
│   ├── install.sh                          Install Falco via Helm
│   ├── falco-values.yaml                   Helm values (ebpf, JSON output, custom rules)
│   ├── falco-custom-rules.yaml             VulnBank-specific detection rules
│   └── attack-exercises.md                 6 exercises to trigger and observe each rule
│
└── observability/
    ├── install.sh                          Install Loki + Grafana via Helm
    ├── observability-values.yaml           Helm values (Promtail scrape config)
    └── grafana-dashboard-configmap.yaml    Pre-built security monitoring dashboard
```

---

## Prerequisites

Phase 1 must be fully deployed before starting Phase 2:
- All four namespaces exist with labels
- VulnBank app and PostgreSQL running
- Kong gateway operational
- NetworkPolicies applied

Verify Phase 1 is healthy:
```bash
kubectl get pods -n vuln-bank
kubectl get pods -n vuln-bank-db
kubectl get pods -n kong
```

---

## Step 1 — Kyverno

### Install

```bash
cd phase-2/kyverno
bash install.sh

# Verify Kyverno is running
kubectl get pods -n kyverno
```

### Understanding Audit vs Enforce

Every policy has a `validationFailureAction` field:

| Mode | Behaviour | When to use |
|---|---|---|
| `Audit` | Logs violations, allows pods | Default — use during burn-in to see what fires |
| `Enforce` | Blocks non-compliant pods | After confirming no false positives |

**Policy 02 (deny-privileged-containers) is the only one set to `Enforce` immediately.**
No legitimate workload in this stack uses privileged mode, hostNetwork, hostPID,
hostIPC, or hostPath mounts. It is safe to block from day one.

All other policies start in `Audit`. This mirrors how financial sector teams
roll out admission controls — you never flip to `Enforce` blindly.

### Apply all policies

```bash
kubectl apply -f policies/

# Verify policies are loaded
kubectl get clusterpolicies
```

### Read the audit report

After applying, Kyverno evaluates all running pods against every policy
and writes the results to PolicyReport resources:

```bash
# Summary across all namespaces
kubectl get policyreport -A

# Detailed violations for the vuln-bank namespace
kubectl describe policyreport -n vuln-bank

# All FAIL results in a readable format
kubectl get policyreport -n vuln-bank -o json \
  | python3 -c "
import sys, json
r = json.load(sys.stdin)
for result in r.get('results', []):
    if result['result'] == 'fail':
        print(f\"FAIL  {result['policy']} / {result['rule']}\")
        print(f\"      {result['message'][:120]}\")
        print()
"
```

### Switching a policy to Enforce

Once you have confirmed a policy produces no false positives against your
running workloads, switch it to Enforce:

```bash
# Edit the policy file: change Audit → Enforce
# Then re-apply
kubectl apply -f policies/01-deny-root-pods.yaml

# Test it fires correctly
kubectl run root-test --image=alpine -n vuln-bank \
  --overrides='{"spec":{"securityContext":{"runAsUser":0}}}' -- sleep 10
# Expected: Error from server: admission webhook denied the request
```

### Generate policy — auto NetworkPolicy on new namespaces

Policy 08 uses Kyverno's `generate` type to automatically create a
default-deny NetworkPolicy whenever a namespace is labelled:

```bash
# Test with a scratch namespace
kubectl create namespace test-isolation
kubectl label namespace test-isolation network-policy=default-deny

# Kyverno creates the NetworkPolicy automatically
kubectl get networkpolicies -n test-isolation
# Expected: default-deny-all created by Kyverno

# Clean up
kubectl delete namespace test-isolation
```

This is Kyverno's `generate` capability — it creates Kubernetes resources
automatically in response to other resource events. OPA Gatekeeper has
no equivalent. It is one of the primary reasons Kyverno was chosen.

---

## Step 2 — Falco

### Install

```bash
cd phase-2/falco
bash install.sh

# Verify Falco DaemonSet is running (one pod per node)
kubectl get pods -n falco

# Watch live alerts
kubectl logs -n falco -l app.kubernetes.io/name=falco -f \
  | grep -v DEBUG \
  | python3 -c "
import sys, json
for line in sys.stdin:
    try:
        a = json.loads(line)
        print(f\"{a['priority']:10} | {a.get('rule','')}\")
        print(f\"           | {a.get('output','')[:120]}\")
        print()
    except:
        print(line.rstrip())
"
```

### Custom rules

The custom rules are loaded via a ConfigMap:

```bash
kubectl apply -f falco-custom-rules.yaml
kubectl rollout restart daemonset/falco -n falco
```

### VulnBank detection rules

| Rule | Priority | Maps to VulnBank Vulnerability |
|---|---|---|
| Shell Spawned in VulnBank Container | CRITICAL | RCE via unrestricted file upload |
| Unexpected Outbound Connection from VulnBank | WARNING | SSRF via `/upload_profile_picture_url` |
| Sensitive File Read in VulnBank Container | ERROR | Post-RCE credential harvesting |
| Executable Written to Writable Mount | ERROR | Attacker tool staging after RCE |
| Unexpected Process in Postgres Container | CRITICAL | Lateral movement to database tier |
| K8s Service Account Token Read | CRITICAL | Kubernetes API credential theft |

### Attack exercises

The `attack-exercises.md` file contains six hands-on exercises that
trigger each rule and show the expected Falco output.

Open it in one terminal and keep Falco logs open in another:

```bash
# Terminal 1 — watch Falco
kubectl logs -n falco -l app.kubernetes.io/name=falco -f | grep -v DEBUG

# Terminal 2 — run exercises
cat phase-2/falco/attack-exercises.md
```

### What Falco cannot see

Falco operates at the syscall level. Application-layer attacks that do
not cause unusual syscalls are invisible to it:

- SQL injection — HTTP payload, no unusual syscall
- JWT manipulation — HTTP header manipulation, no unusual syscall
- BOLA/BOPLA — valid HTTP requests with different IDs
- Race conditions — legitimate syscalls at high frequency

This is why Falco is one layer of a defence-in-depth stack, not a
replacement for application-level controls.

---

## Step 3 — Observability

### Install

```bash
cd phase-2/observability
bash install.sh

# Access Grafana
kubectl port-forward svc/loki-grafana 3000:80 -n observability

# Open in browser: http://localhost:3000
# Username: admin
# Password: VulnBankLab2024
```

### Load the dashboard

```bash
kubectl apply -f grafana-dashboard-configmap.yaml

# Restart Grafana to pick up the ConfigMap
kubectl rollout restart deployment/loki-grafana -n observability
```

The VulnBank Security Monitoring dashboard loads automatically.
It contains four panels:

| Panel | Data Source | What It Shows |
|---|---|---|
| Falco Security Alerts | Loki | Live alert stream, filterable by rule and priority |
| Kong Blocked Routes (404) | Loki | Requests terminated by Kong — attacker enumeration |
| Kong Rate Limit Events (429) | Loki | Rate limit triggers — brute-force attempt indicator |
| Falco Alert Count by Rule | Loki | Bar chart of alert frequency per rule over time |

### Verifying log ingestion

```bash
# Confirm Promtail is scraping Falco logs
kubectl logs -n observability -l app=promtail --tail=20 \
  | grep -i "falco\|vuln-bank\|kong"

# In Grafana — Explore tab, query:
# {app="falco"} | json
# {namespace="kong"}
```

---

## Phase 2 Vuln-to-Control Mapping

Extending the Phase 1 mapping table with Phase 2 controls:

| Vulnerability | Phase 1 Control | Phase 2 Control | Residual Risk |
|---|---|---|---|
| RCE via file upload | NetworkPolicy egress block | Falco: shell spawn detection | Medium — detection, not prevention |
| SSRF | Kong route blocking + NetworkPolicy | Falco: outbound connection detection | Low — dual prevention + detection |
| Credential harvesting post-RCE | None | Falco: sensitive file read detection | Low |
| Container escape (privileged) | None | Kyverno: deny-privileged-containers (Enforce) | Low |
| Running as root | None | Kyverno: deny-root-pods (Audit → Enforce) | Medium until switched to Enforce |
| K8s API credential theft | automountServiceAccountToken: false (manifest) | Kyverno enforces it cluster-wide + Falco detects token read | Low |
| Supply chain / unknown image | None | Kyverno: restrict-image-registries | Low in Audit; Medium until Enforce |
| No NetworkPolicy on new namespaces | Manual policy per namespace | Kyverno: auto-generates on label | Low |
| Disk exhaustion via file upload | ephemeral-storage limit (manifest) | Kyverno: require-resource-limits enforces it | Low |

---

## Resource Budget (Phase 2 additions)

| Component | Memory (approx) |
|---|---|
| Kyverno (admission controller) | ~150 MB |
| Falco (DaemonSet) | ~256 MB |
| Loki | ~256 MB |
| Grafana | ~128 MB |
| Promtail (DaemonSet) | ~64 MB |
| **Phase 2 total** | **~854 MB** |
| Phase 1 total | ~800 MB |
| **Combined total** | **~1.65 GB** |

Your VM has 12 GiB allocated. Combined Phase 1 + Phase 2 uses under 2 GiB,
leaving comfortable headroom.

---

## Known Gotchas

| Issue | Symptom | Fix |
|---|---|---|
| Falco fails to start on k3s | `driver: failed to load` in logs | Check kernel version — modern_ebpf needs Linux 5.8+. Run `uname -r` on the node. If below 5.8, switch to `driver.kind=ebpf` in `falco-values.yaml`. |
| Kyverno blocks cert-manager pods | PolicyReport shows violations in cert-manager namespace | Policies are scoped to `vuln-bank`, `vuln-bank-db`, `kong` only. cert-manager namespace is excluded intentionally. |
| Grafana dashboard shows no data | Empty panels after import | Confirm Promtail is running: `kubectl get pods -n observability`. Then trigger a Falco rule (run attack-exercises.md Exercise 3) to generate log data. |
| PolicyReport is empty after `kubectl apply -f policies/` | No violations shown | Kyverno scans existing resources in the background. Wait 60 seconds and re-check. Background scanning can be triggered manually with `kubectl annotate clusterpolicy --all kyverno.io/policy-version=$(date +%s)`. |
| `generate` policy not creating NetworkPolicy | NetworkPolicy not appearing in labelled namespace | Confirm Kyverno has RBAC permissions to create NetworkPolicies. Check: `kubectl get clusterrolebinding \| grep kyverno`. |

---

## What Comes Next (Phase 3 ideas)

- **Vault** — replace Kubernetes Secrets with Vault dynamic secrets and
  agent sidecar injection. Eliminates static credentials from the cluster.
- **Trivy Operator** — continuous vulnerability scanning of running images
  (not just at build time). Produces VulnerabilityReport resources per pod.
- **WAF layer** — ModSecurity or Kong's request-validator plugin to detect
  SQL injection and XSS at the gateway. Addresses the HIGH residual risks
  that Falco cannot see (application-layer attacks with no unusual syscalls).
- **Sealed Secrets or External Secrets Operator** — GitOps-safe secret
  management so credentials are never stored in plaintext in the repo.

---

## Disclaimer

This module is part of a deliberately vulnerable application lab.
Do not deploy VulnBank or these configurations on public networks
or with real data.
