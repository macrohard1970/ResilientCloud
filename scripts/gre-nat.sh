#!/usr/bin/env bash
# Forward inter-region GRE between the EC2 host and its WAN edge container.
#
# The wan-<region> container sources GRE from its management IP. Outbound,
# Docker's masquerade rule rewrites that to the host's VPC IP. Inbound GRE
# arrives at the host's VPC IP, so this script DNATs it to the container.
#
# Usage (on the EC2 lab host, after containerlab deploy):
#   sudo scripts/gre-nat.sh <region> up|down
#     region: dc-east | dc-west | dc-eu

set -euo pipefail

declare -A WAN_MGMT=( [dc-east]=10.255.255.50 [dc-west]=10.254.255.50 [dc-eu]=10.253.255.50 )
declare -A MGMT_NET=( [dc-east]=10.255.255.0/24 [dc-west]=10.254.255.0/24 [dc-eu]=10.253.255.0/24 )

REGION="${1:-}"; ACTION="${2:-up}"
[[ -n "${WAN_MGMT[$REGION]:-}" ]] || { echo "Usage: $0 dc-east|dc-west|dc-eu up|down" >&2; exit 1; }

WAN_IP="${WAN_MGMT[$REGION]}"
UPLINK=$(ip -4 route show default | awk '{print $5; exit}')

# GRE connection tracking/NAT helpers (built in on most kernels)
modprobe nf_conntrack_proto_gre 2>/dev/null || true
modprobe nf_nat_proto_gre 2>/dev/null || true
sysctl -qw net.ipv4.ip_forward=1

rules=(
  "-t nat PREROUTING -i $UPLINK -p gre -j DNAT --to-destination $WAN_IP"
  "-t nat POSTROUTING -s ${MGMT_NET[$REGION]} -o $UPLINK -p gre -j MASQUERADE"
  "-t filter FORWARD -p gre -d $WAN_IP -j ACCEPT"
  "-t filter FORWARD -p gre -s $WAN_IP -j ACCEPT"
)

for r in "${rules[@]}"; do
  read -r -a parts <<<"$r"
  table=("${parts[@]:0:2}"); chain="${parts[2]}"; spec=("${parts[@]:3}")
  if [[ "$ACTION" == "up" ]]; then
    iptables "${table[@]}" -C "$chain" "${spec[@]}" 2>/dev/null || iptables "${table[@]}" -I "$chain" 1 "${spec[@]}"
  else
    iptables "${table[@]}" -D "$chain" "${spec[@]}" 2>/dev/null || true
  fi
done
echo "GRE NAT $ACTION: $UPLINK <-> $WAN_IP ($REGION)"
