# Multi-Node GitOps Kubernetes Platform

> A self-managed six-node k3s environment for operating stateful services, exercising failure modes, and checking infrastructure tools against interacting network, storage, scheduling, delivery, and recovery systems.

**Status:** Validated · **Type:** Platform · **Domain:** Reliability and operations

This repository is the public home and documentation for the project described in the
[Korab Cenaj portfolio case study](https://korab.space/projects/multi-node-gitops-kubernetes-platform/). Content is
evidence-bounded: what is validated is stated as validated, and open items are listed as
limitations rather than claims.

## Problem

Static examples do not expose the consequences of maintenance, placement, storage locality, controller reconciliation, or partial failure. Those interactions require a multi-node environment with real state and dependencies.

## Solution

The environment combines three control-plane/etcd nodes, two labeled workers, and one integration node with Cilium, Traefik, MetalLB, cert-manager, Longhorn, Flux, Helm, Kustomize, and self-hosted delivery services.

## Architecture

Three server nodes hold control-plane and etcd roles; two workers and one integration node supply application capacity. Flux currently retains a usable artifact and reports one Kustomization plus 12 Helm releases Ready, while its Git source retry exposes an internal service-resolution dependency.

A three-node etcd/control-plane core provides high availability for the Kubernetes API; two worker nodes run platform workloads; a dedicated integration node isolates experimental services. Ingress traffic flows through MetalLB and Traefik to Cilium-networked pods; Longhorn manages distributed block storage across nodes.

1. **GitOps Reconciliation:** FluxCD GitOps controller reconciles desired state from Gitea repository.
2. **Ingress Routing:** MetalLB advertises virtual IPs; Traefik routes inbound HTTP/HTTPS traffic.
3. **Network Policy:** Cilium enforces eBPF-based network policies and handles pod networking.
4. **Persistent Storage:** Longhorn CSI provisions and replicates persistent volumes across worker nodes.
5. **Certificate Automation:** cert-manager automates Let's Encrypt certificate issuance via Cloudflare DNS-01.
6. **Disaster Recovery:** Velero coordinates scheduled backups to local and remote object storage.

## Validation & Evidence

- 6 of 6 nodes Ready on 24 July 2026
- 3 control-plane/etcd nodes, 2 labeled workers, and 1 integration node observed
- Kubernetes v1.36.2+k3s1 on Ubuntu 24.04 observed
- 12 of 12 Flux Helm releases and 1 of 1 Kustomizations Ready
- Flux Git source retained an artifact but was not Ready because its internal source endpoint did not resolve
- 10 of 10 persistent volumes and 10 of 10 claims Bound; the newest node still had an unready Longhorn manager/plugin path
- 8 of 8 cert-manager certificates Ready
- Velero history contained completed critical backups alongside failed or partially failed off-site runs

## Lessons Learned

- Separating "artifact reconciled" from "source healthy" surfaced a real internal DNS/service-resolution issue with the Flux Git source that a simple pass/fail health check would have hidden.
- Longhorn onboarding on a newly added node isn't instant — the lagging manager/plugin path is a reminder to gate stateful scheduling on storage-layer readiness, not just node readiness.
- "A backup job ran" and "a backup job succeeded and landed off-site" are different claims — Velero's mixed history here is exactly the kind of gap that gets missed if only job completion is checked.

## Limitations

- Self-managed home/lab platform, not an employer production system — findings describe behavior at this scale and topology only.
- The published snapshot is point-in-time (24 July 2026), not a standing or continuously monitored health claim.
- The incomplete Longhorn integration on the newest node and the off-site Velero backup failures were open at the time of this snapshot and aren't yet marked resolved in the published record.
- Continuous monitoring, automated alerting on these specific gaps, and a follow-up snapshot after remediation are outside the current published evidence.

## Technologies

Kubernetes, Reliability, Recovery, Automation, Platform

---
See the full case study at [https://korab.space/projects/multi-node-gitops-kubernetes-platform/](https://korab.space/projects/multi-node-gitops-kubernetes-platform/).
