# Expected Scan Outputs

## OpenSCAP — Pass/Fail Distribution

```
           3 error
          12 fail
         120 pass
          85 notapplicable
```

## kube-bench — K8s 1.24 / kind

```
[PASS] 1.1.1 Ensure that the API server pod specification file permissions are set to 600 or more restrictive
[PASS] 1.1.2 Ensure that the API server pod specification file ownership is set to root:root
[PASS] 1.2.2 Ensure that the --basic-auth-file argument is not set
[PASS] 1.2.5 Ensure that the --kubelet-https argument is set to true
[PASS] 1.2.6 Ensure that the --kubelet-client-certificate and --kubelet-client-key arguments are set as appropriate
[PASS] 1.2.14 Ensure that the --authorization-mode argument is not set to AlwaysAllow
[PASS] 1.2.22 Ensure that the --service-account-lookup argument is set to true
[PASS] 2.1 Ensure that the --cert-file and --key-file arguments are set as appropriate
[PASS] 2.2 Ensure that the --client-cert-auth argument is set to true
[PASS] 2.3 Ensure that the --auto-tls argument is not set to true
[PASS] 2.4 Ensure that the --peer-cert-file and --peer-key-file arguments are set as appropriate
[PASS] 2.5 Ensure that the --peer-client-cert-auth argument is set to true
[PASS] 2.6 Ensure that the --peer-auto-tls argument is not set to true
[PASS] 3.2.1 Ensure that a minimal audit policy is created
[PASS] 5.3.2 Ensure that the cluster has at least one active Network Policy
[PASS] 5.1.1 Ensure that the default service accounts are not actively used
[PASS] 5.2.1 Ensure Pod Security Standards are set to Restricted
[PASS] 5.2.10 Ensure that containers run as non-root
[PASS] 5.2.11 Ensure that containers have readOnlyRootFilesystem enabled
[PASS] 5.2.12 Ensure that containers drop ALL capabilities
[PASS] 5.2.13 Ensure that privilege escalation is not allowed

[FAIL] 1.1.3 Ensure that the controller manager pod specification file permissions are set to 600 or more restrictive
[FAIL] 1.1.5 Ensure that the scheduler pod specification file permissions are set to 600 or more restrictive
[FAIL] 1.1.7 Ensure that the etcd pod specification file permissions are set to 600 or more restrictive
[FAIL] 1.2.22 Ensure that the --anonymous-auth argument is set to false
[FAIL] 1.2.24 Ensure that the --profiling argument is set to false
[FAIL] 1.4.1 Ensure that the argument --authorization-mode is set to RBAC or Webhook
[FAIL] 4.1.1 Ensure that the kubelet service file permissions are set to 600 or more restrictive

[WARN] 1.1.8 Ensure that the etcd pod specification file ownership is set to root:root
[WARN] 1.2.34 Ensure that the --encryption-provider-config argument is set as appropriate
[WARN] 5.4.1 Prefer using secrets as files over secrets as environment variables
```

## How to Read These

- **PASS** on a control you implemented in Weeks 2–4 = your Kyverno policy,
  PSA, or NetworkPolicy is working. This is evidence for the auditor.
- **FAIL** on file permissions (1.1.x) = expected on kind, because kind runs
  control plane components as containers. In a production cluster these would
  be hardened.
- **WARN** on encryption-provider-config = kind doesn't configure etcd
  encryption by default. In a production FI cluster this must be remediated.
