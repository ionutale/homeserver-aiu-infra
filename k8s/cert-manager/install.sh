#!/usr/bin/env bash
set -euo pipefail

VERSION="v1.14.5"  # cert-manager version
URL_BASE="https://github.com/cert-manager/cert-manager/releases/download/${VERSION}"

echo "[cert-manager] Installing CRDs (${VERSION})"
kubectl apply -f "${URL_BASE}/cert-manager.crds.yaml"

# Create namespace if not exists
kubectl get namespace cert-manager >/dev/null 2>&1 || kubectl create namespace cert-manager

# Install core components (controller, webhook, cainjector)
echo "[cert-manager] Installing core components"
kubectl apply -f "${URL_BASE}/cert-manager.yaml"

# Wait for deployments to become ready
for DEP in cert-manager cert-manager-webhook cert-manager-cainjector; do
  echo "[cert-manager] Waiting for deployment $DEP"
  kubectl -n cert-manager rollout status deployment/$DEP --timeout=180s || true
done

# Apply local ClusterIssuer + Certificate (self-signed internal)
if [ -f "$(dirname "$0")/cert-manager.yaml" ]; then
  echo "[cert-manager] Applying local cluster issuer + certificate"
  kubectl apply -f "$(dirname "$0")/cert-manager.yaml"
fi

# Wait for dashboard certificate secret (best-effort)
if kubectl get namespace kubernetes-dashboard >/dev/null 2>&1; then
  echo "[cert-manager] Waiting for dashboard certificate (dashboard-tls)"
  for i in {1..30}; do
    if kubectl -n kubernetes-dashboard get secret dashboard-tls >/dev/null 2>&1; then
      echo "[cert-manager] dashboard-tls secret present"
      break
    fi
    sleep 2
  done
fi

echo "[cert-manager] Done."
