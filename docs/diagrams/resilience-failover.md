# Resilience and Failover

## Failure Detection

Each WAN edge runs BFD on its eBGP sessions to the two remote WAN edges. BFD uses a 300 ms transmit/receive interval with a detect multiplier of 3, so a dead tunnel is detected in about 900 ms. If BFD is unavailable, BGP keepalive/hold timers (3 s / 9 s) act as the fallback.

```mermaid
sequenceDiagram
    participant E as wan-east (AS 65010)
    participant W as wan-west (AS 65020)
    participant EU as wan-eu (AS 65030)

    Note over E,W: Normal: direct path over tun-west (10.110.0.0/30)
    E->>W: BFD hello every 300 ms
    W->>E: BFD hello every 300 ms

    Note over E,W: tun-west fails (peering link or tunnel down)
    E--xW: 3 missed hellos (~900 ms)
    Note over E: BFD down → BGP session to 10.254.0.100 torn down
    Note over E: Withdraws direct path to 10.11.0.0/16

    EU->>E: Already advertising 10.11.0.0/16 (AS path 65030 65020)
    Note over E: Best path is now via wan-eu
    E->>EU: Traffic to DC-West via tun-eu
    EU->>W: Forwarded via tun-west-eu (10.110.0.8/30)
```

## Normal State vs. Single-Link Failure

```mermaid
graph LR
    subgraph "Normal — direct paths"
        E1["DC-East<br/>wan-east"] ===|"tun-west<br/>AS path: 65020"| W1["DC-West<br/>wan-west"]
        E1 ===|"tun-eu"| EU1["DC-EU<br/>wan-eu"]
        W1 ===|"tun-eu"| EU1
    end

    subgraph "East↔West down — reroute through EU"
        E2["DC-East<br/>wan-east"] -.-x|"tun-west DOWN"| W2["DC-West<br/>wan-west"]
        E2 ==>|"10.11.0.0/16<br/>AS path: 65030 65020"| EU2["DC-EU<br/>wan-eu"]
        EU2 ==>|"transit"| W2
    end

    style E1 fill:#4a90d9,color:#fff
    style W1 fill:#e27d3a,color:#fff
    style EU1 fill:#5cb85c,color:#fff
    style E2 fill:#4a90d9,color:#fff
    style W2 fill:#e27d3a,color:#fff
    style EU2 fill:#5cb85c,color:#fff
```

## Failure Scenarios

| Failure | Detection | Effect | Recovery path |
|---------|-----------|--------|---------------|
| One GRE tunnel / VPC peering link | BFD ~900 ms | Direct path withdrawn | Transit via third region (longer AS path) |
| Two inter-region links | BFD ~900 ms | Isolated region loses WAN reachability | None until a link returns; local fabric unaffected |
| WAN edge router in one region | BFD on all its sessions | Region's /16 withdrawn from remote regions | Intra-region traffic continues; cross-region down for that region |
| One spine in a region | BFD / OSPF | ECMP drops to the remaining spine | Remaining spine reflects all routes |
| One leaf | Host link down | Hosts behind that leaf unreachable | None (single-homed hosts in the lab) |
| Entire region (EC2 host down) | BFD on both remote sessions | Region's /16 withdrawn | Other two regions keep a direct path |

## Failover Decision Flow

```mermaid
flowchart TB
    START["Packet from DC-East<br/>to 10.11.0.0/16"]
    Q1{"BGP session<br/>wan-east ↔ wan-west<br/>up?"}
    DIRECT["Forward over tun-west<br/>AS path: 65020"]
    Q2{"BGP session<br/>wan-east ↔ wan-eu<br/>up and wan-eu has<br/>10.11.0.0/16?"}
    TRANSIT["Forward over tun-eu<br/>AS path: 65030 65020"]
    DROP["No route<br/>DC-West unreachable"]

    START --> Q1
    Q1 -->|"Yes"| DIRECT
    Q1 -->|"No (BFD down)"| Q2
    Q2 -->|"Yes"| TRANSIT
    Q2 -->|"No"| DROP

    style DIRECT fill:#5cb85c,color:#fff
    style TRANSIT fill:#f0ad4e,color:#fff
    style DROP fill:#d9534f,color:#fff
```

## Failover Test

See the "Test Failover" section of the [README](../../README.md). Shut down `tun-west` on wan-east, then confirm with `traceroute 10.11.1.1` that the path now passes through wan-eu.
