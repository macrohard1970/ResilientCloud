#!/bin/bash
# Multi-region deploy/destroy helpers
# Usage:
#   ./scripts/deploy-multi-region.sh deploy [region]   — deploy a region's lab
#   ./scripts/deploy-multi-region.sh destroy [region]  — tear down a region's lab
#   ./scripts/deploy-multi-region.sh status [region]   — show running containers
#   ./scripts/deploy-multi-region.sh deploy-all         — deploy all 3 regions
#   ./scripts/deploy-multi-region.sh destroy-all        — tear down all regions
#
# Region names: dc-east, dc-west, dc-eu
# If no region specified for deploy/destroy/status, defaults to dc-east.

set -e

LAB_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MONITORING_DIR="${LAB_DIR}/monitoring"

# ── Region topology mapping ──────────────────────────────────────────
declare -A TOPOLOGY
TOPOLOGY[dc-east]="topology-dc-east.clab.yml"
TOPOLOGY[dc-west]="topology-dc-west.clab.yml"
TOPOLOGY[dc-eu]="topology-dc-eu.clab.yml"

# ── Management networks per region ───────────────────────────────────
declare -A MGMT_NET
MGMT_NET[dc-east]="clab-netlab-east-mgmt"
MGMT_NET[dc-west]="clab-netlab-west-mgmt"
MGMT_NET[dc-eu]="clab-netlab-eu-mgmt"

declare -A SERVICES_NET
SERVICES_NET[dc-east]="clab-netlab-east-services"
SERVICES_NET[dc-west]="clab-netlab-west-services"
SERVICES_NET[dc-eu]="clab-netlab-eu-services"

declare -A SERVICES_SUBNET
SERVICES_SUBNET[dc-east]="10.20.0.0/24"
SERVICES_SUBNET[dc-west]="10.21.0.0/24"
SERVICES_SUBNET[dc-eu]="10.22.0.0/24"

# ── Helper functions ─────────────────────────────────────────────────
get_topo() {
  local region="$1"
  echo "${LAB_DIR}/${TOPOLOGY[$region]:-topology-dc-east.clab.yml}"
}

deploy_region() {
  local region="$1"
  local topo
  topo=$(get_topo "$region")

  echo "=== Deploying ${region} network lab ==="
  echo "  Topology: ${TOPOLOGY[$region]}"

  # Create Docker networks if they don't exist
  docker network create "${MGMT_NET[$region]}" 2>/dev/null || true
  docker network create "${SERVICES_NET[$region]}" --subnet "${SERVICES_SUBNET[$region]}" 2>/dev/null || true

  containerlab deploy -t "$topo"

  echo ""
  echo "=== Starting ${region} monitoring stack ==="
  cd "$MONITORING_DIR"
  docker compose up -d

  echo ""
  echo "=== ${region} lab deployed ==="
  echo "  Grafana:     http://localhost:3000 (admin/admin)"
  echo "  Prometheus:  http://localhost:9090"
  echo "  Suzieq API:  http://localhost:8000"
  echo "  Batfish:     http://localhost:9000"
  echo ""
  containerlab inspect -t "$topo"
}

destroy_region() {
  local region="$1"
  local topo
  topo=$(get_topo "$region")

  echo "=== Stopping ${region} monitoring stack ==="
  cd "$MONITORING_DIR"
  docker compose down 2>/dev/null || true

  echo ""
  echo "=== Destroying ${region} network lab ==="
  containerlab destroy -t "$topo" --cleanup

  echo "=== ${region} lab destroyed ==="
}

status_region() {
  local region="$1"
  local topo
  topo=$(get_topo "$region")

  echo "=== ${region} network lab status ==="
  containerlab inspect -t "$topo"
  echo ""
  echo "=== ${region} monitoring containers ==="
  cd "$MONITORING_DIR"
  docker compose ps
}

# ── Main ─────────────────────────────────────────────────────────────
ACTION="${1:-deploy}"
REGION="${2:-dc-east}"

case "$ACTION" in
  deploy)
    deploy_region "$REGION"
    ;;

  destroy)
    destroy_region "$REGION"
    ;;

  status)
    status_region "$REGION"
    ;;

  deploy-all)
    for r in dc-east dc-west dc-eu; do
      deploy_region "$r"
      echo ""
      echo "--------------------------------------------------------"
      echo ""
    done
    echo "=== All 3 regions deployed ==="
    echo "Verify cross-region connectivity:"
    echo "  docker exec clab-netlab-east-host-a ping 10.11.1.1  # East -> West"
    echo "  docker exec clab-netlab-east-host-a ping 10.12.1.1  # East -> EU"
    echo "  docker exec clab-netlab-west-host-a ping 10.12.1.1  # West -> EU"
    ;;

  destroy-all)
    for r in dc-east dc-west dc-eu; do
      destroy_region "$r"
      echo ""
    done
    echo "=== All 3 regions destroyed ==="
    ;;

  *)
    echo "Usage: $0 {deploy|destroy|status|deploy-all|destroy-all} [region]"
    echo ""
    echo "Regions: dc-east, dc-west, dc-eu (default: dc-east)"
    echo ""
    echo "Commands:"
    echo "  deploy [region]    Deploy a single region's lab + monitoring"
    echo "  destroy [region]   Tear down a single region's lab + monitoring"
    echo "  status [region]     Show running containers for a region"
    echo "  deploy-all          Deploy all 3 regions"
    echo "  destroy-all         Tear down all 3 regions"
    exit 1
    ;;
esac
