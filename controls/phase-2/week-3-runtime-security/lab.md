# Week 3 — Runtime Security: Detecting What Shouldn't Be Happening

## Why This Matters

Preventive controls (PSA, Network Policies, Kyverno) block bad configurations
before they reach the cluster. But a determined attacker who finds an
application-level vulnerability (SQL injection, SSRF, RCE) operates inside
the allowed configuration.

Falco watches what *actually happens* at the kernel level — every syscall,
every file open, every network connection. When a container does something it
shouldn't, Falco fires an alert.

In a Nigerian FI, detecting a shell spawned in a payment-processing container
or an unexpected outbound connection to an unknown IP is how you catch a
breach before exfiltration completes.

---

## What You'll Do

1. Deploy Falco to the kind cluster
2. Write custom detection rules for vuln-bank
3. Run 6 attack exercises and observe each alert
4. Configure alert routing

---

## Prerequisites

- Course 2 Weeks 1–2 completed (cluster running, vuln-bank deployed,
  Kyverno policies applied)
- `helm` installed (included in `.devcontainer.json`)

---

## Step 1 — Deploy Falco

```bash
# Install Falco using the provided Helm values
cd controls/phase-2/falco
bash install.sh

# Verify Falco is running (one pod per node)
kubectl get pods -n falco

# Watch live alerts (open a second terminal)
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

### Understanding the output

Each Falco alert contains:
- **Priority**: CRITICAL, ERROR, WARNING, NOTICE, INFO, DEBUG
- **Rule**: The name of the rule that fired
- **Output**: A human-readable description of what happened
- **Fields**: Container ID, image, user, process name, file name, etc.

---

## Step 2 — Apply Custom Falco Rules

The custom rules are in `controls/phase-2/falco/falco-custom-rules.yaml`.

### What the rules detect

| Rule | Priority | What It Catches |
|---|---|---|
| Shell Spawned in VulnBank Container | CRITICAL | RCE via unrestricted file upload |
| Unexpected Outbound Connection from VulnBank | WARNING | SSRF via `/upload_profile_picture_url` |
| Sensitive File Read in VulnBank Container | ERROR | Post-RCE credential harvesting |
| Executable Written to Writable Mount | ERROR | Attacker tool staging after RCE |
| Unexpected Process in Postgres Container | CRITICAL | Lateral movement to database tier |
| K8s Service Account Token Read | CRITICAL | K8s API credential theft |

### Apply the rules

```bash
kubectl apply -f controls/phase-2/falco/falco-custom-rules.yaml
kubectl rollout restart daemonset/falco -n falco

# Verify rules are loaded
kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=20 | head -5
```

---

## Step 3 — Attack Exercises

Open the attack exercises file in a second terminal:

```bash
cat controls/phase-2/falco/attack-exercises.md
```

Each exercise instructs you to:
1. Run an attack command against the vuln-bank API
2. Watch the Falco alert fire in real time
3. Understand which rule triggered and why

### Exercise 1 — SSRF (triggers Rule 2)

```bash
curl -s -X POST http://localhost:5000/upload_profile_picture_url \
  -H "Authorization: Bearer <JWT>" \
  -H "Content-Type: application/json" \
  -d '{"image_url":"http://169.254.169.254/latest/meta-data/"}'
```

**Expected Falco output:**

```
WARNING | Unexpected Outbound Connection from VulnBank
         | Connection to 169.254.169.254:80 from vuln-bank container
```

### Exercise 2 — Shell Spawn (triggers Rule 1)

```bash
kubectl exec -n vuln-bank deploy/vuln-bank -- /bin/sh -c "id"
```

**Expected Falco output:**

```
CRITICAL | Shell Spawned in VulnBank Container
          | Shell /bin/sh spawned by process python3 in vuln-bank container
```

### Exercise 3 — Sensitive File Read (triggers Rule 3)

```bash
kubectl exec -n vuln-bank deploy/vuln-bank -- cat /etc/shadow
```

**Expected Falco output:**

```
ERROR | Sensitive File Read in VulnBank Container
       | File /etc/shadow read by process cat in vuln-bank container
```

### Exercises 4–6

Run the remaining exercises from `attack-exercises.md`:
- **Exercise 4**: Write an executable to `/tmp` (triggers Rule 4)
- **Exercise 5**: Spawn a process in the postgres container (triggers Rule 5)
- **Exercise 6**: Read the service account token (triggers Rule 6)

---

## Step 4 — Configure Alert Routing

Detection without notification is useless. Configure Falco to send alerts
to a destination.

### Option A: Slack Webhook

Create `falco-alert-config.yaml`:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: falco-config
  namespace: falco
data:
  falco.yaml: |
    json_output: true
    json_include_output_property: true
    
    alert_routes:
      - name: slack
        type: slack
        url: https://hooks.slack.com/services/YOUR/WEBHOOK/URL
        channel: "#security-alerts"
        priority: WARNING
```

### Option B: File Output (fallback)

If no Slack webhook is available, use file output:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: falco-config
  namespace: falco
data:
  falco.yaml: |
    json_output: true
    json_include_output_property: true
    
    file_output:
      enabled: true
      keep_alive: false
      filename: /var/log/falco/alerts.json
```

Apply the config and reload Falco:

```bash
kubectl apply -f falco-alert-config.yaml
kubectl rollout restart daemonset/falco -n falco
```

---

## What Falco Cannot See

Falco operates at the syscall level. Application-layer attacks with no
unusual syscalls are invisible to it:

| Attack | Why Falco Misses It | What Covers It |
|---|---|---|
| SQL injection | HTTP payload, no unusual syscall | WAF, SAST, DAST (Course 1) |
| JWT manipulation | HTTP header, no unusual syscall | API gateway, Course 1 |
| BOLA/BOPLA | Valid HTTP with different IDs | Authorization testing |
| Race conditions | Legitimate syscalls at high frequency | Code review |

This is why Falco is one layer of defence in depth — not a replacement for
application-level controls.

---

## Concepts Extracted

- Falco detects at the syscall level, not the application level
- Preventive controls have limits — detection fills the gap
- Custom rules must be mapped to specific application vulnerabilities
- Alerting is as important as detection

---

## Deliverable

Submit `runtime-security-evidence.md` containing:
1. Output of `kubectl get pods -n falco`
2. For at least 3 of the 6 attack exercises: the command you ran and the
   Falco alert that fired
3. The alert routing configuration you used (Slack webhook or file output)
4. Two-sentence summary: "Which attacks did Falco detect? What attacks would
   Falco miss in this application?"
