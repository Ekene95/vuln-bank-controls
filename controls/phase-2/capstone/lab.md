# Course 2 Capstone — Defence in Depth

## Overview

Build and deploy a hardened multi-tier fintech application that demonstrates
every layer of defence in depth taught in Course 2:

1. **Pipeline (from Course 1):** Build, scan, sign, and push images to GHCR
   after passing all security gates
2. **Deployment gate:** Pull signed images and deploy to the K8s cluster —
   Kyverno rejects any unsigned image
3. **Cluster hardening:** PSA enforced, Network Policies isolating tiers,
   RBAC least-privilege
4. **Runtime monitoring:** Falco detecting anomalous behaviour with alerting
5. **Compliance evidence:** kube-bench + OpenSCAP scan results mapped to
   CBN/NDPA controls

---

## Prerequisites

- All Course 2 weeks completed
- A running kind cluster with all controls from Weeks 2–4 applied
- `cosign` key pair
- GitHub repository with Actions enabled

---

## Step 1 — Pipeline: Build, Scan, Sign, Push

Create a GitHub Actions workflow that:

1. Builds the vuln-bank Docker image
2. Runs Snyk Container scan — fails on critical vulnerabilities
3. Signs the image with CoSign
4. Generates SLSA provenance attestation
5. Pushes the signed image to GHCR

### Verification

```bash
# Verify the image is signed
cosign verify --key cosign.pub ghcr.io/<your-org>/vuln-bank:latest

# Verify SLSA provenance
gh attestation verify oci://ghcr.io/<your-org>/vuln-bank:latest --owner <your-org>
```

---

## Step 2 — Deployment Gate: Kyverno Admission Control

1. Ensure Kyverno is deployed and all 9 policies are applied
2. Create the `cosign-public-key` secret in the `kyverno` namespace
3. Switch `verify-image-signature` policy to Enforce mode
4. Deploy the signed vuln-bank image — should pass
5. Attempt to deploy an unsigned image — should be rejected

### Verification

```bash
# Deploy the signed image
kubectl apply -f signed-pod.yaml

# Verify it's running
kubectl get pods -n vuln-bank

# Attempt unsigned deployment - should fail
kubectl apply -f unsigned-pod.yaml
# Expected: admission webhook denied the request
```

---

## Step 3 — Cluster Hardening

1. Verify PSA restricted profile is applied to `vuln-bank` and `vuln-bank-db`
   namespaces
2. Verify Network Policies are in place
3. Verify RBAC roles are configured
4. Attempt a privileged pod — should be rejected

### Verification

```bash
# Check PSA
kubectl describe ns vuln-bank | grep pod-security

# Check Network Policies
kubectl get networkpolicies -n vuln-bank
kubectl get networkpolicies -n vuln-bank-db

# Check RBAC
kubectl get roles -n vuln-bank
kubectl get rolebindings -n vuln-bank

# Test privileged pod rejection
kubectl run test-priv --image=alpine -n vuln-bank \
  --overrides='{"spec":{"containers":[{"name":"t","image":"alpine","securityContext":{"privileged":true}}]}}'
# Expected: Error from server (Forbidden)
```

---

## Step 4 — Runtime Monitoring

1. Verify Falco is deployed and running
2. Trigger a shell spawn in the vuln-bank container
3. Verify the CRITICAL alert fires

### Verification

```bash
# Watch Falco alerts
kubectl logs -n falco -l app.kubernetes.io/name=falco -f | grep -v DEBUG &

# Trigger a shell spawn
kubectl exec -n vuln-bank deploy/vuln-bank -- /bin/sh -c "id"

# Expected Falco alert:
# CRITICAL | Shell Spawned in VulnBank Container
```

---

## Step 5 — Compliance Evidence

1. Run kube-bench against the cluster
2. Map the passing controls to CBN/NDPA requirements
3. Generate the compliance evidence report

### Verification

```bash
kube-bench run --targets master,node

# Confirm the following pass:
# - 5.2.1: Pod Security Standards set to Restricted
# - 5.2.10: Containers run as non-root
# - 5.2.12: Containers drop ALL capabilities
# - 5.3.2: Network Policies isolate workloads
```

---

## Deliverable

Submit `capstone-evidence.md` containing all of the following:

### 1. Pipeline Evidence
- Link to the GitHub Actions run showing a successful build with all gates
- CoSign verification output (`cosign verify ...`)
- SLSA attestation verification output (`gh attestation verify ...`)

### 2. Admission Control Evidence
- Output showing signed pod deployed, unsigned pod rejected

### 3. Cluster Hardening Evidence
- PSA labels on both namespaces
- Network Policy listing
- RBAC role listing
- Privileged pod rejection message

### 4. Runtime Monitoring Evidence
- Falco alert for shell spawn (copy the JSON alert)

### 5. Compliance Evidence
- kube-bench pass/fail summary
- CBN/NDPA control mapping (at least 10 pass rows)

### 6. Assessment
- What is the cluster's overall security posture?
- What is the weakest layer in this deployment?
- What would you add or improve for a production FI deployment?
