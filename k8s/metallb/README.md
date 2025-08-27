MetalLB for Home Cluster
=========================

Purpose
-------
Provide LoadBalancer IPs inside a bare-metal / home lab so the Kubernetes Dashboard (and future services) get a stable LAN IP instead of relying on NodePort.

What's Included
---------------
1. metallb-install.yaml  - Core MetalLB components (controller + speaker + minimal CRDs) pinned v0.14.5
2. metallb-config.yaml   - AddressPool (192.168.1.240-192.168.1.250) and L2Advertisement
3. (Optional) ingress-loadbalancer-service-patch.yaml - Patches ingress-nginx controller Service to type LoadBalancer and request an IP from the pool.

Quick Start
-----------
# 1. Install MetalLB
kubectl apply -f k8s/metallb/metallb-install.yaml

# 2. Wait for controller & speaker to be Ready
kubectl -n metallb-system get pods

# 3. Apply address pool and L2 advertisement
kubectl apply -f k8s/metallb/metallb-config.yaml

# 4. Patch ingress-nginx controller service (if using ingress for dashboard)
#    (Only after MetalLB components are ready)
kubectl apply -f k8s/kubernetes-dashboard/ingress-loadbalancer-service-patch.yaml

# 5. Confirm external IP assigned
kubectl -n ingress-nginx get svc ingress-nginx-controller

# 6. Add/update LAN DNS or /etc/hosts with the assigned IP for dashboard.home.lan

Security / Notes
----------------
- Ensure 192.168.1.240-250 range is excluded from DHCP to avoid IP conflict.
- MetalLB layer2 mode sends ARP announcements; pick addresses inside your subnet.
- For more CRDs (BGPPeers, Communities, etc.) fetch full upstream manifest.
- Keep components updated: https://github.com/metallb/metallb/releases

Troubleshooting
---------------
1. No external IP: Check speaker DaemonSet pods running on node(s).
2. External IP pending: Confirm CRDs applied and AddressPool + L2Advertisement objects exist.
3. IP conflict warnings in logs: Ensure addresses are not in active DHCP lease.
4. Ingress still unreachable: Verify firewall (ufw) allows the allocated IP and ports 80/443.

Next Steps
----------
- After ingress works, you may delete the NodePort service for the dashboard to reduce exposure.
- Reuse the address pool for other services (create dedicated pools for segmentation if desired).
