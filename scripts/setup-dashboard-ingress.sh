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
  ; do
  [[ -f "${DASHBOARD_DIR}/$f" ]] && kubectl apply -f "${DASHBOARD_DIR}/$f" || echo "(skip missing $f)"
done

step 3 "Install MetalLB core components"
kubectl apply -f "${METALLB_DIR}/metallb-install.yaml"

step 4 "Wait for MetalLB controller & speaker readiness"
kubectl -n metallb-system wait --for=condition=available deployment/controller --timeout=180s 2>/dev/null || {
  echo "WARN: controller deployment wait condition not met (continuing)" >&2
}
kubectl -n metallb-system rollout status ds/speaker --timeout=180s || {
  echo "WARN: speaker daemonset rollout not fully ready (continuing)" >&2
}
echo "MetalLB components proceeded (check manually if issues)."

# Ensure memberlist secret exists (required for MetalLB gossip in some versions)
if ! kubectl -n metallb-system get secret memberlist >/dev/null 2>&1; then
  step 4.1 "Create MetalLB memberlist secret"
  if command -v openssl >/dev/null 2>&1; then
    kubectl create secret generic -n metallb-system memberlist \
      --from-literal=secretkey="$(openssl rand -base64 128)"
  else
    kubectl create secret generic -n metallb-system memberlist \
      --from-literal=secretkey="$(head -c32 /dev/urandom | base64)"
  fi
  echo "Memberlist secret created."
  echo "Restarting MetalLB pods to pick up secret (if needed)."
  kubectl -n metallb-system delete pod -l app=metallb --ignore-not-found || true
fi

step 5 "Apply MetalLB address pool & L2 advertisement"
kubectl apply -f "${METALLB_DIR}/metallb-config.yaml"

step 6 "Ensure ingress controller Service type=LoadBalancer (MetalLB will assign IP)"
if kubectl -n "${INGRESS_NS}" get svc "${INGRESS_SVC}" >/dev/null 2>&1; then
  current_type=$(kubectl -n "${INGRESS_NS}" get svc "${INGRESS_SVC}" -o jsonpath='{.spec.type}')
  if [[ "$current_type" != "LoadBalancer" ]]; then
    echo "Patching service type from $current_type to LoadBalancer"
    kubectl -n "${INGRESS_NS}" patch svc "${INGRESS_SVC}" -p '{"spec":{"type":"LoadBalancer"}}'
  else
    echo "Service already LoadBalancer"
  fi
  echo "Adding/updating MetalLB address-pool annotation"
  kubectl -n "${INGRESS_NS}" annotate svc "${INGRESS_SVC}" metallb.universe.tf/address-pool=dashboard-pool --overwrite || true
else
  echo "ERROR: ingress controller service ${INGRESS_NS}/${INGRESS_SVC} not found. Install ingress-nginx first." >&2
  exit 1
fi

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
