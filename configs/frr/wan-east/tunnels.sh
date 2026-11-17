#!/bin/sh
# GRE tunnel setup — wan-east (DC-East)
# Creates GRE tunnel interfaces to DC-West and DC-EU wan-edge routers.
#
# Environment variables (set by deploy script or Containerlab env):
#   LOCAL_IP     — this EC2 host's VPC private IP (GRE source)
#   REMOTE_WEST  — DC-West EC2 host's VPC private IP (GRE dest)
#   REMOTE_EU    — DC-EU EC2 host's VPC private IP (GRE dest)
#
# Tunnel IPs:
#   tun-west: 10.110.0.1/30 (remote: 10.110.0.2 on wan-west)
#   tun-eu:   10.110.0.5/30 (remote: 10.110.0.6 on wan-eu)

set -e

# Ensure ip command is available
if ! command -v ip >/dev/null 2>&1; then
  apk add --no-cache iproute2 2>/dev/null || apt-get install -y iproute2 2>/dev/null
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

# Create GRE tunnel to DC-EU
if [ -n "$REMOTE_EU" ]; then
  ip tunnel del tun-eu 2>/dev/null || true
  ip tunnel add tun-eu mode gre local "$LOCAL_IP" remote "$REMOTE_EU" ttl 64
  ip link set tun-eu up
  echo "Created GRE tunnel tun-eu: $LOCAL_IP -> $REMOTE_EU"
else
  echo "WARNING: REMOTE_EU not set - tun-eu not created"
fi
