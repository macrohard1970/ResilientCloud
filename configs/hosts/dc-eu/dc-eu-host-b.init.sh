#!/bin/sh
# host-b init script — DC-EU endpoint on leaf2
# IP: 10.12.2.1/24 | Gateway: 10.12.2.254 (leaf2 eth3)

# Install networking tools
apk add --no-cache iproute2 iputils ping bash 2>/dev/null

# Configure the data-plane interface (eth1 → leaf2)
ip addr flush dev eth1
ip addr add 10.12.2.1/24 dev eth1
ip link set eth1 up

# Default route via leaf2
ip route del default 2>/dev/null
ip route add default via 10.12.2.254

# Verify
echo "=== host-b network config ==="
ip addr show eth1
ip route show
