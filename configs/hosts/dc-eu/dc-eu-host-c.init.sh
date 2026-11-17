#!/bin/sh
# host-c init script — DC-EU endpoint on leaf3
# IP: 10.12.3.1/24 | Gateway: 10.12.3.254 (leaf3 eth3)

# Install networking tools
apk add --no-cache iproute2 iputils >/dev/null 2>&1 || true

# Configure the data-plane interface (eth1 → leaf3)
ip addr flush dev eth1
ip addr add 10.12.3.1/24 dev eth1
ip link set eth1 up

# Default route via leaf3
ip route del default 2>/dev/null
ip route add default via 10.12.3.254

# Verify
echo "=== host-c network config ==="
ip addr show eth1
ip route show
