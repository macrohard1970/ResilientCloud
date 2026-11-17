# Multi-Region Architecture

Expanding the single-host Containerlab spine-leaf lab into a three-region AWS datacenter architecture with full-mesh VPC connectivity and BGP routing across the WAN edge.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        AWS CLOUD (3 Regions)                            │
│                                                                         │
│   ┌──────────┐          VPC Peering          ┌──────────┐              │
│   │ DC-EAST  │◄────────────────────────────►│ DC-WEST  │              │
│   │us-east-1 │        10.0.0.0/16↔10.1.0.0/16│us-west-2 │              │
│   │          │                               │          │              │
│   │ 10.10/16 │                               │ 10.11/16 │              │
│   │ hosts    │                               │ hosts    │              │
│   │          │          VPC Peering          │          │              │
│   │ wan-east │◄───────────────┐    ┌─────────┤ wan-west │              │
│   │ AS65010  │               │    │         │ AS65020  │              │
│   └────┬─────┘               │    │         └────┬─────┘              │
│        │                     │    │              │                     │
│        │              VPC Peering  │              │                     │
│        │        10.0.0.0/16↔10.2.0.0/16         │                     │
│        │              10.1.0.0/16↔10.2.0.0/16   │                     │
│        │                     │    │              │                     │
│   ┌────┴─────┐               └────┴──────────────┴─────┐              │
│   │ DC-EU    │◄──────────────────────────────────────►│              │
│   │eu-west-1 │          VPC Peering (full mesh)        │              │
│   │ 10.12/16 │                                         │              │
│   │ wan-eu   │                                         │              │
│   │ AS65030  │                                         │              │
│   └──────────┘                                         │              │
└─────────────────────────────────────────────────────────┘
```

### Per-Region Topology (each region identical)

```
    ┌─────────┐         ┌─────────┐
    │ spine1  │═════════│ spine2  │    FRR (AS 65001, iBGP between spines)
    │ AS 65001│         │ AS 65001│    OSPF area 0 underlay
    └────┬────┘         └────┬────┘
   ┌──────┼──────────┐    ┌───┼──────────┐
   │      │          │    │   │          │
┌──┴──┐┌──┴──┐┌───┴─┐┌─┴──┐┌─┴──┐       │
│leaf1││leaf2││leaf3││leaf4││WAN │       │
│65101││65102││65103││65104││edge│       │
└──┬──┘└──┬──┘└──┬──┘└──┬──┘└─┬──┘       │
   │      │      │      │     │           │
┌──┴──┐┌──┴──┐┌──┴──┐┌──┴──┐  │  GRE tunnels (over VPC peering)
│hst-a││hst-b││hst-c││hst-d│  │  to other regions
│Alpine│Alpine│Alpine│Alpine│ wan-edge peers eBGP with:
└──────┘└──────┘└──────┘└──────┘  • Local spines (inject/learn fabric routes)
                                    • Remote wan-edge routers (cross-region)
```

---

## 1. Three-Region Design

### Region Selection

| Datacenter | AWS Region | Latency to DC-East | Rationale |
|-----------|-----------|-------------------|-----------|
| DC-East | us-east-1 | — (baseline) | Primary, existing infra |
| DC-West | us-west-2 | ~60ms RTT | US West coast, cross-continent |
| DC-EU | eu-west-1 | ~80ms RTT | Europe, trans-Atlantic |

These three regions provide geographic diversity across two continents. Cross-region latency is realistic for testing WAN routing behavior, BGP convergence, and failover scenarios.

### Why Three Regions (Not Two)

Two regions give you a single peering link — no mesh, no alternate path. Three regions create a triangle where the failure of any one peering link leaves the other two intact, and traffic can reroute through the third region. This is the minimum topology that demonstrates real WAN resilience.

### What Lives in Each Region

| Component | Per Region | Notes |
|-----------|-----------|-------|
| VPC | 1 | /16 CIDR, non-overlapping |
| Public subnet | 1 | Bastion EC2 with public IP |
| Private subnet | 1 | Containerlab EC2 instance |
| WAN subnet | 1 | /28 for WAN edge ENI |
| EC2 — bastion | 1 | t3.micro, public, SSH gateway |
| EC2 — lab host | 1 | t3.xlarge (min) or t3.2xlarge (recommended) |
| Containerlab topology | 1 | 2 spines, 4 leaves, 4 hosts, 1 WAN edge |
| Monitoring stack | 1 | Prometheus + Grafana (default); SuzieQ, Batfish, dnsmasq optional |
| VPC peering connections | 2 | One to each other region (full mesh = 3 total) |

---

## 2. WAN Edge Design

The WAN edge router is the bridge between the local Containerlab fabric and the inter-region WAN mesh. It is an FRR container added to each region's Containerlab topology.

### WAN Edge Role

```
┌─────────────────── Per-Region Containerlab Fabric ──────────────────┐
│                                                                     │
│   spine1 ──┬── spine2          OSPF area 0 + iBGP (AS 65001)         │
│      │    │    │                                                     │
│   leaf1..leaf4  wan-edge      eBGP fabric (6510x, 6501x)            │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
                              │
                    eBGP to spines (AS 65001)
                    eBGP neighbor of both spines
                              │
                    ┌─────────┴──────────┐
                    │   WAN EDGE ROUTER   │
                    │   (FRR container)   │
                    │   AS 65010/65020/65030 │
                    └─────────┬──────────┘
                              │
                    GRE tunnels over VPC peering
                              │
            ┌─────────────────┼─────────────────┐
            ▼                 ▼                 ▼
     wan-east (65010)  wan-west (65020)  wan-eu (65030)
            └─────────────────┼─────────────────┘
                              │
                    eBGP full mesh (3 sessions total)
                    BFD for fast failure detection
```

### WAN Edge Responsibilities

1. **Local fabric peering**: eBGP to both spines (AS 65001). Receives all local host /24s from the spines.

2. **Inter-region peering**: eBGP to the other two regions' WAN edge routers over GRE tunnels. Advertises local host subnets, learns remote host subnets.

3. **Route injection**: Remote /16 aggregates learned via inter-region eBGP are re-advertised to the local spines, which pass them to all leaves over eBGP. This makes remote hosts reachable from local hosts.

4. **Route filtering**: Only the region /16 aggregates cross the WAN (route-maps `WAN-IN`, `WAN-OUT`, `FABRIC-OUT` in `configs/frr/wan-*/frr.conf`). Host /24s, loopbacks, underlay links, management and services networks stay inside the region.

### GRE Tunnel Design

GRE tunnels encapsulate BGP and data traffic between WAN edge routers, traversing the VPC peering connection at the AWS level.

```
┌──────────────┐                    ┌──────────────┐
│  EC2 Host     │                    │  EC2 Host     │
│  DC-East      │                    │  DC-West      │
│               │                    │               │
│  ┌─────────┐  │    VPC Peering     │  ┌─────────┐  │
│  │wan-edge │  │◄──────────────────►│  │wan-edge │  │
│  │FRR cont.│  │  GRE over VPC peer │  │FRR cont.│  │
│  │tun-west │──┤                    ├──│tun-east │  │
│  └─────────┘  │                    │  └─────────┘  │
│               │                    │               │
│  Host route:  │                    │  Host route:  │
│  10.1.0.0/16  │                    │  10.0.0.0/16  │
│  via VPC peer │                    │  via VPC peer │
└──────────────┘                    └──────────────┘
```

**How the tunnel works:**

1. `tunnels.sh` (Containerlab exec) creates one GRE interface per remote region (`tun-west`, `tun-eu`, `tun-east`, MTU 1476). FRR assigns each a /30 from 10.110.0.0/24.
2. The GRE outer source is the container's management IP; the destination is the remote EC2 host's VPC private IP (`REMOTE_*` env vars). `scripts/gre-nat.sh` on the EC2 host masquerades outbound GRE to the host's VPC IP and DNATs inbound GRE (IP protocol 47) to the WAN edge container.
3. The EC2 host's route table sends the remote VPC CIDR through the VPC peering connection.
4. BGP sessions between WAN edge routers run between their loopbacks; a static /32 route per remote loopback points into the matching tunnel.
5. Data traffic (host-to-host across regions) also flows through the tunnels, encapsulated in GRE.

**Why GRE over direct VPC peering routing:**

- The Containerlab containers' IPs (10.10.x.x, 10.255.x.x) are inside Docker and not directly routable from the VPC. The GRE tunnel bridges the Docker network to the VPC network.
- GRE allows the FRR control plane to manage routing without modifying the EC2 host's route table for every learned prefix.
- This mirrors real-world WAN designs where routers peer over point-to-point links rather than directly attached subnets.

### WAN Edge ASN Assignments

| Router | ASN | Region | Peers |
|--------|-----|--------|-------|
| wan-east | 65010 | DC-East | spine1 (65001), spine2 (65001), wan-west (65020), wan-eu (65030) |
| wan-west | 65020 | DC-West | spine1 (65001), spine2 (65001), wan-east (65010), wan-eu (65030) |
| wan-eu | 65030 | DC-EU | spine1 (65001), spine2 (65001), wan-east (65010), wan-west (65020) |

---

## 3. Full-Mesh VPC Connectivity

### VPC Peering (Recommended for 3 Regions)

Three cross-region VPC peering connections create a full mesh:

```
         VPC Peering: pcx-east-west
    DC-East ◄──────────────────────────► DC-West
       │                                    │
       │    pcx-east-eu              pcx-west-eu    │
       └──────────────► DC-EU ◄──────────────┘
```

| Peering | Requester | Accepter | Routes Added |
|---------|-----------|----------|-------------|
| pcx-east-west | us-east-1 VPC | us-west-2 VPC | 10.1.0.0/16 → peer, 10.0.0.0/16 → peer |
| pcx-east-eu | us-east-1 VPC | eu-west-1 VPC | 10.2.0.0/16 → peer, 10.0.0.0/16 → peer |
| pcx-west-eu | us-west-2 VPC | eu-west-1 VPC | 10.2.0.0/16 → peer, 10.1.0.0/16 → peer |

Each VPC's route table gets two entries pointing remote VPC CIDRs through the peering connection.

### VPC Peering vs Transit Gateway

| Criteria | VPC Peering | Transit Gateway |
|----------|------------|-----------------|
| Connections for 3 regions | 3 (full mesh) | 3 TGWs + 3 inter-region peering attachments |
| Hourly cost | $0 | $0.05/hr × 3 = $3.60/day ($108/mo) |
| Data processing cost | $0 | $0.05/GB |
| Cross-region data transfer | $0.02/GB | $0.02/GB (same) |
| Scalability to 5+ regions | O(n²) connections | O(n) attachments |
| Transitive routing | No (non-transitive) | Yes |
| Configuration complexity | Low (route tables per VPC) | Medium (TGW route tables) |
| Best for | 3-4 VPCs, simple topology | 5+ VPCs, hub-spoke, VPN/DX integration |

**Decision: VPC Peering.** Three peerings is manageable, and the cost is zero beyond data transfer. The non-transitive limitation is irrelevant for a 3-node full mesh. If the architecture grows to 5+ regions, migrate to Transit Gateway.

### Route Table Configuration

Each VPC has a main route table with the following structure:

**DC-East (10.0.0.0/16) route table:**

| Destination | Target | Purpose |
|------------|--------|---------|
| 10.0.0.0/16 | local | VPC local |
| 0.0.0.0/0 | igw-xxx | Internet (public subnet) |
| 10.1.0.0/16 | pcx-east-west | DC-West via peering |
| 10.2.0.0/16 | pcx-east-eu | DC-EU via peering |

**DC-West (10.1.0.0/16) route table:**

| Destination | Target | Purpose |
|------------|--------|---------|
| 10.1.0.0/16 | local | VPC local |
| 0.0.0.0/0 | igw-xxx | Internet (public subnet) |
| 10.0.0.0/16 | pcx-east-west | DC-East via peering |
| 10.2.0.0/16 | pcx-west-eu | DC-EU via peering |

**DC-EU (10.2.0.0/16) route table:**

| Destination | Target | Purpose |
|------------|--------|---------|
| 10.2.0.0/16 | local | VPC local |
| 0.0.0.0/0 | igw-xxx | Internet (public subnet) |
| 10.0.0.0/16 | pcx-east-eu | DC-East via peering |
| 10.1.0.0/16 | pcx-west-eu | DC-West via peering |

---

## 4. BGP Routing Across Regions

### Route Propagation Flow

```
DC-East host-a (10.10.1.1) pings DC-West host-a (10.11.1.1):

1. host-a → leaf1 (gateway 10.10.1.254)
2. leaf1 has route to 10.11.0.0/16 via spine1/spine2 (learned from wan-east via BGP)
3. spine1/spine2 → wan-east (underlay link)
4. wan-east → GRE tunnel to wan-west (10.110.0.0/30)
5. GRE packet traverses VPC peering (10.0.0.0/16 → 10.1.0.0/16)
6. wan-west receives GRE, decapsulates
7. wan-west → spine1/spine2 (underlay link)
8. spine → leaf1 (has route to 10.11.1.0/24)
9. leaf1 → host-a (10.11.1.1)
```

### BGP Route Advertisement

**What each WAN edge advertises to remote peers:**

| WAN Edge | Advertises | To |
|----------|-----------|-----|
| wan-east | 10.10.0.0/16 (own aggregate) + 10.11/16, 10.12/16 (transit) | wan-west, wan-eu |
| wan-west | 10.11.0.0/16 (own aggregate) + 10.10/16, 10.12/16 (transit) | wan-east, wan-eu |
| wan-eu | 10.12.0.0/16 (own aggregate) + 10.10/16, 10.11/16 (transit) | wan-east, wan-west |

**What each WAN edge advertises to local spines:**

| WAN Edge | Advertises | To |
|----------|-----------|-----|
| wan-east | 10.11.0.0/16, 10.12.0.0/16 | dc-east-spine1, dc-east-spine2 |
| wan-west | 10.10.0.0/16, 10.12.0.0/16 | dc-west-spine1, dc-west-spine2 |
| wan-eu | 10.10.0.0/16, 10.11.0.0/16 | dc-eu-spine1, dc-eu-spine2 |

### Route Aggregation

Each WAN edge aggregates its region's four /24 host subnets into a single /16 advertisement:

| Region | Individual /24s | Aggregated /16 |
|--------|----------------|----------------|
| DC-East | 10.10.1.0/24, .2.0/24, .3.0/24, .4.0/24 | 10.10.0.0/16 |
| DC-West | 10.11.1.0/24, .2.0/24, .3.0/24, .4.0/24 | 10.11.0.0/16 |
| DC-EU | 10.12.1.0/24, .2.0/24, .3.0/24, .4.0/24 | 10.12.0.0/16 |

The WAN edge builds the aggregate with `aggregate-address` from the /24s its spines send it, so the /16 is only advertised while at least one local /24 exists. Individual /24s stay inside the region; only the /16 crosses the WAN. Transit aggregates are re-advertised so the third region can carry traffic when a direct tunnel fails.

### BGP Path Selection and Load Balancing

With the full mesh, each WAN edge has two paths to each remote region — one direct and one transitive through the third region:

```
wan-east to wan-west:
  Path 1: Direct (GRE tunnel, 1 hop, AS path: 65020)
  Path 2: Via wan-eu (2 GRE tunnels, 2 hops, AS path: 65030 65020)
```

BGP prefers the shorter AS path (direct). The transitive path serves as backup. If the direct tunnel goes down (BFD detects in <1s), BGP converges to the transitive path within seconds.

### Route Policies

Applied on every WAN edge (`configs/frr/wan-*/frr.conf`):

| Route-map | Direction | Permits | Effect |
|-----------|-----------|---------|--------|
| `WAN-OUT` | to remote WAN edges | own /16 aggregate, the two remote /16s | Own region plus transit for failover |
| `WAN-IN` | from remote WAN edges | the two remote /16s | Rejects anything else, including our own /16 |
| `FABRIC-OUT` | to local spines | the two remote /16s | Fabric learns only remote aggregates |

Loops are prevented by eBGP AS-path checks. Each WAN edge has a unique ASN, so a route that already passed through a region is rejected when it comes back.

---

## 5. Resilience Strategy

### Failure Scenarios and Recovery

| Failure | Detection | Recovery | Convergence Time |
|---------|-----------|----------|-----------------|
| Spine router crash | BFD (1s) | eBGP reroutes to surviving spine | <5s |
| Leaf router crash | BFD (1s) | Host loses connectivity (single-homed) | N/A (lab limitation) |
| WAN edge crash | BFD (1s) | BGP reroutes via transitive path | <10s |
| GRE tunnel down | BFD (1s) | BGP withdraws tunnel route, converges to backup | <10s |
| VPC peering link down | BFD on tunnel (1s) | Same as tunnel down | <10s |
| EC2 instance failure | CloudWatch alarm | EC2 auto-recovery or manual redeploy | Minutes |
| Entire region failure | BGP timeout (hold time ~9s) | Traffic reroutes through surviving region | <30s |

### Resilience Layers

1. **Fabric layer (per region)**: Dual spines (iBGP between them, eBGP to each leaf). Any single spine failure is handled by the surviving spine. BFD-enabled sessions detect failures in under 1 second.

2. **WAN layer**: Full-mesh eBGP between three WAN edge routers. Loss of any single peering link leaves two remaining. Traffic automatically reroutes through the third region. BFD on all WAN BGP sessions.

3. **AWS layer**: VPC peering connections are managed by AWS and inherently redundant across AWS infrastructure. Cross-region peering uses AWS's backbone network.

4. **Host layer**: EC2 auto-recovery can be enabled to automatically restart failed instances on different hardware. EBS snapshots enable quick redeployment. Containerlab topology is declarative — `containerlab deploy -t topology.clab.yml` rebuilds the entire lab in under 5 minutes.

### BGP Convergence Tuning

```
! On all WAN edge BGP neighbors:
neighbor X.X.X.X timers 3 9          ! Keepalive 3s, hold 9s
neighbor X.X.X.X timers connect 5    ! Connect retry 5s
neighbor X.X.X.X bfd profile WAN     ! bgpd creates the BFD session (multihop, loopbacks)

! BFD profile:
bfd
 profile WAN
  transmit-interval 300
  receive-interval 300
  detect-multiplier 3
 exit                            ! Detection time: 300ms × 3 = 900ms
```

### High-Availability Considerations

| Component | HA Approach | Notes |
|-----------|-------------|-------|
| Spines | 2 per region, active-active | iBGP between spines, eBGP to leaves and WAN edge |
| WAN edge | 1 per region | Single point of failure per region (acceptable for lab) |
| VPC peering | 3 connections (full mesh) | Any 2 still form a connected graph |
| BGP sessions | BFD-enabled, fast timers | <10s convergence |
| EC2 | Auto-recovery enabled | Restarts on hardware failure |
| Containerlab | Declarative topology | Redeploys in <5 min from git |

> **Production note:** For production, each region would have dual WAN edge routers (active/active), dual EC2 instances in different AZs, and Transit Gateway instead of VPC peering. This lab demonstrates the routing concepts at a scale that's practical to deploy and test.

---

## 6. Integration with Existing Lab

### What Changes

| Component | Current | Multi-Region | Impact |
|-----------|---------|-------------|--------|
| Containerlab topology | 2 spines, 4 leaves, 4 hosts | +1 WAN edge router per region | Add wan-edge node + 2 links to spines |
| FRR configs | 6 router configs | +1 wan-edge config per region | New FRR config for WAN edge |
| Spine configs | eBGP to 4 leaves | +1 eBGP neighbor (wan-edge) | Add wan-edge neighbor |
| IP plan | Single region | 3 regions, unique CIDRs | See multi-region-ip-plan.md |
| Ansible inventory | 6 routers, 4 hosts, 6 services | ×3 regions | Region-aware inventory |
| Deploy script | Single host | 3 EC2 hosts + VPC infra | Multi-region deploy script |
| Monitoring | Single Grafana/Prometheus | Per-region + cross-region views | Add WAN dashboards |

### What Stays the Same

- Containerlab topology structure (spine-leaf design)
- FRR version and daemon configuration
- OSPF area 0 underlay design
- eBGP leaf-spine pattern (no route reflection needed)
- Monitoring stack (Prometheus + Grafana; SuzieQ, Batfish, dnsmasq as optional profiles)
- Ansible automation framework
- Alpine Linux endpoint hosts
- All open-source licensing

### Backward Compatibility

The existing single-host lab continues to work unchanged. DC-East is the existing lab with a WAN edge router added. The multi-region expansion is additive — deploying DC-West and DC-EU does not break the existing setup. You can run DC-East alone (Phase 1), add WAN connectivity (Phase 2), or deploy all three regions (Phase 3) at any pace.
