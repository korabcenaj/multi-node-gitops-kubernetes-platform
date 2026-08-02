#!/usr/bin/env bash
# Longhorn Scheduling Policy — Apply Node Tags and Scheduling Rules
# =================================================================
# SAFE SCRIPT: Does NOT delete volumes, PVCs, or PVs.
# Only modifies Longhorn node CRs (tags, scheduling, eviction).
#
# Intended Node Roles:
#   control1: always-on, critical storage (with control2)
#   control2: always-on, critical storage (with control1)
#   control3: TEMPORARY — Longhorn scheduling DISABLED, replicas evicted
#   worker:   BULK ONLY — 3 TB HDD for offline/non-critical storage
#
# Run: bash longhorn-scheduling-policy.sh
# =================================================================

set -euo pipefail

NAMESPACE="longhorn-system"

echo "=============================================="
echo "Longhorn Scheduling Policy — Apply Node Tags"
echo "=============================================="
echo ""
echo "⚠️  SAFETY: This script does NOT delete any volumes, PVCs, or PVs."
echo "   It only modifies Longhorn node scheduling and eviction settings."
echo ""

# -------------------------------------------------------------------
# 1. Tag always-on Longhorn nodes for critical storage
# -------------------------------------------------------------------
echo "--- [1/6] Tagging always-on nodes (control1, control2) for critical storage ---"

kubectl -n "${NAMESPACE}" patch node.longhorn.io control1 --type='merge' \
  -p '{"spec":{"tags":["always-on","critical"]}}' 2>/dev/null \
  && echo "  ✓ control1 tagged: always-on, critical" \
  || echo "  ⚠️  control1: node.longhorn.io not found or patch failed (may need manual setup)"

kubectl -n "${NAMESPACE}" patch node.longhorn.io control2 --type='merge' \
  -p '{"spec":{"tags":["always-on","critical"]}}' 2>/dev/null \
  && echo "  ✓ control2 tagged: always-on, critical" \
  || echo "  ⚠️  control2: node.longhorn.io not found or patch failed (may need manual setup)"

# -------------------------------------------------------------------
# 2. Tag worker nodes for bulk storage only
# -------------------------------------------------------------------
echo "--- [2/6] Tagging worker nodes (worker, worker2) for bulk storage only ---"

for w_node in worker worker2; do
  kubectl -n "${NAMESPACE}" patch node.longhorn.io "$w_node" --type='merge' \
    -p '{"spec":{"tags":["bulk"]}}' 2>/dev/null \
    && echo "  ✓ $w_node tagged: bulk" \
    || echo "  ⚠️  $w_node: node.longhorn.io not found or patch failed (may need manual setup)"
done

# -------------------------------------------------------------------
# 3. Tag workers' disks for bulk storage
# -------------------------------------------------------------------
echo "--- [3/6] Tagging worker disks with 'bulk' tag ---"

for w_node in worker worker2; do
  DISK_IDS=$(kubectl -n "${NAMESPACE}" get node.longhorn.io "$w_node" -o json 2>/dev/null | jq -r '.spec.disks | keys[]' 2>/dev/null || echo "")
  if [[ -n "${DISK_IDS}" ]]; then
    for DISK_ID in ${DISK_IDS}; do
      kubectl -n "${NAMESPACE}" patch node.longhorn.io "$w_node" --type='json' \
        -p="[{\"op\":\"replace\",\"path\":\"/spec/disks/${DISK_ID}/tags\",\"value\":[\"bulk\",\"hdd\"]}]" 2>/dev/null \
        && echo "  ✓ $w_node disk ${DISK_ID} tagged: bulk, hdd" \
        || echo "  ⚠️  $w_node disk ${DISK_ID}: tag update failed"
    done
  else
    echo "  ⚠️  $w_node: no disks found or node.longhorn.io not available"
  fi
done

# -------------------------------------------------------------------
# 4. Tag control3 as temporary, disable scheduling
# -------------------------------------------------------------------
echo "--- [4/6] Disabling Longhorn scheduling on control3 (temporary node) ---"

kubectl -n "${NAMESPACE}" patch node.longhorn.io control3 --type='merge' \
  -p '{"spec":{"allowScheduling":false,"tags":["temporary"]}}' 2>/dev/null \
  && echo "  ✓ control3: allowScheduling=false, tags=temporary" \
  || echo "  ⚠️  control3: node.longhorn.io not found or patch failed (may need manual setup)"

# Disable scheduling on ALL disks of control3
DISK_IDS=$(kubectl -n "${NAMESPACE}" get node.longhorn.io control3 -o json 2>/dev/null | jq -r '.spec.disks | keys[]' 2>/dev/null || echo "")
if [[ -n "${DISK_IDS}" ]]; then
  for DISK_ID in ${DISK_IDS}; do
    kubectl -n "${NAMESPACE}" patch node.longhorn.io control3 --type='json' \
      -p="[{\"op\":\"replace\",\"path\":\"/spec/disks/${DISK_ID}/allowScheduling\",\"value\":false}]" 2>/dev/null \
      && echo "  ✓ control3 disk ${DISK_ID}: allowScheduling=false" \
      || echo "  ⚠️  control3 disk ${DISK_ID}: scheduling disable failed"
  done
fi

# -------------------------------------------------------------------
# 5. Evict existing replicas from control3
# -------------------------------------------------------------------
echo "--- [5/6] Requesting eviction of replicas from control3 ---"
echo "  ⚠️  This is SAFE: Longhorn will rebuild replicas on always-on nodes."
echo "  No volumes, PVCs, or PVs are deleted."

kubectl -n "${NAMESPACE}" patch node.longhorn.io control3 --type='merge' \
  -p '{"spec":{"evictionRequested":true}}' 2>/dev/null \
  && echo "  ✓ control3: evictionRequested=true (monitor with: watch kubectl -n longhorn-system get replicas.longhorn.io -o wide)" \
  || echo "  ⚠️  control3: eviction request failed (node may not exist)"

# -------------------------------------------------------------------
# 6. Ensure scheduling is enabled on always-on nodes
# -------------------------------------------------------------------
echo "--- [6/6] Ensuring Longhorn scheduling enabled on always-on nodes ---"

kubectl -n "${NAMESPACE}" patch node.longhorn.io control1 --type='merge' \
  -p '{"spec":{"allowScheduling":true,"evictionRequested":false}}' 2>/dev/null \
  && echo "  ✓ control1: allowScheduling=true" \
  || echo "  ⚠️  control1: scheduling enable failed"

kubectl -n "${NAMESPACE}" patch node.longhorn.io control2 --type='merge' \
  -p '{"spec":{"allowScheduling":true,"evictionRequested":false}}' 2>/dev/null \
  && echo "  ✓ control2: allowScheduling=true" \
  || echo "  ⚠️  control2: scheduling enable failed"

# -------------------------------------------------------------------
# 7. Add NVMe disks to always-on nodes
# -------------------------------------------------------------------
echo "--- [7/7] Adding NVMe disks to always-on nodes (control1, control2) ---"

for ctrl_node in control1 control2; do
  # Check if nvme-disk is already present in spec.disks
  EXISTING_DISKS=$(kubectl -n "${NAMESPACE}" get node.longhorn.io "${ctrl_node}" -o jsonpath='{.spec.disks}' 2>/dev/null || echo "")
  if [[ "${EXISTING_DISKS}" != *"nvme-disk"* ]]; then
    kubectl -n "${NAMESPACE}" patch node.longhorn.io "${ctrl_node}" --type='json' \
      -p='[{"op":"add","path":"/spec/disks/nvme-disk","value":{"allowScheduling":true,"diskType":"filesystem","path":"/var/lib/longhorn-nvme","storageReserved":0,"tags":["nvme","ssd","fast"]}}]' 2>/dev/null \
      && echo "  ✓ ${ctrl_node}: nvme-disk added at /var/lib/longhorn-nvme" \
      || echo "  ⚠️  ${ctrl_node}: failed to add nvme-disk"
  else
    echo "  ✓ ${ctrl_node}: nvme-disk already configured"
  fi
done

# -------------------------------------------------------------------
# Summary
# -------------------------------------------------------------------
echo ""
echo "=============================================="
echo "Longhorn Scheduling Policy — Complete"
echo "=============================================="
echo ""
echo "Node Summary:"
echo "  control1: always-on, critical storage  (allowScheduling=true, disks: default, nvme)"
echo "  control2: always-on, critical storage  (allowScheduling=true, disks: default, nvme)"
echo "  control3: TEMPORARY                   (allowScheduling=false, evictionRequested=true)"
echo "  worker:   BULK ONLY                   (allowScheduling=true, disks tagged: bulk)"
echo ""
echo "Validate with:"
echo "  kubectl -n longhorn-system get nodes.longhorn.io -o wide"
echo "  kubectl -n longhorn-system get replicas.longhorn.io -o wide"
echo "  kubectl -n longhorn-system get volumes.longhorn.io -o wide"
echo ""
echo "⚠️  MANUAL CONFIRMATION REQUIRED:"
echo "  1. Verify nvme-disk is added to control1 and control2."
echo "  2. Verify no replicas remain on control3 after eviction completes."
echo "  3. Verify all critical volumes have healthy replicas on control1 or control2."
echo "  4. If replicas are stuck on control3 after 10 minutes, manually inspect:"
echo "     kubectl -n longhorn-system describe replicas.longhorn.io | grep -A5 control3"
