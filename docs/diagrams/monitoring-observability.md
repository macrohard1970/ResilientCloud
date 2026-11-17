# Monitoring and Observability

The monitoring stack runs on each region's EC2 lab host, started from `monitoring/docker-compose.yml`. Every container joins two Docker networks: the services network (`10.20.0.0/24` in DC-East; `10.21.0.0/24` and `10.22.0.0/24` in the other regions per `scripts/deploy-multi-region.sh`) and the management network (`10.255.255.0/24`), which reaches the FRR routers.

## Components and Data Flow

```mermaid
flowchart LR
    subgraph FABRIC["Containerlab fabric (mgmt 10.255.255.0/24)"]
        SP["spine1 / spine2<br/>.11 / .12"]
        LF["leaf1–leaf4<br/>.21–.24"]
        WAN["wan-edge<br/>.50"]
    end

    subgraph STACK["Monitoring stack (docker compose)"]
        GNMIC["gNMIc<br/>10.20.0.14 · :9804"]
        PROM["Prometheus<br/>10.20.0.10 · :9090<br/>15 s scrape · 30 d retention"]
        SUZ["Suzieq<br/>10.20.0.12 · :8000<br/>60 s poll"]
        GRAF["Grafana<br/>10.20.0.11 · :3000"]
        BAT["Batfish<br/>10.20.0.13 · :9996 / :9000"]
        DNS["dnsmasq<br/>10.20.0.15 · :53<br/>zone netlab.local"]
    end

    CFG[("configs/frr/*<br/>snapshot copied to<br/>monitoring/batfish/networks/")]
    USER["Operator<br/>(via SSH tunnel)"]

    SP -. "gNMI :57400<br/>(targets commented out)" .-> GNMIC
    LF -. "gNMI :57400<br/>(targets commented out)" .-> GNMIC
    GNMIC -->|"/metrics every 10 s"| PROM
    SP -->|"SSH as root"| SUZ
    LF -->|"SSH as root"| SUZ
    PROM -->|"datasource (default)"| GRAF
    SUZ -->|"datasource :8000"| GRAF
    CFG -->|"offline analysis"| BAT
    USER --> GRAF
    USER --> SUZ
    USER --> BAT
    DNS -.->|"name resolution<br/>upstream 8.8.8.8 / 1.1.1.1"| FABRIC

    style GNMIC fill:#f0ad4e,color:#fff
    style PROM fill:#d9534f,color:#fff
    style GRAF fill:#e27d3a,color:#fff
    style SUZ fill:#4a90d9,color:#fff
    style BAT fill:#5cb85c,color:#fff
    style DNS fill:#9d9d9d,color:#fff
```

## What Each Tool Collects

| Tool | Source | Method | Data | Interval |
|------|--------|--------|------|----------|
| gNMIc | spines, leaves | gNMI subscribe (`json_ietf`) | Interface counters, BGP neighbor session state | 10 s |
| Prometheus | gNMIc, Grafana, itself | HTTP scrape | Time-series metrics | 15 s (gNMIc: 10 s) |
| Suzieq | spines, leaves | SSH, `devtype: linux` | interfaces, bgp, ospf, routes, address, lldp, arpnd, vlan, mlag | 60 s |
| Batfish | Copied `frr.conf` snapshots | Offline config parsing | Routing loops, ACL conflicts, reachability | On demand |
| Grafana | Prometheus, Suzieq | Datasource queries | Dashboards | On view |
| dnsmasq | `monitoring/dnsmasq/hosts` | Static hosts file | `*.netlab.local` names | — |

## Telemetry Pipeline

```mermaid
sequenceDiagram
    participant R as FRR router
    participant G as gNMIc
    participant P as Prometheus
    participant GF as Grafana

    G->>R: Subscribe /interfaces/.../counters, /bgp/neighbors/.../session-state
    loop every 10 s
        R-->>G: Sample update
    end
    Note over G: Rename paths to short metric names<br/>(e.g. counters → in-octets, bgp → routing)
    loop every 10 s
        P->>G: GET :9804/metrics
    end
    GF->>P: PromQL query
    P-->>GF: Series for dashboard
```

## Batfish Validation Workflow

```mermaid
flowchart LR
    EDIT["Edit configs/frr/&lt;node&gt;/frr.conf"] --> COPY["Copy to<br/>monitoring/batfish/networks/current/&lt;node&gt;/"]
    COPY --> SNAP["POST :9996/v2/set/snapshot/new-snapshot<br/>network: netlab"]
    SNAP --> CHECK{"Issues found?"}
    CHECK -->|"Yes"| EDIT
    CHECK -->|"No"| DEPLOY["Deploy with Ansible<br/>(see automation-workflow.md)"]
```

## Current Gaps

These are documented here so the diagrams match the config files as they stand.

- **No router telemetry yet.** All gNMIc targets in `monitoring/gnmic/gnmic.yml` are commented out because the FRR gNMI server is not enabled. Until it is, Prometheus only scrapes gNMIc, Grafana, and itself.
- **WAN edge not polled.** Suzieq's device list covers spines and leaves but not the wan-edge router.
- **Per-region config.** The Suzieq and gNMIc files list DC-East management IPs. The other regions reuse the same management range inside their own Docker networks, so the same files apply on each host.
- **Default credentials.** Grafana and gNMIc use `admin`/`admin`.
