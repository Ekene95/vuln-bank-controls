#!/bin/bash
# install.sh — Install Falco on the cluster via Helm
#
# Falco uses eBPF (or kernel module) to instrument syscalls from every
# container at the kernel level. It is the runtime detection layer —
# Kyverno prevents bad configs from being deployed, Falco detects
# bad behaviour at runtime after deployment.
#
# This installs Falco in modern_ebpf driver mode, which does not require
# a kernel module and works on most modern Linux kernels (5.8+).
# k3s on a reasonably recent kernel supports this.

set -e

echo "Adding Falco Helm repo..."
helm repo add falcosecurity https://falcosecurity.github.io/charts
helm repo update

echo "Installing Falco..."
helm install falco falcosecurity/falco \
  --namespace falco \
  --create-namespace \
  --set driver.kind=modern_ebpf \
  --set falco.grpc.enabled=true \
  --set falco.grpcOutput.enabled=true \
  --set tty=true \
  --set falcoctl.artifact.install.enabled=true \
  --set falcoctl.artifact.follow.enabled=true \
  --values falco-values.yaml

echo "Waiting for Falco DaemonSet to be ready..."
kubectl rollout status daemonset/falco -n falco --timeout=120s

echo ""
echo "Falco installed. Verify with:"
echo "  kubectl get pods -n falco"
echo ""
echo "Watch alerts in real time:"
echo "  kubectl logs -n falco -l app.kubernetes.io/name=falco -f | grep -v DEBUG"
echo ""
echo "Apply custom rules:"
echo "  # Rules are loaded via the falco-custom-rules ConfigMap"
echo "  kubectl apply -f falco-custom-rules.yaml"
