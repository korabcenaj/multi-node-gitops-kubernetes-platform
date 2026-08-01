# Multi-Node GitOps Kubernetes Platform

> A self-managed six-node k3s environment for operating stateful services, exercising failure modes, and checking infrastructure tools against interacting network, storage, scheduling, delivery, and recovery systems.

**Status:** Validated · **Type:** Platform · **Domain:** 

This repository is the public home and documentation for the project described in the
[Korab Cenaj portfolio case study](https://korab.space/projects/multi-node-gitops-kubernetes-platform.html). Content is
evidence-bounded: what is validated is stated as validated, and open items are listed as
limitations rather than claims.

## Problem

Static examples do not expose the consequences of maintenance, placement, storage locality, controller reconciliation, or partial failure. Those interactions require a multi-node environment with real state and dependencies.

## Solution

The environment combines three control-plane/etcd nodes, two labeled workers, and one integration node with Cilium, Traefik, MetalLB, cert-manager, Longhorn, Flux, Helm, Kustomize, and self-hosted delivery services.

## Architecture

Three server nodes hold control-plane and etcd roles; two workers and one integration node supply application capacity. Flux currently retains a usable artifact and reports one Kustomization plus 12 Helm releases Ready, while its Git source retry exposes an internal service-resolution dependency.

_None._

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

_None._

## Limitations

_None._

## Technologies

Kubernetes, Reliability, Recovery, Automation, Platform

---
See the full case study at [https://korab.space/projects/multi-node-gitops-kubernetes-platform.html](https://korab.space/projects/multi-node-gitops-kubernetes-platform.html).
