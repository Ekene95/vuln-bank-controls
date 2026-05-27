#!/bin/bash
# install.sh — Install Kyverno on the cluster
# Run this once before applying any policies.
# Kyverno v1.12 supports Kubernetes 1.25+

set -e

echo "Adding Kyverno Helm repo..."
helm repo add kyverno https://kyverno.github.io/kyverno/
helm repo update

echo "Installing Kyverno..."
helm install kyverno kyverno/kyverno \
  --namespace kyverno \
  --create-namespace \
  --set admissionController.replicas=1 \
  --set backgroundController.resources.limits.memory=256Mi \
  --set cleanupController.resources.limits.memory=128Mi \
  --set reportsController.resources.limits.memory=128Mi

echo "Waiting for Kyverno admission controller to be ready..."
kubectl rollout status deployment/kyverno-admission-controller \
  -n kyverno --timeout=120s

echo "Kyverno installed. Verify with:"
echo "  kubectl get pods -n kyverno"
echo ""
echo "Apply policies with:"
echo "  kubectl apply -f policies/"
echo ""
echo "NOTE: All policies start in Audit mode."
echo "Review violations with:"
echo "  kubectl get policyreport -A"
echo "  kubectl get clusterpolicyreport"
