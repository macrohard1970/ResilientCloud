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
    │ spine1  │═════════│ spine2  │    FRR (AS 65001, iBGP, route reflectors)
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
| Telemetry | gNMIc | BSD-3-Clause |
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
├── configs/
│   ├── frr/
│   │   ├── spine1/ spine2/ leaf1-4/      # DC-East (original + WAN edge)
│   │   ├── dc-west-spine1/2/ leaf1-4/   # DC-West
│   │   ├── dc-eu-spine1/2/ leaf1-4/     # DC-EU
│   │   └── wan-east/ wan-west/ wan-eu/   # WAN edge routers
│   └── hosts/
│       ├── host-a..d.init.sh            # DC-East hosts
│       ├── dc-west/host-a..d.init.sh    # DC-West hosts
│       └── dc-eu/host-a..d.init.sh      # DC-EU hosts
├── automation/ansible/
│   ├── inventory.yml                   # Single-region inventory
│   ├── inventory-multi-region.yml      # Multi-region inventory
│   ├── group_vars/                     # Per-group variables
│   └── playbooks/deploy-configs.yml     # Config deployment playbook
├── monitoring/                         # Prometheus, Grafana, Suzieq, Batfish, gNMIc, dnsmasq
├── scripts/
│   ├── deploy.sh                       # Single-region deploy
│   └── deploy-multi-region.sh          # Multi-region deploy/destroy/status
├── topology.clab.yml                   # DC-East single-region topology
├── topology-dc-east.clab.yml           # DC-East with WAN edge
├── topology-dc-west.clab.yml           # DC-West with WAN edge
└── topology-dc-eu.clab.yml             # DC-EU with WAN edge
```

## Quick Start

### Phase 1: Deploy Independent Regions

Each region deploys as a standalone Containerlab lab on an EC2 instance:

```bash
# On each EC2 host (DC-East, DC-West, DC-EU):
git clone https://github.com/macrohard80/ResilientCloud.git ResilientCloud && cd ResilientCloud

# Deploy the region-specific topology
sudo containerlab deploy -t topology-dc-east.clab.yml   # or -dc-west / -dc-eu

# Push FRR configs via Ansible
ansible-playbook -i automation/ansible/inventory-multi-region.yml \
  automation/ansible/playbooks/deploy-configs.yml

# Start monitoring stack
cd monitoring && docker compose up -d
```

### Phase 2: VPC Peering Full-Mesh

Create cross-region VPC peering connections and update route tables. See `docs/deployment-phases.md` for the full AWS CLI commands.

### Phase 3: WAN Edge BGP

After VPC peering is active, set the GRE tunnel endpoint IPs and deploy WAN edge configs:

```bash
# On DC-East EC2 host, set remote IPs for GRE tunnels:
export LOCAL_IP=<dc-east-private-ip>
export REMOTE_WEST=<dc-west-private-ip>
export REMOTE_EU=<dc-eu-private-ip>

# Redeploy with WAN edge configs (Ansible or manual)
ansible-playbook -i automation/ansible/inventory-multi-region.yml \
  automation/ansible/playbooks/deploy-configs.yml
```

### Verify Cross-Region Connectivity

```bash
# DC-East → DC-West
docker exec clab-netlab-east-host-a ping -c 3 10.11.1.1

# DC-East → DC-EU
docker exec clab-netlab-east-host-a ping -c 3 10.12.1.1

# DC-West → DC-EU
docker exec clab-netlab-west-host-a ping -c 3 10.12.1.1

# Show BGP sessions on WAN edge
docker exec clab-netlab-east-wan-east vtysh -c "show ip bgp summary"

# Trace cross-region path
docker exec clab-netlab-east-host-a traceroute 10.11.1.1
```

### Test Failover

```bash
# Shut down East↔West tunnel, verify traffic reroutes through EU:
docker exec clab-netlab-east-wan-east vtysh -c \
  "configure terminal" -c "interface tun-west" -c "shutdown"

# Trace should show hop through wan-eu:
docker exec clab-netlab-east-host-a traceroute 10.11.1.1

# Restore:
docker exec clab-netlab-east-wan-east vtysh -c \
  "configure terminal" -c "interface tun-west" -c "no shutdown"
```

## Documentation

- [Multi-Region Architecture](docs/multi-region-architecture.md) — Full design document
- [Multi-Region IP Plan](docs/multi-region-ip-plan.md) — IP allocation across all 3 regions
- [Deployment Phases](docs/deployment-phases.md) — 3-phase rollout with AWS CLI commands
- [Cost Estimate](docs/cost-estimate.md) — AWS monthly cost breakdown
- [Architecture Diagrams](docs/diagrams/) — Mermaid diagrams for all components

## Requirements

- 3 AWS EC2 instances (t3.xlarge minimum, t3.2xlarge recommended) — one per region
- AWS VPC peering support (cross-region)
- Docker Engine 24.0+
- Containerlab 0.55+
- Ansible 2.14+
- 4+ vCPU, 16+ GB RAM, 50 GB disk per host

## License

MIT — see repository contents. All bundled tools retain their own licenses.
