#!/bin/sh
# GRE tunnel setup — wan-eu
# Runs inside the wan-eu container (Containerlab exec) and creates
# tun-east, tun-west.
#
# Addressing:
#   GRE source      = this container's management IP (eth0). The EC2 host
#                     masquerades it to the host's VPC IP on the way out and
#                     forwards inbound GRE back to it (scripts/gre-nat.sh).
#   GRE destination = remote EC2 host private IP, from the environment:
#     REMOTE_EAST  — DC-East lab host private IP
#     REMOTE_WEST  — DC-West lab host private IP
#   Tunnel IPs are configured by FRR (frr.conf), not here.
#
# A tunnel whose REMOTE_* variable is empty is skipped, so a region can
# run on its own without the WAN.

set -e

LOCAL_IP=$(ip -4 -o addr show dev eth0 | awk '{print $4}' | cut -d/ -f1)

mk_tunnel() {  # name remote
  [ -n "$2" ] || { echo "$1: remote IP not set - skipped"; return 0; }
  ip tunnel del "$1" 2>/dev/null || true
  ip tunnel add "$1" mode gre local "$LOCAL_IP" remote "$2" ttl 64
  # Inter-region VPC peering MTU is 1500; GRE adds 24 bytes
  ip link set "$1" mtu 1476 up
  echo "$1: $LOCAL_IP -> $2"
}

mk_tunnel tun-east "${REMOTE_EAST:-}"
mk_tunnel tun-west "${REMOTE_WEST:-}"
