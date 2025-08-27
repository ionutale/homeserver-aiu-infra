# OIDC / SSO Enablement Notes

To enable OIDC for the Kubernetes API (so the Dashboard can use external auth instead of static tokens):

1. Choose an identity provider: Keycloak (self-hosted), Authentik, Dex, or a cloud IdP.
2. Configure the API server with flags (varies by your distro, e.g., kubeadm edit /etc/kubernetes/manifests/kube-apiserver.yaml):

```
--oidc-issuer-url=https://auth.home.lan/realms/home
--oidc-client-id=kubernetes-dashboard
--oidc-username-claim=email
--oidc-groups-claim=groups
```

3. Create a client (confidential/public) in the IdP named `kubernetes-dashboard` with redirect URI:
```
https://dashboard.home.lan/
```
   (Dashboard uses token pasting; for full OIDC flow you can front it with a reverse proxy like oauth2-proxy.)

4. Deploy `oauth2-proxy` (or `dex + gangway`) in the cluster, have Ingress route:
```
/dashboard -> oauth2-proxy -> kubernetes-dashboard service
```

5. Configure oauth2-proxy with your IdP client secret and set cookie domain to `.home.lan`.

6. Replace the NodePort exposure with Ingress only. Remove `admin-user` and rely on RBAC tied to OIDC groups.

## Minimal oauth2-proxy Helm values (example skeleton)

```yaml
ingress:
  enabled: true
  className: nginx
  hosts:
    - dashboard.home.lan
  tls:
    - secretName: dashboard-tls
      hosts:
        - dashboard.home.lan
extraArgs:
  provider: oidc
  oidc-issuer-url: https://auth.home.lan/realms/home
  oidc-client-id: kubernetes-dashboard
  oidc-client-secret: <secret>
  cookie-secure: true
  cookie-domain: .home.lan
  upstreams: https://kubernetes-dashboard.kubernetes-dashboard.svc.cluster.local:443
```

Associate RBAC by creating `ClusterRoleBindings` to groups exposed in the ID token (e.g., `k8s-admins`, `k8s-readers`).
