#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="kubernetes-dashboard"
SA_NAME="${1:-dashboard-viewer}" # default least-privilege account

if [ "${1:-}" = "" ]; then
	>&2 echo "(Using default service account: $SA_NAME. Pass another SA name as first arg if needed.)"
fi

# Kubernetes 1.24+ preferred path (projected tokens)
if kubectl -n "$NAMESPACE" get sa "$SA_NAME" >/dev/null 2>&1; then
	if TOKEN=$(kubectl create token "$SA_NAME" -n "$NAMESPACE" 2>/dev/null); then
		echo "$TOKEN"
		exit 0
	fi
fi

# Fallback for <1.24 where secrets are auto-created for SAs
SECRET_NAME=$(kubectl -n "$NAMESPACE" get sa "$SA_NAME" -o jsonpath='{.secrets[0].name}' 2>/dev/null || true)
if [ -n "$SECRET_NAME" ]; then
	kubectl -n "$NAMESPACE" get secret "$SECRET_NAME" -o go-template='{{.data.token | base64decode}}'
	echo
	exit 0
fi

echo "Failed to obtain token for service account '$SA_NAME' in namespace '$NAMESPACE'." >&2
echo "Ensure the SA exists and has an associated secret (pre-1.24) or that 'kubectl create token' is supported." >&2
exit 1
