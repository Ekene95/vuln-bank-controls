#!/bin/bash
# install.sh — Install Loki + Grafana via the loki-stack Helm chart
#
# This deploys:
#   - Grafana        — dashboard UI
#   - Loki           — log aggregation backend
#   - Promtail       — log collector (DaemonSet on every node)
#
# Promtail scrapes pod logs from /var/log/pods/* on the node.
# It automatically picks up Falco alerts (JSON on stdout) and
# Kong access logs — no application changes needed.

set -e

echo "Adding Grafana Helm repo..."
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

echo "Installing Loki stack (Loki + Promtail + Grafana)..."
helm install loki grafana/loki-stack \
  --namespace observability \
  --create-namespace \
  --set grafana.enabled=true \
  --set grafana.adminPassword=VulnBankLab2024 \
  --set loki.persistence.enabled=false \
  --set promtail.enabled=true \
  --values observability-values.yaml

echo "Waiting for Grafana to be ready..."
kubectl rollout status deployment/loki-grafana -n observability --timeout=180s

echo ""
echo "Grafana is running. Access it with:"
echo "  kubectl port-forward svc/loki-grafana 3000:80 -n observability"
echo "  Then open: http://localhost:3000"
echo "  Username: admin"
echo "  Password: VulnBankLab2024"
echo ""
echo "Import the VulnBank dashboard:"
echo "  kubectl apply -f grafana-dashboard-configmap.yaml"
echo ""
echo "Loki datasource is pre-configured — dashboards load immediately."
