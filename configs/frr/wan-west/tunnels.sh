#!/bin/sh
# GRE tunnel setup — wan-west (DC-West)
# Creates GRE tunnel interfaces to DC-East and DC-EU wan-edge routers.
#
# Environment variables:
#   LOCAL_IP     — this EC2 host's VPC private IP (GRE source)
#   REMOTE_EAST  — DC-East EC2 host's VPC private IP (GRE dest)
#   REMOTE_EU    — DC-EU EC2 host's VPC private IP (GRE dest)
#
# Tunnel IPs:
#   tun-east: 10.110.0.2/30 (remote: 10.110.0.1 on wan-east)
#   tun-eu:   10.110.0.9/30 (remote: 10.110.0.10 on wan-eu)

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

# Create GRE tunnel to DC-EU
if [ -n "$REMOTE_EU" ]; then
  ip tunnel del tun-eu 2>/dev/null || true
  ip tunnel add tun-eu mode gre local "$LOCAL_IP" remote "$REMOTE_EU" ttl 64
  ip link set tun-eu up
  echo "Created GRE tunnel tun-eu: $LOCAL_IP -> $REMOTE_EU"
else
  echo "WARNING: REMOTE_EU not set - tun-eu not created"
fi
