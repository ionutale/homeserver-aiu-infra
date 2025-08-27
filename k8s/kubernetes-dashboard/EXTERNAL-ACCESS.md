External Access Options
=======================

Goal: Reach the Kubernetes Dashboard from any device on the home LAN via https://dashboard.home.lan/

Option A: NodePort (Already Present)
------------------------------------
Service: kubernetes-dashboard-nodeport (port 32443)
Pros: Simple, no extra components.
Cons: High port, self-signed cert mismatch, must remember port, NetworkPolicy must allow traffic.

Test:
  curl -k https://<node-ip>:32443/ -o /dev/null -w '%{http_code}\n'

Option B: Ingress + MetalLB (Recommended)
-----------------------------------------
1. Install MetalLB (L2 mode) using manifests in k8s/metallb/
2. Patch ingress-nginx controller service to LoadBalancer.
3. Ingress (k8s/kubernetes-dashboard/ingress.yaml) serves dashboard.home.lan on 443 with TLS secret dashboard-tls.
4. Add DNS or /etc/hosts entry: <LB-IP> dashboard.home.lan

Advantages: Clean hostname, standard 443 port, TLS terminates at ingress.

Verification Steps:
  kubectl -n ingress-nginx get svc ingress-nginx-controller  # shows EXTERNAL-IP
  curl -k https://dashboard.home.lan/ -H 'Host: dashboard.home.lan' -o /dev/null -w '%{http_code}\n'

Option C: Port-Forward (Fallback / Temporary)
--------------------------------------------
  kubectl -n kubernetes-dashboard port-forward svc/kubernetes-dashboard 8443:443
Then visit https://localhost:8443/
Not suitable for LAN-wide access.

Migration Plan (NodePort -> Ingress)
------------------------------------
1. Ensure Dashboard works internally (port-forward test).
2. Deploy MetalLB & configure pool.
3. Patch ingress-nginx controller service to LoadBalancer.
4. Update local DNS/hosts for dashboard.home.lan.
5. Test HTTPS access.
6. Delete NodePort service when satisfied:
   kubectl -n kubernetes-dashboard delete svc kubernetes-dashboard-nodeport

Firewall Considerations
-----------------------
- Allow inbound TCP 80/443 on the node for the LoadBalancer IP.
- If using ufw: sudo ufw allow 80/tcp; sudo ufw allow 443/tcp

Troubleshooting Matrix
----------------------
Symptom: NodePort timeout
  - Check: NetworkPolicy allows ingress; pod ready; kube-proxy running.
Symptom: Ingress Pending External IP
  - Check: MetalLB speaker running; AddressPool + L2Advertisement exist.
Symptom: TLS browser warning
  - Self-signed cert via cert-manager; optionally replace with real CA if internal PKI.
Symptom: 404 from ingress
  - Check: Host header matches dashboard.home.lan and ingress rules.

Security Hardening
------------------
- Remove admin-user after initial validation.
- Keep least-privilege ServiceAccount tokens short-lived; rotate if stored.
- Consider enabling OIDC and disabling token login in dashboard settings.
