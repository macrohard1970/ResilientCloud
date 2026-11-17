# Deployment Phases

Visual companion to [docs/deployment-phases.md](../deployment-phases.md), which has the full AWS CLI commands.

## Timeline

```mermaid
gantt
    title ResilientCloud phased rollout (~65 min)
    dateFormat HH:mm
    axisFormat %H:%M

    section Phase 1 - Independent regions
    DC-East VPC + EC2               :p1a, 00:00, 10m
    DC-West VPC + EC2               :p1b, 00:00, 10m
    DC-EU VPC + EC2                 :p1c, 00:00, 10m
    Install Docker + Containerlab   :p1d, after p1a, 15m
    Deploy fabric + monitoring      :p1e, after p1d, 5m

    section Phase 2 - VPC peering
    Create 3 peering connections    :p2a, after p1e, 5m
    Update 6 route tables           :p2b, after p2a, 5m
    Update security groups          :p2c, after p2b, 5m

    section Phase 3 - WAN edge BGP
    Enable IP forwarding            :p3a, after p2c, 2m
    GRE tunnels + WAN edge configs  :p3b, after p3a, 10m
    Verify BGP + failover test      :p3c, after p3b, 8m
```

## Phase Progression

```mermaid
flowchart LR
    subgraph P1["Phase 1: Isolated regions"]
        direction TB
        E1["DC-East<br/>us-east-1"]
        W1["DC-West<br/>us-west-2"]
        EU1["DC-EU<br/>eu-west-1"]
    end

    subgraph P2["Phase 2: L3 connectivity"]
        direction TB
        E2["DC-East"] <-->|"pcx"| W2["DC-West"]
        E2 <-->|"pcx"| EU2["DC-EU"]
        W2 <-->|"pcx"| EU2
    end

    subgraph P3["Phase 3: Cross-region routing"]
        direction TB
        E3["wan-east<br/>AS 65010"] <-->|"eBGP/GRE"| W3["wan-west<br/>AS 65020"]
        E3 <-->|"eBGP/GRE"| EU3["wan-eu<br/>AS 65030"]
        W3 <-->|"eBGP/GRE"| EU3
    end

    P1 -->|"VPC peering<br/>+ routes + SGs"| P2
    P2 -->|"GRE tunnels<br/>+ BGP + BFD"| P3

    style P1 fill:#f5f5f5
    style P2 fill:#f5f5f5
    style P3 fill:#f5f5f5
```

## Verification Gates

Each phase must pass its checks before the next starts.

```mermaid
flowchart TB
    G1{"Phase 1 gate:<br/>intra-region ping OK<br/>spine BGP sessions Established"}
    G2{"Phase 2 gate:<br/>3 peering connections active<br/>EC2 ↔ EC2 ping across regions"}
    G3{"Phase 3 gate:<br/>wan-edge shows 4 BGP neighbors<br/>host ping 10.11.1.1 / 10.12.1.1<br/>failover reroutes via third region"}
    DONE["Deployment complete"]

    G1 -->|"pass"| G2
    G2 -->|"pass"| G3
    G3 -->|"pass"| DONE
    G1 -->|"fail"| F1["Fix fabric / Ansible configs"]
    G2 -->|"fail"| F2["Check route tables, SGs, peering acceptance"]
    G3 -->|"fail"| F3["Check GRE endpoints, ip_forward, BFD"]
```
