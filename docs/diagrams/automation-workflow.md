# Automation Workflow

How the deploy scripts, Containerlab topologies, FRR config files, and the Ansible playbook combine to build and configure one region. The same workflow runs independently on each region's EC2 lab host.

## Build Pipeline

```mermaid
flowchart TB
    subgraph REPO["Repository (cloned on each EC2 lab host)"]
        TOPO["topology-dc-east.clab.yml<br/>topology-dc-west.clab.yml<br/>topology-dc-eu.clab.yml"]
        FRR["configs/frr/&lt;node&gt;/<br/>frr.conf · daemons · vtysh.conf"]
        HOSTS["configs/hosts/*.init.sh"]
        TUN["configs/frr/wan-*/tunnels.sh"]
        INV["automation/ansible/<br/>inventory-multi-region.yml<br/>group_vars/"]
        MON["monitoring/docker-compose.yml"]
    end

    SCRIPT["scripts/deploy-multi-region.sh<br/>deploy | destroy | status &lt;region&gt;"]

    subgraph RUNTIME["EC2 lab host (Docker)"]
        NETS["Docker networks<br/>clab-netlab-&lt;region&gt;-mgmt<br/>clab-netlab-&lt;region&gt;-services"]
        CLAB["Containerlab fabric<br/>2 spines · 4 leaves · wan-edge · 4 hosts"]
        STACK["Monitoring stack"]
    end

    ANS["ansible-playbook<br/>playbooks/deploy-configs.yml"]

    SCRIPT -->|"1. create"| NETS
    SCRIPT -->|"2. containerlab deploy"| CLAB
    TOPO --> CLAB
    FRR -->|"bind-mounted at deploy"| CLAB
    HOSTS -->|"host init"| CLAB
    TUN -->|"GRE tunnels<br/>LOCAL_IP / REMOTE_*"| CLAB
    SCRIPT -->|"3. docker compose up -d"| STACK
    MON --> STACK
    INV --> ANS
    FRR -->|"copy on change"| ANS
    ANS -->|"4. push config, reload FRR,<br/>verify BGP / OSPF / ping"| CLAB

    style SCRIPT fill:#4a90d9,color:#fff
    style ANS fill:#d9534f,color:#fff
    style CLAB fill:#5cb85c,color:#fff
    style STACK fill:#e27d3a,color:#fff
```

## Deploy Script Actions

`scripts/deploy-multi-region.sh <action> <region>` (region defaults to `dc-east`):

```mermaid
flowchart LR
    START["deploy-multi-region.sh"] --> ACT{"action"}
    ACT -->|"deploy"| D1["Create mgmt + services<br/>Docker networks"] --> D2["containerlab deploy<br/>-t topology-&lt;region&gt;.clab.yml"] --> D3["docker compose up -d"] --> D4["containerlab inspect"]
    ACT -->|"destroy"| X1["docker compose down"] --> X2["containerlab destroy --cleanup"]
    ACT -->|"status"| S1["containerlab inspect"] --> S2["docker compose ps"]
```

| Region | Topology file | Mgmt network | Services subnet |
|--------|---------------|--------------|-----------------|
| dc-east | `topology-dc-east.clab.yml` | `clab-netlab-east-mgmt` | 10.20.0.0/24 |
| dc-west | `topology-dc-west.clab.yml` | `clab-netlab-west-mgmt` | 10.21.0.0/24 |
| dc-eu | `topology-dc-eu.clab.yml` | `clab-netlab-eu-mgmt` | 10.22.0.0/24 |

`scripts/deploy.sh` does the same for the original single-region `topology.clab.yml`.

## Ansible Playbook Plays

`automation/ansible/playbooks/deploy-configs.yml` runs four plays in order. Ansible connects as `root` over SSH to each node's management IP from the inventory.

```mermaid
sequenceDiagram
    participant A as Ansible control (EC2 host)
    participant R as routers (spines, leaves, wan-edge)
    participant S as spines
    participant H as hosts_group

    A->>R: Play 1: copy frr.conf + daemons to /etc/frr/
    A->>R: Ensure FRR running (frrinit.sh start)
    R-->>A: Changed files trigger handler: frrinit.sh reload
    A->>S: Play 2: vtysh "show ip bgp summary"
    S-->>A: BGP session table
    A->>R: Play 3: vtysh "show ip ospf neighbor"
    R-->>A: OSPF adjacencies
    A->>H: Play 4: ping own gateway, ping 10.10.3.1
    H-->>A: Return codes
```

## Inventory Structure

```mermaid
graph TB
    ALL["all"] --> E["dc_east<br/>us-east-1 · 10.10.0.0/16"]
    ALL --> W["dc_west<br/>us-west-2 · 10.11.0.0/16"]
    ALL --> EU["dc_eu<br/>eu-west-1 · 10.12.0.0/16"]
    E --> ER["dc_east_routers"]
    E --> EH["dc_east_hosts"]
    ER --> ES["dc_east_spines<br/>spine1, spine2 · AS 65001"]
    ER --> EL["dc_east_leaves<br/>leaf1–4 · AS 65101–65104"]
    ER --> EW["dc_east_wan<br/>wan-east · AS 65010"]
    W -.->|"same structure"| W2["..."]
    EU -.->|"same structure"| EU2["..."]

    GV["group_vars/<br/>routers.yml · spines.yml · leaves.yml"] -.-> ER
```

## Notes

- The playbook resolves config paths as `$PWD/../configs/frr/<node>/`, so run it from the `automation/` directory.
- Play 4's cross-fabric ping target (`10.10.3.1`) is a DC-East address; it verifies intra-region connectivity only.
- GRE tunnel endpoints (`LOCAL_IP`, `REMOTE_WEST`, `REMOTE_EU`, etc.) must be exported before deploying the WAN edge, because they are EC2 private IPs known only after Phase 1.
