#!/usr/bin/env bash
# Single-region lab (topology.clab.yml: DC-East fabric without the WAN edge).
#
# Usage:
#   scripts/deploy.sh [deploy]   lab + Prometheus/Grafana
#   scripts/deploy.sh destroy
#   scripts/deploy.sh status
#
# Uses the same device names, management network and monitoring settings as
# dc-east, so run either this or topology-dc-east.clab.yml, not both.

set -euo pipefail

LAB_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TOPO="${LAB_DIR}/topology.clab.yml"
compose() { (cd "${LAB_DIR}/monitoring" && docker compose --env-file env/dc-east.env "$@"); }

case "${1:-deploy}" in
  deploy)
    [[ -x "${LAB_DIR}/bin/frr_exporter" ]] || echo "note: run scripts/fetch-frr-exporter.sh for FRR metrics"
    sudo containerlab deploy -t "$TOPO" --reconfigure
    compose up -d
    echo "Grafana http://localhost:3000  Prometheus http://localhost:9090 (via SSH tunnel)"
    sudo containerlab inspect -t "$TOPO"
    ;;
  destroy)
    compose --profile suzieq --profile batfish --profile dns down || true
    sudo containerlab destroy -t "$TOPO" --cleanup
    ;;
  status)
    sudo containerlab inspect -t "$TOPO" || true
    compose ps
    ;;
  *) echo "Usage: $0 {deploy|destroy|status}"; exit 1 ;;
esac
