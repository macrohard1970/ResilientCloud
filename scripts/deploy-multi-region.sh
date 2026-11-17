#!/usr/bin/env bash
# Multi-region deploy/destroy helpers. Run on the region's EC2 lab host.
#
# Usage:
#   scripts/deploy-multi-region.sh deploy  <region>   lab + core monitoring (+ GRE NAT if REMOTE_* set)
#   scripts/deploy-multi-region.sh destroy <region>
#   scripts/deploy-multi-region.sh status  <region>
#   scripts/deploy-multi-region.sh deploy-all | destroy-all   all regions on ONE host
#                                                             (demo only: no WAN between them)
# Regions: dc-east, dc-west, dc-eu (default dc-east)
#
# Cross-region WAN: export the other regions' lab host private IPs first, e.g. on dc-east:
#   export REMOTE_WEST=10.1.2.x REMOTE_EU=10.2.2.x
#
# Monitoring extras: MON_PROFILES="batfish dns" scripts/deploy-multi-region.sh deploy dc-east

set -euo pipefail

LAB_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MONITORING_DIR="${LAB_DIR}/monitoring"
REGIONS=(dc-east dc-west dc-eu)

declare -A TOPOLOGY=(
  [dc-east]="topology-dc-east.clab.yml"
  [dc-west]="topology-dc-west.clab.yml"
  [dc-eu]="topology-dc-eu.clab.yml"
)

check_region() {
  [[ -n "${TOPOLOGY[$1]:-}" ]] || { echo "Unknown region '$1' (use: ${REGIONS[*]})" >&2; exit 1; }
}

compose() {  # region args...
  local region="$1"; shift
  local profiles=()
  for p in ${MON_PROFILES:-}; do profiles+=(--profile "$p"); done
  (cd "$MONITORING_DIR" && docker compose --env-file "env/${region}.env" "${profiles[@]}" "$@")
}

deploy_region() {
  local region="$1" topo="${LAB_DIR}/${TOPOLOGY[$1]}"
  echo "=== Deploying ${region} (${TOPOLOGY[$region]}) ==="
  [[ -x "${LAB_DIR}/bin/frr_exporter" ]] || echo "  note: bin/frr_exporter missing; run scripts/fetch-frr-exporter.sh for metrics"
  # Containerlab creates the management network with the subnet from the topology.
  sudo -E containerlab deploy -t "$topo" --reconfigure

  if env | grep -q '^REMOTE_[A-Z]*=.\+'; then
    sudo "${LAB_DIR}/scripts/gre-nat.sh" "$region" up
  else
    echo "  REMOTE_* not set: WAN tunnels skipped (region runs standalone)"
  fi

  echo "=== Starting ${region} monitoring ==="
  compose "$region" up -d
  sudo containerlab inspect -t "$topo"
}

destroy_region() {
  local region="$1" topo="${LAB_DIR}/${TOPOLOGY[$1]}"
  echo "=== Destroying ${region} ==="
  MON_PROFILES="suzieq batfish dns" compose "$region" down || true
  sudo "${LAB_DIR}/scripts/gre-nat.sh" "$region" down || true
  sudo containerlab destroy -t "$topo" --cleanup
}

status_region() {
  local region="$1"
  sudo containerlab inspect -t "${LAB_DIR}/${TOPOLOGY[$region]}" || true
  MON_PROFILES="suzieq batfish dns" compose "$region" ps
}

ACTION="${1:-}"; REGION="${2:-dc-east}"
case "$ACTION" in
  deploy)   check_region "$REGION"; deploy_region "$REGION" ;;
  destroy)  check_region "$REGION"; destroy_region "$REGION" ;;
  status)   check_region "$REGION"; status_region "$REGION" ;;
  deploy-all)  for r in "${REGIONS[@]}"; do deploy_region "$r"; done ;;
  destroy-all) for r in "${REGIONS[@]}"; do destroy_region "$r"; done ;;
  *)
    sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
    exit 1 ;;
esac
