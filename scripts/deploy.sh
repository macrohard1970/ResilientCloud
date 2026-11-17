#!/bin/bash
# Lab deploy/destroy helpers
# Usage:
#   ./scripts/deploy.sh        — deploy the full lab
#   ./scripts/deploy.sh destroy — tear down the lab
#   ./scripts/deploy.sh status  — show running containers

set -e

LAB_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TOPO="${LAB_DIR}/topology.clab.yml"
MONITORING_DIR="${LAB_DIR}/monitoring"

case "${1:-deploy}" in

  deploy)
    echo "=== Deploying network lab ==="
    containerlab deploy -t "$TOPO"
    echo ""
    echo "=== Starting monitoring stack ==="
    # Create external networks if they don't exist
    docker network create clab-netlab-services --subnet 10.20.0.0/24 2>/dev/null || true
    docker network create clab-netlab-mgmt 2>/dev/null || true
    cd "$MONITORING_DIR"
    docker compose up -d
    echo ""
    echo "=== Lab deployed ==="
    echo "  Grafana:     http://localhost:3000 (admin/admin)"
    echo "  Prometheus:  http://localhost:9090"
    echo "  Suzieq API:  http://localhost:8000"
    echo "  Batfish:     http://localhost:9000"
    echo ""
    containerlab inspect -t "$TOPO"
    ;;

  destroy)
    echo "=== Stopping monitoring stack ==="
    cd "$MONITORING_DIR"
    docker compose down
    echo ""
    echo "=== Destroying network lab ==="
    containerlab destroy -t "$TOPO" --cleanup
    echo "=== Lab destroyed ==="
    ;;

  status)
    echo "=== Network lab status ==="
    containerlab inspect -t "$TOPO"
    echo ""
    echo "=== Monitoring containers ==="
    cd "$MONITORING_DIR"
    docker compose ps
    ;;

  *)
    echo "Usage: $0 {deploy|destroy|status}"
    exit 1
    ;;
esac
