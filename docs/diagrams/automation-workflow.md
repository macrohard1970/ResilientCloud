# Automation Workflow

How the deploy scripts, Containerlab topologies, FRR config files, and the Ansible playbook combine to build and configure one region. The same workflow runs independently on each region's EC2 lab host.

## Build Pipeline

```mermaid
flowchart TB
    subgraph REPO["Repository (cloned on each EC2 lab host)"]
        TOPO["topology-dc-east.clab.yml<br/>topology-dc-west.clab.yml<br/>topology-dc-eu.clab.yml"]
        FRR["configs/frr/&lt;device&gt;/<br/>frr.conf · daemons · vtysh.conf"]
        HOSTS["configs/hosts/&lt;region&gt;/*.init.sh"]
        TUN["configs/frr/wan-*/tunnels.sh"]
        BIN["bin/frr_exporter<br/>(scripts/fetch-frr-exporter.sh)"]
        INV["automation/ansible/<br/>inventory-multi-region.yml"]
        MON["monitoring/docker-compose.yml<br/>+ env/&lt;region&gt;.env"]
    end

    SCRIPT["scripts/deploy-multi-region.sh<br/>deploy | destroy | status &lt;region&gt;"]

    subgraph RUNTIME["EC2 lab host (Docker)"]
        CLAB["Containerlab fabric<br/>mgmt network clab-netlab-&lt;region&gt;-mgmt<br/>2 spines · 4 leaves · wan-edge · 4 hosts"]
        NAT["iptables GRE DNAT/masquerade<br/>(scripts/gre-nat.sh)"]
        STACK["Prometheus + Grafana<br/>(+ optional profiles)"]
    end

    ANS["ansible-playbook<br/>playbooks/deploy-configs.yml -l &lt;region&gt;"]

    SCRIPT -->|"1. containerlab deploy --reconfigure"| CLAB
    TOPO --> CLAB
    FRR -->|"bind-mounted"| CLAB
    HOSTS -->|"host init (exec)"| CLAB
    TUN -->|"GRE tunnels from REMOTE_*"| CLAB
    BIN -->|"bind-mounted, started by exec"| CLAB
    SCRIPT -->|"2. only if REMOTE_* set"| NAT
    SCRIPT -->|"3. docker compose up -d"| STACK
    MON --> STACK
    INV --> ANS
    FRR --> ANS
    ANS -->|"later edits: copy, frr-reload.py,<br/>verify BGP / OSPF / ping"| CLAB

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
    ACT -->|"deploy"| D1["containerlab deploy<br/>-t topology-&lt;region&gt;.clab.yml"] --> D2{"REMOTE_* set?"}
    D2 -->|"yes"| D3["gre-nat.sh &lt;region&gt; up"] --> D4["docker compose<br/>--env-file env/&lt;region&gt;.env up -d"]
    D2 -->|"no"| D4
    ACT -->|"destroy"| X1["docker compose down"] --> X2["gre-nat.sh down"] --> X3["containerlab destroy --cleanup"]
    ACT -->|"status"| S1["containerlab inspect"] --> S2["docker compose ps"]
```

| Region | Topology file | Mgmt network | Monitoring env |
|--------|---------------|--------------|----------------|
| dc-east | `topology-dc-east.clab.yml` | `clab-netlab-east-mgmt` 10.255.255.0/24 | `env/dc-east.env` |
| dc-west | `topology-dc-west.clab.yml` | `clab-netlab-west-mgmt` 10.254.255.0/24 | `env/dc-west.env` |
| dc-eu | `topology-dc-eu.clab.yml` | `clab-netlab-eu-mgmt` 10.253.255.0/24 | `env/dc-eu.env` |

`scripts/deploy.sh` does the same for the single-region `topology.clab.yml` (DC-East without the WAN edge). It shares the DC-East names and networks, so run one or the other.

## Ansible Playbook Plays

`automation/ansible/playbooks/deploy-configs.yml` runs four plays. Ansible connects with `docker exec` (`community.docker.docker`), since the FRR and Alpine images have no SSH server. Inventory names equal container names.

```mermaid
sequenceDiagram
    participant A as Ansible (EC2 host)
    participant R as routers (spines, leaves, wan_edges)
    participant S as spines + wan_edges
    participant H as hosts_group (Alpine)

    A->>R: Play 1: vtysh "show version" (FRR up?)
    A->>R: copy frr.conf + daemons (unsafe_writes: bind mounts)
    R-->>A: changed frr.conf → handler frr-reload.py --reload
    A->>S: Play 2: vtysh "show ip bgp summary"
    A->>R: Play 3: vtysh "show ip ospf neighbor"
    A->>H: Play 4 (raw, no Python): ping gateway, ping host-c of the same region
```

## Inventory Structure

```mermaid
graph TB
    ALL["all<br/>ansible_connection: community.docker.docker"] --> E["dc_east<br/>us-east-1 · 10.10.0.0/16"]
    ALL --> W["dc_west<br/>us-west-2 · 10.11.0.0/16"]
    ALL --> EU["dc_eu<br/>eu-west-1 · 10.12.0.0/16"]
    E --> ES["dc_east_spines<br/>dc-east-spine1, dc-east-spine2"]
    E --> EL["dc_east_leaves<br/>dc-east-leaf1..4"]
    E --> EW["dc_east_wan<br/>wan-east"]
    E --> EH["dc_east_hosts<br/>dc-east-host-a..d"]
    W -.->|"same structure"| W2["dc-west-*, wan-west"]
    EU -.->|"same structure"| EU2["dc-eu-*, wan-eu"]

    ALL --> G["Cross-region groups targeted by the playbook:<br/>spines · leaves · wan_edges · routers · hosts_group"]
```

## Notes

- Always limit a run to the local region (`-l dc_east`). The other regions' containers live on other EC2 hosts.
- The playbook finds configs relative to itself (`playbook_dir`), so it works from any directory.
- Changing a `daemons` file needs a node restart (`containerlab deploy ... --reconfigure`); the playbook warns when that happens.
