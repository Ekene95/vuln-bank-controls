# Week 2 — Kubernetes Security: Hardening the Orchestration Layer

## Why This Matters

Kubernetes defaults are designed for convenience, not security. By default:
- Pods run as root
- All pods can reach all other pods (flat network)
- Every service account has broad permissions

In a Nigerian FI, a compromised pod with flat network access can reach the
database tier. The CBN Cybersecurity Framework requires network segmentation
(Domain 4.1) and least-privilege access (Domain 3.2).

---

## What You'll Do

1. Deploy a kind cluster
2. Deploy vuln-bank with namespace isolation
3. Apply Pod Security Standards (restricted profile)
4. Write Network Policies to isolate tiers
5. Create RBAC roles with least privilege

---

## Step 1 — Deploy a kind Cluster

```bash
# Create the cluster
kind create cluster --name vuln-bank-cluster

# Verify
kubectl cluster-info
kubectl get nodes
```

---

## Step 2 — Deploy vuln-bank with Namespaces

```bash
# Create namespaces
kubectl create namespace vuln-bank
kubectl create namespace vuln-bank-db

# Label them for Pod Security Standards
kubectl label namespace vuln-bank pod-security.kubernetes.io/enforce=restricted
kubectl label namespace vuln-bank-db pod-security.kubernetes.io/enforce=restricted
```

### Deploy the application

Apply the manifests from `controls/manifests/`:

```bash
# Deploy Postgres
kubectl apply -f controls/manifests/postgres/postgres.yaml -n vuln-bank-db

# Deploy vuln-bank
kubectl apply -f controls/manifests/vuln-bank/app.yaml -n vuln-bank

# Verify
kubectl get pods -n vuln-bank
kubectl get pods -n vuln-bank-db
```

### Test that PSA is working

Try to deploy a privileged pod:

```bash
kubectl run privileged-test --image=alpine -n vuln-bank \
  --overrides='{"spec":{"containers":[{"name":"t","image":"alpine","securityContext":{"privileged":true}}]}}' \
  -- sleep 30
```

**Expected result:** The pod is rejected.

```
Error from server (Forbidden): pods "privileged-test" is forbidden:
violates PodSecurity "restricted:latest": privileged containers not allowed
```

---

## Step 3 — Apply Network Policies

Network Policies enforce microsegmentation. The database namespace should only
receive traffic from the frontend namespace on port 5432. The frontend should
not reach the internet except on port 443.

### Database NetworkPolicy

Create `network-policy-db.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: db-ingress
  namespace: vuln-bank-db
spec:
  podSelector:
    matchLabels:
      app: postgres
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: vuln-bank
    ports:
    - port: 5432
      protocol: TCP
```

### Frontend NetworkPolicy

Create `network-policy-frontend.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: frontend-egress
  namespace: vuln-bank
spec:
  podSelector:
    matchLabels:
      app: vuln-bank
  policyTypes:
  - Egress
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: vuln-bank-db
    ports:
    - port: 5432
      protocol: TCP
  - to:
    - namespaceSelector: {}
    ports:
    - port: 53
      protocol: UDP
```

### Apply both policies

```bash
kubectl apply -f network-policy-db.yaml
kubectl apply -f network-policy-frontend.yaml

# Verify
kubectl get networkpolicies -n vuln-bank
kubectl get networkpolicies -n vuln-bank-db
```

---

## Step 4 — Configure RBAC

Create two roles with different permission levels.

### Developer Role

Create `rbac/developer-role.yaml`:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: vuln-bank
  name: developer
rules:
- apiGroups: [""]
  resources: ["pods", "pods/log"]
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources: ["pods/exec"]
  verbs: ["create"]
- apiGroups: [""]
  resources: ["services", "endpoints"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  namespace: vuln-bank
  name: developer-binding
subjects:
- kind: ServiceAccount
  name: developer
  namespace: vuln-bank
roleRef:
  kind: Role
  name: developer
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: v1
kind: ServiceAccount
metadata:
  namespace: vuln-bank
  name: developer
```

### Operator Role

Create `rbac/operator-role.yaml`:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: vuln-bank
  name: operator
rules:
- apiGroups: ["", "apps", "extensions"]
  resources: ["deployments", "pods", "services", "configmaps", "secrets"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: [""]
  resources: ["pods/log"]
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources: ["secrets"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  namespace: vuln-bank
  name: operator-binding
subjects:
- kind: ServiceAccount
  name: operator
  namespace: vuln-bank
roleRef:
  kind: Role
  name: operator
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: v1
kind: ServiceAccount
metadata:
  namespace: vuln-bank
  name: operator
```

### Apply RBAC resources

```bash
kubectl apply -f rbac/developer-role.yaml
kubectl apply -f rbac/operator-role.yaml
```

### Test RBAC

```bash
# Test as developer — should be able to view pods but not delete them
kubectl --as=system:serviceaccount:vuln-bank:developer get pods -n vuln-bank
kubectl --as=system:serviceaccount:vuln-bank:developer delete pod some-pod -n vuln-bank

# Test as operator — should be able to deploy and delete
kubectl --as=system:serviceaccount:vuln-bank:operator get pods -n vuln-bank
kubectl --as=system:serviceaccount:vuln-bank:operator get secrets -n vuln-bank
```

**Expected results:**

| Action | Developer | Operator |
|---|---|---|
| `get pods` | Allowed | Allowed |
| `delete pod` | Denied | Allowed |
| `get secrets` | Denied | Allowed |

---

## Concepts Extracted

- PSA restricted profile is the K8s-native way to enforce pod security
- Network Policies implement microsegmentation between tiers
- RBAC with separate service accounts enforces least-privilege access
- kind is a testing cluster — production hardening requires more (node
  hardening, audit logging, encryption at rest)

---

## Deliverable

Submit a single `k8s-hardening-evidence.md` containing:
1. Output of `kubectl get pods -n vuln-bank` and `kubectl get pods -n vuln-bank-db`
2. The two NetworkPolicy YAML files
3. The RBAC YAML files
4. Output from the RBAC test commands showing developer vs. operator permissions
5. Two-sentence summary: "What attack paths does this configuration prevent?
   What residual risk remains?"
