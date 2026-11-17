#!/bin/sh
# host-a init script — endpoint on leaf1
# IP: 10.10.1.1/24 | Gateway: 10.10.1.254 (leaf1 eth3)

# Install networking tools
apk add --no-cache iproute2 iputils >/dev/null 2>&1 || true

# Configure the data-plane interface (eth1 → leaf1)
ip addr flush dev eth1
ip addr add 10.10.1.1/24 dev eth1
ip link set eth1 up

# Default route via leaf1
ip route del default 2>/dev/null
ip route add default via 10.10.1.254

# Verify
echo "=== host-a network config ==="
ip addr show eth1
ip route show
