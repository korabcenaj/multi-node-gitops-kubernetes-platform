# Runtime low-power overrides

The low-power profile disables KEDA, Hubble Relay/UI, and the Longhorn UI in
Flux-managed desired state. It also suspends the monitoring, Loki/Promtail, and
Tempo Helm releases before their runtime workloads are scaled to zero. Matrix
keeps its manifests and PVCs but declares zero replicas for PostgreSQL, Synapse,
and Element.

The following workloads require explicit runtime overrides:

- `DaemonSet/kepler/kepler` receives the non-matching node selector
  `power.homelab/disabled=true`. Kepler only exports power telemetry.
- `Deployment/portfolio-dev/portfolio-web` is scaled to zero. It is a
  development workload with no Helm or Flux owner.
- Monitoring deployments, StatefulSets, and the node-exporter DaemonSet are
  scaled to zero after `HelmRelease/monitoring/kube-prometheus-stack` is
  suspended.
- Loki and Promtail are scaled to zero after `HelmRelease/logging/loki` is
  suspended.
- Tempo is scaled to zero after `HelmRelease/tracing/tempo` is suspended.
- `Deployment/semaphore/semaphore` and `StatefulSet/semaphore/postgresql` are
  not owned by Flux and are scaled to zero.

These overrides do not delete workloads or persistent data. Restore them with:

```bash
kubectl patch daemonset kepler -n kepler --type=json \
  -p='[{"op":"remove","path":"/spec/template/spec/nodeSelector/power.homelab~1disabled"}]'
kubectl scale deployment portfolio-web -n portfolio-dev --replicas=1

# Restore Helm-managed observability after removing spec.suspend from the
# three HelmRelease manifests and reconciling Flux.
kubectl scale deployment kps-grafana kps-kube-prometheus-stack-operator \
  kps-kube-state-metrics -n monitoring --replicas=1
kubectl scale statefulset alertmanager-kps-kube-prometheus-stack-alertmanager \
  prometheus-kps-kube-prometheus-stack-prometheus -n monitoring --replicas=1
kubectl patch daemonset kps-prometheus-node-exporter -n monitoring --type=json \
  -p='[{"op":"remove","path":"/spec/template/spec/nodeSelector/power.homelab~1disabled"}]'
kubectl scale statefulset loki -n logging --replicas=1
kubectl patch daemonset loki-promtail -n logging --type=json \
  -p='[{"op":"remove","path":"/spec/template/spec/nodeSelector/power.homelab~1disabled"}]'
kubectl scale statefulset tempo -n tracing --replicas=1

# Restore Matrix after changing its three declared replicas back to 1.

# Restore Semaphore database first, then the application.
kubectl scale statefulset postgresql -n semaphore --replicas=1
kubectl rollout status statefulset/postgresql -n semaphore
kubectl scale deployment semaphore -n semaphore --replicas=1
```

Before enabling KEDA again, re-add `keda.yaml` to
`clusters/homelab/prod/platform/kustomization.yaml` and verify the intended
`ScaledObject` or `ScaledJob` exists.
