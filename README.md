# ResilientCloud

A multi-region resilient cloud networking lab built entirely with free and open-source tools. Three AWS regions run independent Containerlab spine-leaf fabrics connected via VPC peering full-mesh with GRE tunnels carrying eBGP for cross-region routing.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        AWS CLOUD (3 Regions)                            │
│                                                                         │
│   ┌──────────┐          VPC Peering          ┌──────────┐              │
│   │ DC-EAST  │◄────────────────────────────►│ DC-WEST  │              │
│   │us-east-1 │        10.0.0.0/16↔10.1.0.0/16│us-west-2 │              │
│   │ 10.10/16 │                               │ 10.11/16 │              │
│   │ wan-east │◄───────────────┐    ┌─────────┤ wan-west │              │
│   │ AS65010  │               │    │         │ AS65020  │              │
│   └────┬─────┘               │    │         └────┬─────┘              │
│        │              VPC Peering  │              │                     │
│   ┌────┴─────┐               └────┴──────────────┴─────┐              │
│   │ DC-EU    │◄──────────────────────────────────────►│              │
│   │eu-west-1 │          VPC Peering (full mesh)        │              │
│   │ 10.12/16 │                                         │              │
│   │ wan-eu   │                                         │              │
│   │ AS65030  │                                         │              │
│   └──────────┘                                         │              │
└─────────────────────────────────────────────────────────┘
```

### Per-Region Topology

```
    ┌─────────┐         ┌─────────┐
    │ spine1  │═════════│ spine2  │    FRR (AS 65001, iBGP between spines)
    └────┬────┘         └────┬────┘    OSPF area 0 underlay
   ┌──────┼──────────┐    ┌───┼──────────┐
   │      │          │    │   │          │
┌──┴──┐┌──┴──┐┌───┴─┐┌─┴──┐┌─┴──┐       │
│leaf1││leaf2││leaf3││leaf4││WAN │       │
└──┬──┘└──┬──┘└──┬──┘└──┬──┘└─┬──┘       │
   │      │      │      │     │           │
┌──┴──┐┌──┴──┐┌──┴──┐┌──┴──┐  │  GRE tunnels (over VPC peering)
│hst-a││hst-b││hst-c││hst-d│  │  to other regions
└──────┘└──────┘└──────┘└──────┘  wan-edge peers eBGP with:
                                    • Local spines (inject/learn fabric routes)
                                    • Remote wan-edge routers (cross-region)
```

## Key Design Principles

- **Three regions, not two** — A triangle topology where the failure of any one peering link leaves the other two intact. Traffic can reroute through the third region. This is the minimum topology that demonstrates real WAN resilience.
- **Full-mesh VPC peering** — Three cross-region peering connections (no Transit Gateway cost). Each VPC routes to both others directly.
- **GRE tunnels over VPC peering** — Containerlab container IPs are Docker-internal and not directly routable from the VPC. GRE tunnels bridge the Docker network to the VPC network, carrying BGP and data traffic between WAN edge routers.
- **eBGP full mesh between WAN edges** — Each WAN edge peers with its local spines (to inject/learn fabric routes) and with both remote WAN edges (to exchange inter-region routes). BFD provides sub-second failure detection.
- **Route aggregation** — Each WAN edge aggregates its region's four /24 host subnets into a single /16 advertisement. Individual /24s stay within the local fabric; only the /16 aggregate crosses the WAN.

## Regions

| Datacenter | AWS Region | VPC CIDR | Host Subnets | Loopbacks | WAN ASN |
|-----------|-----------|----------|-------------|----------|---------|
| DC-East | us-east-1 | 10.0.0.0/16 | 10.10.0.0/16 | 10.255.0.0/24 | AS 65010 |
| DC-West | us-west-2 | 10.1.0.0/16 | 10.11.0.0/16 | 10.254.0.0/24 | AS 65020 |
| DC-EU | eu-west-1 | 10.2.0.0/16 | 10.12.0.0/16 | 10.253.0.0/24 | AS 65030 |

## Components

| Component | Tool | License |
|-----------|------|---------|
| Topology orchestration | Containerlab | BSD-3-Clause |
| Routers | FRRouting (FRR) | GPL-2.0 |
| Endpoint hosts | Alpine Linux | MIT |
| Automation | Ansible | GPL-3.0 |
| Metrics | Prometheus + Grafana | Apache-2.0 / AGPL-3.0 |
| Observability | Suzieq | Apache-2.0 |
| Config validation | Batfish | Apache-2.0 |
| Telemetry | frr_exporter | MIT |
| DNS/DHCP | dnsmasq | GPL-2.0 |

## Repository Structure

```
ResilientCloud/
├── docs/
│   ├── multi-region-architecture.md   # Full architecture document
│   ├── multi-region-ip-plan.md       # IP addressing plan (all 3 regions)
│   ├── deployment-phases.md          # 3-phase rollout plan
│   ├── cost-estimate.md              # AWS cost breakdown
│   ├── ip-addressing-plan.md         # Original single-region IP plan
│   └── diagrams/
│       ├── architecture-overview.md  # High-level AWS multi-region diagram
│       ├── network-topology.md       # Per-region spine-leaf fabric
│       ├── bgp-peering.md            # BGP AS relationships and peering
│       ├── traffic-flow.md           # Cross-region traffic path
│       ├── resilience-failover.md    # Failure scenarios and recovery
│       ├── deployment-phases.md      # Phased deployment timeline
│       ├── monitoring-observability.md # Telemetry, metrics, and validation flow
│       ├── automation-workflow.md    # Deploy scripts, Containerlab, Ansible
│       └── security-access.md        # Trust boundaries, SGs, access path
├── bin/                                # frr_exporter binary (downloaded, git-ignored)
├── configs/
│   ├── frr/
│   │   ├── dc-east-{spine1,spine2,leaf1..4}/   # DC-East fabric
│   │   ├── dc-west-{spine1,spine2,leaf1..4}/   # DC-West fabric
│   │   ├── dc-eu-{spine1,spine2,leaf1..4}/     # DC-EU fabric
│   │   └── wan-east/ wan-west/ wan-eu/         # WAN edges (frr.conf + tunnels.sh)
│   └── hosts/
│       ├── dc-east/dc-east-host-{a..d}.init.sh
│       ├── dc-west/dc-west-host-{a..d}.init.sh
│       └── dc-eu/dc-eu-host-{a..d}.init.sh
├── automation/ansible/
│   ├── inventory.yml                   # Single-region (DC-East, no WAN edge)
│   ├── inventory-multi-region.yml      # All 33 devices; use -l dc_east|dc_west|dc_eu
│   ├── requirements.yml                # community.docker collection
│   ├── group_vars/                     # routers / spines / leaves
│   └── playbooks/deploy-configs.yml    # Push configs, reload FRR, verify
├── monitoring/                         # Per-region Prometheus + Grafana; optional SuzieQ, Batfish, dnsmasq
│   ├── env/<region>.env                # Region settings for docker compose
│   └── prometheus/targets/<region>.yml # frr_exporter targets
├── scripts/
│   ├── deploy.sh                       # Single-region deploy/destroy/status
│   ├── deploy-multi-region.sh          # Per-region deploy/destroy/status
│   ├── gre-nat.sh                      # Host NAT so GRE reaches the WAN edge container
│   └── fetch-frr-exporter.sh           # Download frr_exporter (pinned, checksummed)
├── topology.clab.yml                   # DC-East single-region topology
├── topology-dc-east.clab.yml           # DC-East with WAN edge
├── topology-dc-west.clab.yml           # DC-West with WAN edge
└── topology-dc-eu.clab.yml             # DC-EU with WAN edge
```

## Quick Start

### Phase 1: Deploy Independent Regions

Each region runs on its own EC2 lab host. Prerequisites: Docker with the compose
plugin, Containerlab, and for Ansible `ansible-core` plus the `community.docker`
collection.

```bash
# On each EC2 host (example: DC-East; use dc-west / dc-eu on the others)
git clone https://github.com/macrohard80/ResilientCloud.git && cd ResilientCloud
scripts/fetch-frr-exporter.sh                     # optional: FRR metrics for Prometheus
scripts/deploy-multi-region.sh deploy dc-east     # topology + Prometheus/Grafana

# Re-push configs after editing configs/frr/* (no restart needed)
cd automation/ansible
ansible-galaxy collection install -r requirements.yml
ansible-playbook -i inventory-multi-region.yml playbooks/deploy-configs.yml -l dc_east
```

Optional monitoring: `MON_PROFILES="batfish dns" scripts/deploy-multi-region.sh deploy dc-east`.
See [monitoring/README.md](monitoring/README.md).

### Phase 2: VPC Peering Full-Mesh

Create cross-region VPC peering connections and update route tables and
security groups (allow IP protocol 47, GRE, between the lab hosts). See
`docs/deployment-phases.md` for the AWS CLI commands.

### Phase 3: WAN Edge BGP

Redeploy each region with the other two lab hosts' private IPs. The WAN edge
creates its GRE tunnels at startup and `gre-nat.sh` forwards GRE to it:

```bash
# DC-East host
REMOTE_WEST=<dc-west-private-ip> REMOTE_EU=<dc-eu-private-ip> scripts/deploy-multi-region.sh deploy dc-east
# DC-West host
REMOTE_EAST=<dc-east-private-ip> REMOTE_EU=<dc-eu-private-ip> scripts/deploy-multi-region.sh deploy dc-west
# DC-EU host
REMOTE_EAST=<dc-east-private-ip> REMOTE_WEST=<dc-west-private-ip> scripts/deploy-multi-region.sh deploy dc-eu
```

### Verify Cross-Region Connectivity

```bash
# DC-East → DC-West
docker exec dc-east-host-a ping -c 3 10.11.1.1

# DC-East → DC-EU
docker exec dc-east-host-a ping -c 3 10.12.1.1

# DC-West → DC-EU
docker exec dc-west-host-a ping -c 3 10.12.1.1

# Show BGP sessions on WAN edge
docker exec wan-east vtysh -c "show ip bgp summary"

# Trace cross-region path
docker exec dc-east-host-a traceroute 10.11.1.1
```

### Test Failover

```bash
# Shut down East↔West tunnel, verify traffic reroutes through EU:
docker exec wan-east vtysh -c \
  "configure terminal" -c "interface tun-west" -c "shutdown"

# Trace should show hop through wan-eu:
docker exec dc-east-host-a traceroute 10.11.1.1

# Restore:
docker exec wan-east vtysh -c \
  "configure terminal" -c "interface tun-west" -c "no shutdown"
```

## Documentation

- [Multi-Region Architecture](docs/multi-region-architecture.md) — Full design document
- [Multi-Region IP Plan](docs/multi-region-ip-plan.md) — IP allocation across all 3 regions
- [Deployment Phases](docs/deployment-phases.md) — 3-phase rollout with AWS CLI commands
- [Cost Estimate](docs/cost-estimate.md) — AWS monthly cost breakdown
- [Architecture Diagrams](docs/diagrams/) — Mermaid diagrams for all components
- [Changelog](CHANGELOG.md) — Fixes and their reasons

## Requirements

- 3 AWS EC2 instances (t3.xlarge minimum) — one per region; stop them when idle
- AWS VPC peering support (cross-region)
- Docker Engine 24.0+
- Containerlab 0.55+
- Ansible core 2.14+ with `community.docker` (optional)
- 4+ vCPU, 16+ GB RAM, 50 GB disk per host

## License

MIT — see repository contents. All bundled tools retain their own licenses.
