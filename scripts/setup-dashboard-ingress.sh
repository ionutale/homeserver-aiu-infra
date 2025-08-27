#!/usr/bin/env bash
# setup-dashboard-ingress.sh
# Automates Dashboard + MetalLB + Ingress exposure on home LAN.
set -euo pipefail

# Resolve repo root (script may be invoked from anywhere)
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

REMOVE_NODEPORT="${REMOVE_NODEPORT:-false}"
HOSTNAME="${HOSTNAME:-dashboard.home.lan}"
DASHBOARD_DIR="k8s/kubernetes-dashboard"
METALLB_DIR="k8s/metallb"
INGRESS_NS="ingress-nginx"
INGRESS_SVC="ingress-nginx-controller"
TIMEOUT_SEC=300

req() { command -v "$1" >/dev/null 2>&1 || { echo "Missing required command: $1" >&2; exit 1; }; }
req kubectl
req awk
req curl

if [[ ! -f "${DASHBOARD_DIR}/dashboard-upstream.yaml" ]]; then
  echo "ERROR: Expected file ${DASHBOARD_DIR}/dashboard-upstream.yaml not found (repo layout mismatch)." >&2
  exit 1
fi

step() { local n="$1" msg="$2"; echo "[$n] $msg"; }

step 1 "Apply (or re-apply) core Dashboard manifest (incl NetworkPolicy)"
kubectl apply -f "${DASHBOARD_DIR}/dashboard-upstream.yaml"

step 2 "Apply remaining Dashboard resources (RBAC, ingress, nodeport, certs, etc.)"
# Apply specific known manifests explicitly to avoid scripts / non-yaml files.
for f in \
  rbac-least-privilege.yaml \
  admin-user.yaml \
  dashboard-nodeport-service.yaml \
  ingress.yaml \
  ingress-loadbalancer-service-patch.yaml \
  ; do
  [[ -f "${DASHBOARD_DIR}/$f" ]] && kubectl apply -f "${DASHBOARD_DIR}/$f" || echo "(skip missing $f)"
done

step 3 "Install MetalLB core components"
kubectl apply -f "${METALLB_DIR}/metallb-install.yaml"

step 4 "Wait for MetalLB pods Ready"
start_time=$(date +%s)
while true; do
  not_ready=$(kubectl -n metallb-system get pods --no-headers 2>/dev/null | awk '$2 !~ /1\\/1/ {c++} END {print c+0}') || true
  if [[ -z "$not_ready" ]]; then
    sleep 2; continue
  fi
  [[ "$not_ready" == "0" ]] && break
  if (( $(date +%s) - start_time > TIMEOUT_SEC )); then
    echo "ERROR: MetalLB pods not ready within ${TIMEOUT_SEC}s" >&2
    kubectl -n metallb-system get pods || true
    exit 1
  fi
  sleep 2
done

echo "MetalLB pods Ready."

step 5 "Apply MetalLB address pool & L2 advertisement"
kubectl apply -f "${METALLB_DIR}/metallb-config.yaml"

step 6 "Patch ingress controller Service to LoadBalancer (MetalLB will assign IP)"
kubectl apply -f "${DASHBOARD_DIR}/ingress-loadbalancer-service-patch.yaml"

step 7 "Wait for External IP on ${INGRESS_NS}/${INGRESS_SVC}"
start_time=$(date +%s)
LB_IP=""
while true; do
  LB_IP=$(kubectl -n "${INGRESS_NS}" get svc "${INGRESS_SVC}" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
  if [[ -n "${LB_IP}" ]]; then
    echo "Got External IP: ${LB_IP}"
    break
  fi
  if (( $(date +%s) - start_time > TIMEOUT_SEC )); then
    echo "ERROR: Timed out waiting for LoadBalancer IP" >&2
    kubectl -n "${INGRESS_NS}" get svc "${INGRESS_SVC}" || true
    exit 1
  fi
  sleep 2
done

step 8 "Ensure /etc/hosts contains ${HOSTNAME} -> ${LB_IP}"
HOSTS_LINE="${LB_IP} ${HOSTNAME}"
if grep -qE "[[:space:]]${HOSTNAME}([[:space:]]|$)" /etc/hosts; then
  echo "Entry for ${HOSTNAME} exists; not modifying (manual verify recommended)."
else
  if [[ $EUID -ne 0 ]]; then
    echo "Attempting to append via sudo..."
    echo "${HOSTS_LINE}" | sudo tee -a /etc/hosts >/dev/null || echo "Unable to modify /etc/hosts (continuing)"
  else
    echo "${HOSTS_LINE}" >> /etc/hosts
  fi
  echo "Added: ${HOSTS_LINE}"
fi

step 9 "Test HTTPS reachability (expect 200/302)"
HTTP_CODE=$(curl -ks -o /dev/null -w '%{http_code}' "https://${HOSTNAME}/" || true)
echo "HTTP code: ${HTTP_CODE}"
if [[ "${HTTP_CODE}" != "200" && "${HTTP_CODE}" != "302" ]]; then
  echo "WARNING: Unexpected HTTP code. Investigate ingress, DNS, or NetworkPolicy." >&2
fi

step 10 "Optional cleanup (NodePort removal)"
if [[ "${REMOVE_NODEPORT}" == "true" ]]; then
  kubectl -n kubernetes-dashboard delete svc kubernetes-dashboard-nodeport --ignore-not-found
else
  echo "Skipping NodePort removal (set REMOVE_NODEPORT=true to remove)."
fi

echo
echo "Done."
echo "Dashboard URL: https://${HOSTNAME}/"
echo "Get token: ${DASHBOARD_DIR}/get-dashboard-token.sh"
