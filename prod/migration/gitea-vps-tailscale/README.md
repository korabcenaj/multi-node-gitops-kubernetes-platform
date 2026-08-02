# Gitea VPS tailnet egress — staged migration resources

These resources are intentionally not referenced by the production root
Kustomization yet. They are split into two gates because `ProxyGroup` cannot be
created until the Operator CRDs exist.

1. Merge and validate the tailnet tags/grants. Pre-create the mode-protected
   `tailscale/operator-oauth` Secret out of band with keys `client_id` and
   `client_secret`; never add those values here.
2. Add `operator/` to a reviewed Flux Kustomization, reconcile, and wait for the
   HelmRelease and Operator to become Ready.
3. Add `egress/` only after the `ProxyGroup` CRD exists. Wait for
   `ProxyGroupReady=true` and `TailscaleEgressSvcReady=true`.
4. Apply the exact CoreDNS override and the coordinated Flux/runner/BuildKit
   changes only after the VPS certificate and private listener are healthy.

The cluster runs Cilium kube-proxy replacement, but `bpf-lb-sock` is currently
false. The Tailscale compatibility warning for socket load-balancer bypass is
therefore not triggered. The namespace has no Pod Security enforcement label;
the official egress proxies use privileged containers by default. Do not relax
security in other namespaces.

Rollback removes the CoreDNS custom ConfigMap entry, restores the in-cluster
Flux URL and both hostAliases, then removes the egress Service/ProxyGroup. The
Operator itself can remain installed while troubleshooting, or be removed in a
separate reviewed change after no managed resources remain.
