#!/usr/bin/env bash
# Patch ingress-nginx controller Service to use node IP via externalIPs.
set -euo pipefail

NODE_IP="${NODE_IP:-}"  # If empty, will attempt to auto-detect single node InternalIP
SVC_NS="ingress-nginx"
SVC_NAME="ingress-nginx-controller"

if [[ -z "$NODE_IP" ]]; then
  NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
fi

echo "Using node IP: $NODE_IP"

kubectl -n "$SVC_NS" get svc "$SVC_NAME" >/dev/null 2>&1 || { echo "Service $SVC_NS/$SVC_NAME not found" >&2; exit 1; }

echo "Patching service to ensure type=NodePort and add externalIPs list"
kubectl -n "$SVC_NS" patch svc "$SVC_NAME" -p '{"spec":{"type":"NodePort"}}' || true
kubectl -n "$SVC_NS" patch svc "$SVC_NAME" --type=merge -p '{"spec":{"externalIPs":["'"$NODE_IP"'"]}}'

echo "Result:"
kubectl -n "$SVC_NS" get svc "$SVC_NAME" -o wide

echo
echo "Add to /etc/hosts on clients (if not using DNS):"
echo "  $NODE_IP  dashboard.home.lan"
echo
echo "Then browse: https://dashboard.home.lan/ (Ingress)"
