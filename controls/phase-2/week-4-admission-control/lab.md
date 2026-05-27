# Week 4 — Admission Control: Enforcing Policy at the Gate

## Why This Matters

Admission control is the pipeline-to-cluster handshake. Kyverno sits at the
door and checks every resource before it enters the cluster. If a pod doesn't
meet policy — running as root, missing resource limits, unsigned image — it's
rejected before it can do any damage.

In a Nigerian FI, admission control prevents a developer from accidentally
deploying a container that runs as root and has network access to the
production database. The CBN Cybersecurity Framework requires this kind of
pre-deployment enforcement under Access Control (Domain 3.2).

---

## What You'll Do

1. Deploy Kyverno to the kind cluster
2. Apply policies that block non-compliant pods
3. Test each policy in Audit mode first, then switch to Enforce
4. Write a mutating policy that auto-fixes missing security contexts
5. Verify CoSign signature at admission time

---

## Prerequisites

- Course 2 Weeks 1–2 completed (cluster running)
- `helm` installed
- CoSign key pair generated (from Week 1)

---

## Step 1 — Deploy Kyverno

```bash
cd controls/phase-2/kyverno
bash install.sh

# Verify Kyverno is running
kubectl get pods -n kyverno

# Verify Kyverno is the admission webhook
kubectl get validatingwebhookconfigurations
kubectl get mutatingwebhookconfigurations
```

---

## Step 2 — Apply All Policies

All policies start in Audit mode (except `02-deny-privileged-containers`,
which is safe to Enforce immediately).

```bash
kubectl apply -f controls/phase-2/kyverno/policies/

# Verify
kubectl get clusterpolicies
```

### Understanding Audit vs. Enforce

| Mode | Behaviour | When to Use |
|---|---|---|
| **Audit** | Logs violations, allows pods through | Default — burn-in period to see what fires |
| **Enforce** | Blocks non-compliant pods | After confirming no false positives |

---

## Step 3 — Test Root-Blocking Policy (Policy 01)

### In Audit mode

Apply the policy. Deploy a pod that runs as root:

```bash
kubectl run root-test --image=alpine -n vuln-bank \
  --overrides='{"spec":{"securityContext":{"runAsUser":0}}}' -- sleep 10
```

The pod should run (Audit mode allows it). Check the policy report:

```bash
kubectl get policyreport -n vuln-bank -o yaml | grep -A5 "fail"
```

### Switch to Enforce

Edit `01-deny-root-pods.yaml` and change `validationFailureAction: Audit`
to `validationFailureAction: Enforce`. Re-apply:

```bash
kubectl apply -f controls/phase-2/kyverno/policies/01-deny-root-pods.yaml

# Test again — this time the pod should be rejected
kubectl run root-test-2 --image=alpine -n vuln-bank \
  --overrides='{"spec":{"securityContext":{"runAsUser":0}}}' -- sleep 10
```

**Expected result:**

```
Error from server: admission webhook "validate.kyverno.svc" denied the request:
Containers must not run as root. Set securityContext.runAsNonRoot: true
```

---

## Step 4 — Test Signature Verification Policy (Policy 09)

Policy 09 (`verify-image-signature`) requires all images from `ghcr.io/*` to
carry a valid CoSign signature.

### Prepare the public key secret

```bash
# Create the secret that Kyverno will use to verify signatures
kubectl create secret generic cosign-public-key \
  --namespace kyverno \
  --from-file=cosign.pub=/path/to/cosign.pub
```

### Test with an unsigned image

```bash
kubectl run unsigned-test --image=ghcr.io/fake-org/fake-image:latest -n vuln-bank
```

**Expected audit result:**

```
FAIL: image ghcr.io/fake-org/fake-image:latest has no signature
```

### Test with a signed image

Deploy the signed vuln-bank image from Week 1:

```yaml
kubectl apply -f test-pods/signed-pod.yaml
```

### Switch to Enforce

```bash
# Edit 09-verify-image-signature.yaml
# Change validationFailureAction: Audit → Enforce
kubectl apply -f controls/phase-2/kyverno/policies/09-verify-image-signature.yaml

# Verify unsigned images are now rejected
kubectl run unsigned-test-2 --image=ghcr.io/fake-org/fake-image:latest -n vuln-bank
```

---

## Step 5 — Write a Mutating Policy

Mutating policies automatically fix missing configurations. Create
`policy-mutate-run-as-non-root.yaml`:

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: auto-add-run-as-non-root
  annotations:
    policies.kyverno.io/title: Auto-Add runAsNonRoot
    policies.kyverno.io/category: Pod Security
    policies.kyverno.io/severity: medium
spec:
  validationFailureAction: Enforce
  rules:
  - name: inject-run-as-non-root
    match:
      any:
      - resources:
          kinds: ["Pod"]
          namespaces:
            - vuln-bank
            - vuln-bank-db
    mutate:
      patchStrategicMerge:
        spec:
          securityContext:
            runAsNonRoot: true
          containers:
          - (name): "*"
            securityContext:
              runAsNonRoot: true
              allowPrivilegeEscalation: false
```

```bash
kubectl apply -f policy-mutate-run-as-non-root.yaml

# Test: deploy a pod without any securityContext
kubectl run test-mutate --image=alpine -n vuln-bank -- sleep 10

# Check what Kyverno added
kubectl get pod test-mutate -n vuln-bank -o yaml | grep -A5 "securityContext"
```

---

## Summary: Policy Inventory

| Policy | What It Does | Mode |
|---|---|---|
| 01 — deny-root-pods | Blocks containers running as root | Audit → Enforce |
| 02 — deny-privileged-containers | Blocks privileged mode, hostNetwork, hostPath | Enforce |
| 04 — require-resource-limits | Requires CPU/memory/storage limits | Audit |
| 05 — disable-automount-sa-token | Prevents K8s API token mounting | Audit |
| 05 — require-readonly-rootfs | Requires read-only root filesystem | Audit |
| 06 — deny-capability-escalation | Drops all Linux capabilities | Audit |
| 07 — restrict-image-registries | Allowlists approved registries | Audit |
| 08 — generate-default-deny-netpol | Auto-creates NetworkPolicy on new namespaces | Generate |
| 09 — verify-image-signature | Requires CoSign signature on images | Audit → Enforce |

---

## Concepts Extracted

- Admission control is the last gate before a resource enters the cluster
- Audit → Enforce progression prevents accidental production outages
- Validating policies block non-compliant resources
- Mutating policies automatically fix missing configurations
- Signature verification at admission closes the supply chain loop

---

## Deliverable

Submit `admission-control-evidence.md` containing:
1. Output of `kubectl get clusterpolicies`
2. Screenshot or text of the root-blocking policy test (Policy 01) —
   showing the Enforce rejection message
3. Screenshot or text of the signature verification test (Policy 09) —
   showing audit failure for unsigned image, PASS for signed image
4. The mutating policy YAML (`policy-mutate-run-as-non-root.yaml`)
5. Two-sentence summary: "Which policies would you switch to Enforce first
   in production? Which would you keep in Audit and why?"
