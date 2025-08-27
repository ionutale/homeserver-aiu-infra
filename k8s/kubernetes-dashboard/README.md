# Kubernetes Dashboard Setup

This directory contains manifests and helper script to deploy the official Kubernetes Dashboard in your cluster and expose it on your home LAN.

## Components

- Upstream recommended dashboard manifests (namespaced under `kubernetes-dashboard`).
- An additional `Service` of type `NodePort` (configurable) or an optional `Ingress`.
- An admin `ServiceAccount` + `ClusterRoleBinding` to obtain a login token easily.
 - Optional least-privilege `dashboard-viewer` role & service account.
 - Optional Ingress + cert-manager self-signed internal TLS for `dashboard.home.lan`.
 - OIDC / SSO guidance (see `oidc/README.md`).

## Quick Start

From the repo root:

```bash
kubectl apply -f k8s/kubernetes-dashboard/

Optional (enable cert + ingress + least-privilege):

```bash
kubectl apply -f k8s/cert-manager/cert-manager.yaml
kubectl apply -f k8s/kubernetes-dashboard/rbac-least-privilege.yaml
kubectl apply -f k8s/kubernetes-dashboard/ingress.yaml
```
```

Then retrieve the token (Kubernetes 1.24+):

```bash
kubectl create token admin-user -n kubernetes-dashboard
```

If that fails (older cluster), fall back to:

```bash
kubectl -n kubernetes-dashboard get secret $(kubectl -n kubernetes-dashboard get sa admin-user -o jsonpath='{.secrets[0].name}') -o go-template='{{.data.token | base64decode}}'
```

Or simply run the helper script (still applies NodePort & admin user):

```bash
bash k8s/kubernetes-dashboard/get-dashboard-token.sh
```

Access via:

- NodePort: https://<ANY_NODE_IP>:32443/
- Ingress (after applying ingress + cert): https://dashboard.home.lan/

Because this is exposed via NodePort with a self-signed cert and admin-level token auth, only use it on a trusted, isolated home LAN. Don't expose this NodePort externally without adding proper authentication (OIDC, reverse proxy + SSO, etc.).

(You will get a self-signed cert warning; proceed.)

If you prefer to later secure with ingress + cert manager, you can add an Ingress manifest.

## Files

- `dashboard-upstream.yaml` – Mostly unmodified upstream recommended manifest (possibly trimmed for size).
- `dashboard-nodeport-service.yaml` – Exposes the dashboard via NodePort 32443.
- `admin-user.yaml` – Admin service account + binding.

## Tokens & RBAC

Default admin token (cluster-admin) is powerful. Prefer using the `dashboard-viewer` service account for read-only access:

```bash
bash k8s/kubernetes-dashboard/get-dashboard-token.sh dashboard-viewer
```

If you still need full admin during setup:

```bash
bash k8s/kubernetes-dashboard/get-dashboard-token.sh admin-user
```

To create custom roles, clone `rbac-least-privilege.yaml` and adjust verbs/resources.

## OIDC / SSO

See `k8s/kubernetes-dashboard/oidc/README.md` for enabling external identity provider and removing static tokens.

## Remove

```bash
kubectl delete -f k8s/kubernetes-dashboard/
```
