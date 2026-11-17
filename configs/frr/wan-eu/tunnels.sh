#!/bin/sh
# GRE tunnel setup — wan-eu (DC-EU)
# Creates GRE tunnel interfaces to DC-East and DC-West wan-edge routers.
#
# Environment variables:
#   LOCAL_IP     — this EC2 host's VPC private IP (GRE source)
#   REMOTE_EAST  — DC-East EC2 host's VPC private IP (GRE dest)
#   REMOTE_WEST  — DC-West EC2 host's VPC private IP (GRE dest)
#
# Tunnel IPs:
#   tun-east: 10.110.0.6/30 (remote: 10.110.0.5 on wan-east)
#   tun-west: 10.110.0.10/30 (remote: 10.110.0.9 on wan-west)

set -e

if ! command -v ip >/dev/null 2>&1; then
  apk add --no-cache iproute2 2>/dev/null || apt-get install -y iproute2 2>/dev/null
fi

# Create GRE tunnel to DC-East
if [ -n "$REMOTE_EAST" ]; then
  ip tunnel del tun-east 2>/dev/null || true
  ip tunnel add tun-east mode gre local "$LOCAL_IP" remote "$REMOTE_EAST" ttl 64
  ip link set tun-east up
  echo "Created GRE tunnel tun-east: $LOCAL_IP -> $REMOTE_EAST"
else
  echo "WARNING: REMOTE_EAST not set - tun-east not created"
fi

# Create GRE tunnel to DC-West
if [ -n "$REMOTE_WEST" ]; then
  ip tunnel del tun-west 2>/dev/null || true
  ip tunnel add tun-west mode gre local "$LOCAL_IP" remote "$REMOTE_WEST" ttl 64
  ip link set tun-west up
  echo "Created GRE tunnel tun-west: $LOCAL_IP -> $REMOTE_WEST"
else
  echo "WARNING: REMOTE_WEST not set - tun-west not created"
fi
