# Node Labels & Taints — Power Optimization

This file documents required node labels and taints for the power-optimization
design. These are applied ONCE manually (or via bootstrap script) and are NOT
managed by Flux GitOps — labels/taints are cluster-level node configuration.

## Current Cluster Nodes

| Node | Role | Power Policy | Storage Policy |
|---|---|---|---|
| `control1` | control-plane | **on-demand shutdown** | critical DB replicas |
| `control2` | control-plane | **on-demand shutdown** | critical DB replicas |
| `control3` | control-plane | **on-demand shutdown** | **NO critical storage** |
| `worker` | worker | **on-demand shutdown** | **bulk/offline only** (3 TB HDD) |

control1 + control2 = 2 control-plane nodes online → etcd quorum maintained.

## ⚠️ ETCD QUORUM

To maintain etcd quorum, you must shut down the nodes in a specific sequence using `scripts/shutdown-cluster.sh`. This script gracefully stops `k3s` on `control3`, then `control2`, and finally `control1` so etcd flushes to disk properly. Do NOT abruptly power off all nodes simultaneously.

---

## Label Scheme 1: Pod Scheduling (power.homelab/*)

Used by Flux Kustomize affinity patches to pin workloads to nodes.

### Labels

Apply to nodes using kubectl:

```bash
# Always-on nodes (control1, control2)
kubectl label node control1 power.homelab/always-on=true --overwrite
kubectl label node control1 workload.homelab/tier=critical --overwrite
kubectl label node control1 storage.longhorn.io/enabled=true --overwrite

kubectl label node control2 power.homelab/always-on=true --overwrite
kubectl label node control2 workload.homelab/tier=critical --overwrite
kubectl label node control2 storage.longhorn.io/enabled=true --overwrite

# Nightly-off nodes
kubectl label node control3 power.homelab/nightly-off=true --overwrite
kubectl label node control3 workload.homelab/tier=standard --overwrite
kubectl label node control3 storage.longhorn.io/enabled=true --overwrite

kubectl label node worker power.homelab/nightly-off=true --overwrite
kubectl label node worker workload.homelab/tier=standard --overwrite
kubectl label node worker storage.longhorn.io/enabled=true --overwrite
```

### Taints

Apply to the always-on node to repel non-critical workloads:

```bash
# Critical-only taint on control1
# Only pods with matching toleration can schedule here
kubectl taint node control1 power.homelab/critical-only=true:NoSchedule --overwrite

# Optional: also taint control2 to reserve it primarily for critical workloads
# kubectl taint node control2 power.homelab/critical-only=true:NoSchedule --overwrite
```

---

## Label Scheme 2: Longhorn Storage Policy (node-role.korab.local/*)

Used by Longhorn StorageClass `nodeSelector` and `diskSelector` parameters
to control WHERE Longhorn replicas are placed.

**Critical rule: `worker` and `control3` MUST NOT host critical live database replicas.**

### Node Labels

```bash
# --- Always-on nodes: critical database storage ONLY ---
kubectl label node control1 node-role.korab.local/always-on=true --overwrite
kubectl label node control2 node-role.korab.local/always-on=true --overwrite

# --- Worker: bulk/offline storage only (3 TB HDD) ---
kubectl label node worker node-role.korab.local/bulk-storage=true --overwrite

# --- control3: temporary/shutdown-capable, NO critical storage ---
kubectl label node control3 node-role.korab.local/temporary=true --overwrite
```

### Longhorn Node Tags (for StorageClass nodeSelector)

These are applied to Longhorn node CRs, NOT Kubernetes node objects:

```bash
# Tag always-on Longhorn nodes for critical storage
kubectl -n longhorn-system patch node.longhorn.io control1 --type='merge' \
  -p '{"spec":{"tags":["always-on","critical"]}}'

kubectl -n longhorn-system patch node.longhorn.io control2 --type='merge' \
  -p '{"spec":{"tags":["always-on","critical"]}}'

# Tag worker node for bulk storage only
kubectl -n longhorn-system patch node.longhorn.io worker --type='merge' \
  -p '{"spec":{"tags":["bulk"]}}'

# control3: NO storage tags (or tag as temporary/no-critical)
kubectl -n longhorn-system patch node.longhorn.io control3 --type='merge' \
  -p '{"spec":{"tags":["temporary"]}}'
```

### Longhorn Disk Tags (for StorageClass diskSelector)

Worker's 3 TB HDD should be tagged for bulk use only:

```bash
# List disks on worker to find the HDD disk ID
kubectl -n longhorn-system get node.longhorn.io worker -o json | jq '.spec.disks'

# Tag the worker's HDD (replace <disk-id> with actual disk ID, e.g. "default-disk-xxxxx")
kubectl -n longhorn-system patch node.longhorn.io worker --type='json' \
  -p='[{"op":"replace","path":"/spec/disks/<disk-id>/tags","value":["bulk","hdd"]}]'

# Control1/Control2 disks tagged for critical storage
kubectl -n longhorn-system patch node.longhorn.io control1 --type='json' \
  -p='[{"op":"replace","path":"/spec/disks/<disk-id>/tags","value":["always-on","critical","ssd"]}]'
```

### Disable Longhorn Scheduling on control3

```bash
# Prevent Longhorn from scheduling ANY replicas on control3
kubectl -n longhorn-system patch node.longhorn.io control3 --type='merge' \
  -p '{"spec":{"allowScheduling":false,"evictionRequested":true}}'

# Also disable scheduling on all disks of control3
kubectl -n longhorn-system get node.longhorn.io control3 -o json | jq '.spec.disks | keys[]' | while read disk; do
  kubectl -n longhorn-system patch node.longhorn.io control3 --type='json' \
    -p="[{\"op\":\"replace\",\"path\":\"/spec/disks/$disk/allowScheduling\",\"value\":false}]"
done
```

### Evict Existing Replicas from control3

```bash
# This is SAFE — it only requests eviction, Longhorn rebuilds replicas elsewhere.
# It does NOT delete volumes, PVCs, or PVs.
kubectl -n longhorn-system patch node.longhorn.io control3 --type='merge' \
  -p '{"spec":{"evictionRequested":true}}'

# Monitor eviction progress
watch kubectl -n longhorn-system get replicas.longhorn.io -o wide
```

---

## Summary

| Label | Scheme | Purpose |
|---|---|---|
| `power.homelab/always-on=true` | Pod Scheduling | Node stays online 24/7 (pod affinity) |
| `power.homelab/nightly-off=true` | Pod Scheduling | Node may be shut down nightly |
| `workload.homelab/tier` | Pod Scheduling | `critical`, `standard`, or `batch` |
| `storage.longhorn.io/enabled=true` | Pod Scheduling | Node participates in Longhorn storage |
| `node-role.korab.local/always-on=true` | Storage Policy | Longhorn critical storage node |
| `node-role.korab.local/bulk-storage=true` | Storage Policy | Longhorn bulk/offline storage only |
| `node-role.korab.local/temporary=true` | Storage Policy | Temporary node, no critical storage |

| Taint | Effect |
|---|---|
| `power.homelab/critical-only=true:NoSchedule` | Only critical pods (with toleration) schedule on this node |

---

## Safe Shutdown Procedure (control3 + worker)

Before shutting down `control3` or `worker`:

1. Verify no critical workloads are scheduled on these nodes.
2. Verify Longhorn volumes are healthy:
   ```bash
   kubectl -n longhorn-system get volumes.longhorn.io -o wide
   ```
3. Cordon the node: `kubectl cordon <node>`
4. Evict non-DaemonSet pods: `kubectl drain <node> --ignore-daemonsets --delete-emptydir-data`
5. Shut down the node.

---

## Verification

```bash
# Check Kubernetes node labels
kubectl get nodes -o custom-columns=NAME:.metadata.name,LABELS:.metadata.labels

# Check taints
kubectl get nodes -o custom-columns=NAME:.metadata.name,TAINTS:.spec.taints

# Check Longhorn node scheduling
kubectl -n longhorn-system get nodes.longhorn.io -o wide

# Check Longhorn node tags
kubectl -n longhorn-system get nodes.longhorn.io -o json | jq '.items[] | {name: .metadata.name, tags: .spec.tags, allowScheduling: .spec.allowScheduling, evictionRequested: .spec.evictionRequested}'

# Verify critical pods are on always-on node
kubectl get pods -A -o wide --field-selector spec.nodeName=control1

# Verify NO critical DB pods on worker or control3
kubectl get pods -n git -o wide | grep -E 'worker|control3'
```
