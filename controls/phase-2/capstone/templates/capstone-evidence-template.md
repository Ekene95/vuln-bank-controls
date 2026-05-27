# Course 2 Capstone — Evidence Report

## Environment
- **Date:**
- **Cluster:** kind
- **K8s version:**
- **Host OS:** GitHub Codespaces (Ubuntu)

---

## 1. Pipeline Evidence

### GitHub Actions Run
- **Run URL:**
- **Status:** [PASS / FAIL]

### Cosign Verification
```
[Paste cosign verify output here]
```

### SLSA Attestation Verification
```
[Paste gh attestation verify output here]
```

---

## 2. Admission Control Evidence

### Signed Pod Deployment
```
[Paste kubectl apply output for signed pod]
```

### Unsigned Pod Rejection
```
[Paste kubectl apply output for unsigned pod — should show error]
```

---

## 3. Cluster Hardening Evidence

### Pod Security Standards
```
kubectl describe ns vuln-bank | grep pod-security
```

### Network Policies
```
kubectl get networkpolicies -n vuln-bank
kubectl get networkpolicies -n vuln-bank-db
```

### RBAC
```
kubectl get roles -n vuln-bank
kubectl get rolebindings -n vuln-bank
```

### Privileged Pod Rejection
```
kubectl run test-priv --image=alpine -n vuln-bank \
  --overrides='{"spec":{"containers":[{"name":"t","image":"alpine","securityContext":{"privileged":true}}]}}'
```

---

## 4. Runtime Monitoring Evidence

### Falco Alert — Shell Spawn
```json
[Paste the Falco JSON alert for shell spawn here]
```

---

## 5. Compliance Evidence

### kube-bench Summary
```
[Paste kube-bench summary output]
```

### CBN/NDPA Control Mapping

| CIS ID | CBN Ref | NDPA Art | Technical Control | Result |
|---|---|---|---|---|
| 5.2.1 | CS 3.2 | Art 2.4 | PSA restricted profile | PASS |
| 5.2.10 | CS 3.2 | Art 2.4 | Kyverno deny-root-pods | PASS |
| 5.2.12 | CS 5.1 | Art 2.5 | Capabilities drop ALL | PASS |
| 5.3.2 | CS 4.1 | Art 2.5 | Network Policies | PASS |
| 4.2.1 | CS 3.1 | Art 2.4 | RBAC roles | PASS |
| | CS 2.4 | Art 2.5 | Cosign image signing | PASS |
| | CS 6.2 | Art 5.1 | Falco runtime monitoring | PASS |

---

## 6. Assessment

**What is the cluster's overall security posture?**




**What is the weakest layer in this deployment?**




**What would you add or improve for a production FI deployment?**


