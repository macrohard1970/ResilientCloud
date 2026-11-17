#!/bin/sh
# host-d init script — DC-West endpoint on leaf4
# IP: 10.11.4.1/24 | Gateway: 10.11.4.254 (leaf4 eth3)

# Install networking tools
apk add --no-cache iproute2 iputils ping bash 2>/dev/null

# Configure the data-plane interface (eth1 → leaf4)
ip addr flush dev eth1
ip addr add 10.11.4.1/24 dev eth1
ip link set eth1 up

# Default route via leaf4
ip route del default 2>/dev/null
ip route add default via 10.11.4.254

# Verify
echo "=== host-d network config ==="
ip addr show eth1
ip route show
