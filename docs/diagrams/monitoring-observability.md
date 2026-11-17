# Monitoring and Observability

Each region's EC2 lab host runs its own monitoring stack from `monitoring/docker-compose.yml`, configured by `monitoring/env/<region>.env`. Only Prometheus and Grafana start by default. SuzieQ, Batfish, and dnsmasq are opt-in compose profiles, so they use no resources unless enabled.

Every monitoring container joins two Docker networks: the region's services network (created by compose) and the region's Containerlab management network (created by `containerlab deploy`).

| Region | Mgmt network | Services network | Prometheus | Grafana |
|--------|--------------|------------------|------------|---------|
| dc-east | `clab-netlab-east-mgmt` 10.255.255.0/24 | `rc-dc-east-services` 10.20.0.0/24 | 127.0.0.1:9090 | 127.0.0.1:3000 |
| dc-west | `clab-netlab-west-mgmt` 10.254.255.0/24 | `rc-dc-west-services` 10.21.0.0/24 | 127.0.0.1:9091 | 127.0.0.1:3001 |
| dc-eu | `clab-netlab-eu-mgmt` 10.253.255.0/24 | `rc-dc-eu-services` 10.22.0.0/24 | 127.0.0.1:9092 | 127.0.0.1:3002 |

## Components and Data Flow

```mermaid
flowchart LR
    subgraph FABRIC["Containerlab fabric — mgmt 10.x.255.0/24"]
        SP["&lt;region&gt;-spine1/2<br/>.11 / .12"]
        LF["&lt;region&gt;-leaf1..4<br/>.21–.24"]
        WAN["wan-&lt;region&gt;<br/>.50"]
        EXP["frr_exporter :9342<br/>(in every FRR node)"]
        SP --- EXP
        LF --- EXP
        WAN --- EXP
    end

    subgraph DEFAULT["Default stack"]
        PROM["rc-&lt;region&gt;-prometheus<br/>mgmt .41 · 15 s scrape · 7 d retention"]
        GRAF["rc-&lt;region&gt;-grafana<br/>mgmt .42"]
    end

    subgraph OPTIONAL["Optional profiles"]
        SUZ["rc-&lt;region&gt;-suzieq<br/>--profile suzieq · mgmt .43"]
        BAT["rc-&lt;region&gt;-batfish<br/>--profile batfish"]
        DNS["rc-&lt;region&gt;-dnsmasq<br/>--profile dns · mgmt .46"]
    end

    TGT[("prometheus/targets/&lt;region&gt;.yml<br/>7 FRR nodes")]
    CFG[("configs/frr/*<br/>snapshot copy")]
    USER["Operator<br/>(SSH tunnel to 127.0.0.1)"]

    TGT -->|"file_sd"| PROM
    EXP -->|"HTTP /metrics"| PROM
    PROM -->|"datasource"| GRAF
    FABRIC -.->|"SSH (needs sshd added)"| SUZ
    CFG -->|"offline analysis"| BAT
    DNS -.->|"*.lab.internal names"| FABRIC
    USER --> GRAF
    USER --> PROM
    USER --> BAT

    style PROM fill:#d9534f,color:#fff
    style GRAF fill:#e27d3a,color:#fff
    style EXP fill:#f0ad4e,color:#fff
    style SUZ fill:#4a90d9,color:#fff
    style BAT fill:#5cb85c,color:#fff
    style DNS fill:#9d9d9d,color:#fff
```

## What Each Tool Collects

| Tool | Default | Source | Method | Data |
|------|---------|--------|--------|------|
| frr_exporter | if `bin/frr_exporter` exists | FRR daemon sockets | Runs inside each FRR node | BGP peer state/prefixes, OSPF neighbors, BFD peer state, route counts |
| Prometheus | on | frr_exporter, Grafana, itself | HTTP scrape every 15 s | Time series, labelled `device`, `role`, `region` |
| Grafana | on | Prometheus | Datasource queries | Dashboards (FRR BGP dashboard: grafana.com ID 22943) |
| SuzieQ | `--profile suzieq` | FRR nodes | SSH every poll | interfaces, BGP, OSPF, routes, LLDP |
| Batfish | `--profile batfish` | Snapshot of `frr.conf` files | Offline parsing via pybatfish | Init issues, BGP session compatibility, reachability |
| dnsmasq | `--profile dns` | `dnsmasq/hosts.<region>` | Static hosts | `dc-east-spine1.lab.internal`, ... |

## Metrics Pipeline

```mermaid
sequenceDiagram
    participant D as FRR daemons (bgpd, ospfd, bfdd, zebra)
    participant X as frr_exporter (same container, :9342)
    participant P as rc-<region>-prometheus
    participant G as rc-<region>-grafana

    Note over X: Started by the topology exec step<br/>when bin/frr_exporter is present
    loop every 15 s
        P->>X: GET http://<mgmt-ip>:9342/metrics
        X->>D: show ... json over Unix sockets
        D-->>X: JSON
        X-->>P: frr_bgp_peer_state, frr_ospf_neighbors, frr_bfd_peer_state, ...
    end
    G->>P: PromQL
    P-->>G: Series per device
```

## Batfish Validation Workflow

```mermaid
flowchart LR
    EDIT["Edit configs/frr/&lt;device&gt;/frr.conf"] --> COPY["Copy to monitoring/batfish/snapshots/&lt;region&gt;/configs/&lt;device&gt;.cfg"]
    COPY --> RUN["--profile batfish up -d<br/>pybatfish init_snapshot()"]
    RUN --> CHECK{"Issues found?"}
    CHECK -->|"Yes"| EDIT
    CHECK -->|"No"| DEPLOY["ansible-playbook ... -l &lt;region&gt;<br/>(see automation-workflow.md)"]
```

## Known Limits

- **Metrics need the binary.** If `scripts/fetch-frr-exporter.sh` was not run before `containerlab deploy`, the routers run normally and the Prometheus `frr` targets show as down.
- **SuzieQ needs SSH.** The FRR image has no SSH server. The steps to add one are in `monitoring/README.md`.
- **Default credentials.** Grafana is `admin`/`admin` unless `GRAFANA_ADMIN_PASSWORD` is exported first. All ports bind to 127.0.0.1 only.
