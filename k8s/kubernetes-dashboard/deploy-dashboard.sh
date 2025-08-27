#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../" && pwd)"

kubectl apply -f "$REPO_ROOT/k8s/metrics-server/metrics-server.yaml"
kubectl apply -f "$REPO_ROOT/k8s/kubernetes-dashboard/" 

# Wait for dashboard pod
printf "Waiting for kubernetes-dashboard pod to be Ready...\n"
kubectl -n kubernetes-dashboard wait --for=condition=Ready pod -l k8s-app=kubernetes-dashboard --timeout=180s || true

printf "\nLogin token (copy & paste into Dashboard):\n"
"$REPO_ROOT/k8s/kubernetes-dashboard/get-dashboard-token.sh" || true

NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
printf "\nOpen: https://%s:32443/ (accept self-signed cert warning)\n" "$NODE_IP"
