# Multi-Region IP Addressing Plan

Three datacenters across AWS regions, each running an independent Containerlab spine-leaf fabric, connected via VPC peering full-mesh with BGP routing across the WAN edge.

## Region Allocation

| Datacenter | AWS Region | Location | Role |
|-----------|------------|----------|------|
| DC-East | us-east-1 | N. Virginia, USA | Primary (Americas) |
| DC-West | us-west-2 | Oregon, USA | Secondary (Americas West) |
| DC-EU | eu-west-1 | Dublin, Ireland | Tertiary (Europe) |

---

## Network Allocation Summary

### AWS VPC Level (routable across regions via VPC peering)

| Network | DC-East | DC-West | DC-EU | Purpose |
|---------|---------|---------|-------|---------|
| VPC CIDR | 10.0.0.0/16 | 10.1.0.0/16 | 10.2.0.0/16 | AWS VPC supernet |
| Public subnet | 10.0.1.0/24 | 10.1.1.0/24 | 10.2.1.0/24 | EC2 with public IP (SSH/bastion) |
| Private subnet | 10.0.2.0/24 | 10.1.2.0/24 | 10.2.2.0/24 | EC2 without public IP |
| WAN subnet | 10.0.3.0/28 | 10.1.3.0/28 | 10.2.3.0/28 | WAN edge ENI / tunnel endpoints |

### Containerlab Internal Level (Docker-isolated per host)

| Network | DC-East | DC-West | DC-EU | Purpose |
|---------|---------|---------|-------|---------|
| Host subnets | 10.10.0.0/16 | 10.11.0.0/16 | 10.12.0.0/16 | Endpoint /24s per leaf (advertised via BGP) |
| Loopbacks | 10.255.0.0/24 | 10.254.0.0/24 | 10.253.0.0/24 | Router IDs /32 (advertised via BGP) |
| Underlay P2P | 10.0.0.0/24 | 10.100.0.0/24 | 10.200.0.0/24 | Spine-leaf /31 links (Docker-internal, not advertised) |
| Management | 10.255.255.0/24 | 10.254.255.0/24 | 10.253.255.0/24 | Containerlab OOB mgmt (Docker-internal) |
| Services | 10.20.0.0/24 | 10.21.0.0/24 | 10.22.0.0/24 | Monitoring containers (Docker-internal) |

### WAN Interconnect (GRE tunnels over VPC peering)

| Network | Subnet | Purpose |
|---------|--------|---------|
| WAN tunnel mesh | 10.100.0.0/24 | /30 per inter-region tunnel (3 links for full mesh) |

---

## 1. AWS VPC Design

Each region gets a dedicated VPC with public, private, and WAN subnets. The VPC CIDRs are non-overlapping to enable cross-region VPC peering.

### VPC — DC-East (us-east-1)

| Subnet | CIDR | AZ | Purpose |
|--------|------|----|---------|
| Public | 10.0.1.0/24 | us-east-1a | Bastion/jump host with public IP |
| Private | 10.0.2.0/24 | us-east-1b | Containerlab EC2 instance |
| WAN | 10.0.3.0/28 | us-east-1a | Secondary ENI for WAN edge tunnel |

VPC ID: `vpc-0287cc4e662371bcb` (existing)
IGW: `igw-0fcd99507b2227246` (existing)

### VPC — DC-West (us-west-2)

| Subnet | CIDR | AZ | Purpose |
|--------|------|----|---------|
| Public | 10.1.1.0/24 | us-west-2a | Bastion/jump host with public IP |
| Private | 10.1.2.0/24 | us-west-2b | Containerlab EC2 instance |
| WAN | 10.1.3.0/28 | us-west-2a | Secondary ENI for WAN edge tunnel |

### VPC — DC-EU (eu-west-1)

| Subnet | CIDR | AZ | Purpose |
|--------|------|----|---------|
| Public | 10.2.1.0/24 | eu-west-1a | Bastion/jump host with public IP |
| Private | 10.2.2.0/24 | eu-west-1b | Containerlab EC2 instance |
| WAN | 10.2.3.0/28 | eu-west-1a | Secondary ENI for WAN edge tunnel |

---

## 2. Host Subnets — BGP-Advertised Per Region

Each region's host subnets are advertised via BGP across the WAN mesh. These MUST be unique across all regions.

### DC-East — 10.10.0.0/16

| Leaf | Subnet | Gateway | Host IP | VLAN |
|------|--------|---------|---------|------|
| leaf1 | 10.10.1.0/24 | 10.10.1.254 | 10.10.1.1 | 10 |
| leaf2 | 10.10.2.0/24 | 10.10.2.254 | 10.10.2.1 | 20 |
| leaf3 | 10.10.3.0/24 | 10.10.3.254 | 10.10.3.1 | 30 |
| leaf4 | 10.10.4.0/24 | 10.10.4.254 | 10.10.4.1 | 40 |

Remaining: 10.10.5.0/24 – 10.10.255.0/24

### DC-West — 10.11.0.0/16

| Leaf | Subnet | Gateway | Host IP | VLAN |
|------|--------|---------|---------|------|
| leaf1 | 10.11.1.0/24 | 10.11.1.254 | 10.11.1.1 | 10 |
| leaf2 | 10.11.2.0/24 | 10.11.2.254 | 10.11.2.1 | 20 |
| leaf3 | 10.11.3.0/24 | 10.11.3.254 | 10.11.3.1 | 30 |
| leaf4 | 10.11.4.0/24 | 10.11.4.254 | 10.11.4.1 | 40 |

Remaining: 10.11.5.0/24 – 10.11.255.0/24

### DC-EU — 10.12.0.0/16

| Leaf | Subnet | Gateway | Host IP | VLAN |
|------|--------|---------|---------|------|
| leaf1 | 10.12.1.0/24 | 10.12.1.254 | 10.12.1.1 | 10 |
| leaf2 | 10.12.2.0/24 | 10.12.2.254 | 10.12.2.1 | 20 |
| leaf3 | 10.12.3.0/24 | 10.12.3.254 | 10.12.3.1 | 30 |
| leaf4 | 10.12.4.0/24 | 10.12.4.254 | 10.12.4.1 | 40 |

Remaining: 10.12.5.0/24 – 10.12.255.0/24

---

## 3. Loopback Addresses — BGP-Advertised Per Region

Each router gets a /32 loopback used as OSPF Router ID and BGP update-source. These are unique per region and advertised via BGP for reachability.

### DC-East — 10.255.0.0/24 (existing, unchanged)

| Device | Loopback | ASN | Role |
|--------|----------|-----|------|
| spine1 | 10.255.0.1/32 | 65001 | Spine (route reflector) |
| spine2 | 10.255.0.2/32 | 65001 | Spine (route reflector) |
| leaf1 | 10.255.0.11/32 | 65101 | Leaf |
| leaf2 | 10.255.0.12/32 | 65102 | Leaf |
| leaf3 | 10.255.0.13/32 | 65103 | Leaf |
| leaf4 | 10.255.0.14/32 | 65104 | Leaf |
| wan-east | 10.255.0.100/32 | 65010 | WAN edge (new) |

### DC-West — 10.254.0.0/24

| Device | Loopback | ASN | Role |
|--------|----------|-----|------|
| spine1 | 10.254.0.1/32 | 65001 | Spine (route reflector) |
| spine2 | 10.254.0.2/32 | 65001 | Spine (route reflector) |
| leaf1 | 10.254.0.11/32 | 65101 | Leaf |
| leaf2 | 10.254.0.12/32 | 65102 | Leaf |
| leaf3 | 10.254.0.13/32 | 65103 | Leaf |
| leaf4 | 10.254.0.14/32 | 65104 | Leaf |
| wan-west | 10.254.0.100/32 | 65020 | WAN edge |

### DC-EU — 10.253.0.0/24

| Device | Loopback | ASN | Role |
|--------|----------|-----|------|
| spine1 | 10.253.0.1/32 | 65001 | Spine (route reflector) |
| spine2 | 10.253.0.2/32 | 65001 | Spine (route reflector) |
| leaf1 | 10.253.0.11/32 | 65101 | Leaf |
| leaf2 | 10.253.0.12/32 | 65102 | Leaf |
| leaf3 | 10.253.0.13/32 | 65103 | Leaf |
| leaf4 | 10.253.0.14/32 | 65104 | Leaf |
| wan-eu | 10.253.0.100/32 | 65030 | WAN edge |

> **Note:** The internal fabric ASNs (65001, 65101–65104) are reused across regions. This is safe because each region's fabric is Docker-isolated — the ASNs never interact outside their host. Only the WAN edge ASNs (65010, 65020, 65030) are unique and visible across regions.

---

## 4. Underlay P2P Links (Docker-Internal)

Each region's spine-leaf underlay uses /31 point-to-point links. These are inside Docker network namespaces and never advertised externally, so they could theoretically be reused. Unique ranges are assigned for operational clarity.

### DC-East — 10.0.0.0/24 (existing, unchanged)

| Link | Spine side | Leaf side | Subnet |
|------|-----------|-----------|--------|
| spine1 ↔ leaf1 | 10.0.0.0/31 | 10.0.0.1/31 | 10.0.0.0/31 |
| spine1 ↔ leaf2 | 10.0.0.2/31 | 10.0.0.3/31 | 10.0.0.2/31 |
| spine1 ↔ leaf3 | 10.0.0.4/31 | 10.0.0.5/31 | 10.0.0.4/31 |
| spine1 ↔ leaf4 | 10.0.0.6/31 | 10.0.0.7/31 | 10.0.0.6/31 |
| spine2 ↔ leaf1 | 10.0.0.8/31 | 10.0.0.9/31 | 10.0.0.8/31 |
| spine2 ↔ leaf2 | 10.0.0.10/31 | 10.0.0.11/31 | 10.0.0.10/31 |
| spine2 ↔ leaf3 | 10.0.0.12/31 | 10.0.0.13/31 | 10.0.0.12/31 |
| spine2 ↔ leaf4 | 10.0.0.14/31 | 10.0.0.15/31 | 10.0.0.14/31 |
| spine1 ↔ spine2 | 10.0.0.16/31 | 10.0.0.17/31 | 10.0.0.16/31 |
| spine1 ↔ wan-east | 10.0.0.18/31 | 10.0.0.19/31 | 10.0.0.18/31 |
| spine2 ↔ wan-east | 10.0.0.20/31 | 10.0.0.21/31 | 10.0.0.20/31 |

### DC-West — 10.100.0.0/24

Same structure as DC-East, offset to 10.100.0.0/24.

| Link | Subnet |
|------|--------|
| spine1 ↔ leaf1 | 10.100.0.0/31 |
| spine1 ↔ leaf2 | 10.100.0.2/31 |
| spine1 ↔ leaf3 | 10.100.0.4/31 |
| spine1 ↔ leaf4 | 10.100.0.6/31 |
| spine2 ↔ leaf1 | 10.100.0.8/31 |
| spine2 ↔ leaf2 | 10.100.0.10/31 |
| spine2 ↔ leaf3 | 10.100.0.12/31 |
| spine2 ↔ leaf4 | 10.100.0.14/31 |
| spine1 ↔ spine2 | 10.100.0.16/31 |
| spine1 ↔ wan-west | 10.100.0.18/31 |
| spine2 ↔ wan-west | 10.100.0.20/31 |

### DC-EU — 10.200.0.0/24

Same structure, offset to 10.200.0.0/24.

| Link | Subnet |
|------|--------|
| spine1 ↔ leaf1 | 10.200.0.0/31 |
| spine1 ↔ leaf2 | 10.200.0.2/31 |
| spine1 ↔ leaf3 | 10.200.0.4/31 |
| spine1 ↔ leaf4 | 10.200.0.6/31 |
| spine2 ↔ leaf1 | 10.200.0.8/31 |
| spine2 ↔ leaf2 | 10.200.0.10/31 |
| spine2 ↔ leaf3 | 10.200.0.12/31 |
| spine2 ↔ leaf4 | 10.200.0.14/31 |
| spine1 ↔ spine2 | 10.200.0.16/31 |
| spine1 ↔ wan-eu | 10.200.0.18/31 |
| spine2 ↔ wan-eu | 10.200.0.20/31 |

---

## 5. WAN Tunnel Mesh — 10.100.0.0/24 (Inter-Region)

GRE tunnels carry BGP between WAN edge routers across VPC peering connections. Each tunnel is a /30.

| Tunnel | DC-East side | DC-West side | DC-EU side | Subnet |
|--------|-------------|-------------|-----------|--------|
| East ↔ West | 10.110.0.1/30 | 10.110.0.2/30 | — | 10.110.0.0/30 |
| East ↔ EU | 10.110.0.5/30 | — | 10.110.0.6/30 | 10.110.0.4/30 |
| West ↔ EU | — | 10.110.0.9/30 | 10.110.0.10/30 | 10.110.0.8/30 |

> Tunnel subnet range 10.110.0.0/24 is reserved for inter-region WAN links and not used by any VPC or internal Docker network.

### WAN Edge Router Tunnel Interfaces

| WAN Edge | To East | To West | To EU |
|----------|---------|---------|-------|
| wan-east (DC-East) | — | tun-w: 10.110.0.1/30 | tun-e: 10.110.0.5/30 |
| wan-west (DC-West) | tun-e: 10.110.0.2/30 | — | tun-e: 10.110.0.9/30 |
| wan-eu (DC-EU) | tun-e: 10.110.0.6/30 | tun-w: 10.110.0.10/30 | — |

---

## 6. BGP ASN Plan

### Internal Fabric (Docker-Isolated, Reused Per Region)

| ASN | Devices | Type | Purpose |
|-----|---------|------|---------|
| 65001 | spine1, spine2 | iBGP | Spine fabric, route reflectors |
| 65101 | leaf1 | eBGP | Connects to spines, advertises host /24 |
| 65102 | leaf2 | eBGP | Connects to spines, advertises host /24 |
| 65103 | leaf3 | eBGP | Connects to spines, advertises host /24 |
| 65104 | leaf4 | eBGP | Connects to spines, advertises host /24 |

These ASNs are reused in all three regions. Safe because each fabric is isolated inside its Docker host and never peers externally.

### WAN Edge (Unique Per Region, Inter-Region Peering)

| ASN | Device | Region | Peers With |
|-----|--------|--------|-----------|
| 65010 | wan-east | DC-East | Spines (65001), wan-west (65020), wan-eu (65030) |
| 65020 | wan-west | DC-West | Spines (65001), wan-east (65010), wan-eu (65030) |
| 65030 | wan-eu | DC-EU | Spines (65001), wan-east (65010), wan-west (65020) |

### BGP Peering Topology

```
                     eBGP (65010 ↔ 65020)
    ┌─────────────┐◄──────────────────────►┌─────────────┐
    │  DC-EAST    │                          │  DC-WEST    │
    │  AS 65010   │                          │  AS 65020   │
    │  wan-east   │                          │  wan-west   │
    └──────┬──────┘                          └──────┬──────┘
           │                                        │
    eBGP   │ 65010↔65030                    eBGP   │ 65020↔65030
           │                                        │
    ┌──────┴──────┐◄────────────────────────────────┴──────┐
    │  DC-EU      │           eBGP (65020 ↔ 65030)         │
    │  AS 65030   │                                       │
    │  wan-eu     │◄───────────────────────────────────────►
    └─────────────┘           eBGP (65010 ↔ 65030)
```

Each WAN edge router also peers eBGP with its local spines (AS 65001), acting as a route-reflector client. This injects remote routes into the local fabric and advertises local host subnets to remote regions.

---

## 7. Management & Services (Docker-Internal Per Region)

These networks exist only inside each EC2 host's Docker. They are not routable across regions.

| Network | DC-East | DC-West | DC-EU | Purpose |
|---------|---------|---------|-------|---------|
| Management | 10.255.255.0/24 | 10.254.255.0/24 | 10.253.255.0/24 | Containerlab OOB (SSH, Ansible, gNMI) |
| Services | 10.20.0.0/24 | 10.21.0.0/24 | 10.22.0.0/24 | Monitoring containers |

### Management IP Assignments (same pattern per region)

| Device | DC-East | DC-West | DC-EU |
|--------|---------|---------|-------|
| spine1 | .11 | .11 | .11 |
| spine2 | .12 | .12 | .12 |
| leaf1 | .21 | .21 | .21 |
| leaf2 | .22 | .22 | .22 |
| leaf3 | .23 | .23 | .23 |
| leaf4 | .24 | .24 | .24 |
| wan-edge | .50 | .50 | .50 |
| host-a | .31 | .31 | .31 |
| host-b | .32 | .32 | .32 |
| host-c | .33 | .33 | .33 |
| host-d | .34 | .34 | .34 |
| prometheus | .41 | .41 | .41 |
| grafana | .42 | .42 | .42 |
| suzieq | .43 | .43 | .43 |
| batfish | .44 | .44 | .44 |
| gnmic | .45 | .45 | .45 |
| dnsmasq | .46 | .46 | .46 |

---

## IP Allocation Map (Visual)

```
AWS VPC LEVEL (routable across regions)
├── 10.0.0.0/16  ── DC-East VPC (us-east-1)
├── 10.1.0.0/16  ── DC-West VPC (us-west-2)
└── 10.2.0.0/16  ── DC-EU VPC (eu-west-1)

CONTAINERLAB INTERNAL (Docker-isolated, BGP-advertised)
├── 10.10.0.0/16 ── DC-East host subnets (advertised)
├── 10.11.0.0/16 ── DC-West host subnets (advertised)
├── 10.12.0.0/16 ── DC-EU host subnets (advertised)
├── 10.255.0.0/24 ── DC-East loopbacks (advertised)
├── 10.254.0.0/24 ── DC-West loopbacks (advertised)
└── 10.253.0.0/24 ── DC-EU loopbacks (advertised)

WAN INTERCONNECT (GRE tunnels over VPC peering)
└── 10.110.0.0/24 ── Inter-region tunnel /30s

DOCKER-INTERNAL (not advertised, unique per region for clarity)
├── 10.0.0.0/24    ── DC-East underlay P2P
├── 10.100.0.0/24  ── DC-West underlay P2P
├── 10.200.0.0/24  ── DC-EU underlay P2P
├── 10.255.255.0/24 ── DC-East mgmt
├── 10.254.255.0/24 ── DC-West mgmt
├── 10.253.255.0/24 ── DC-EU mgmt
├── 10.20.0.0/24   ── DC-East services
├── 10.21.0.0/24   ── DC-West services
└── 10.22.0.0/24   ── DC-EU services
```

No overlaps between any VPC CIDRs, BGP-advertised prefixes, or WAN tunnel subnets. Docker-internal networks (underlay, mgmt, services) are isolated per host and assigned unique ranges for operational clarity.
