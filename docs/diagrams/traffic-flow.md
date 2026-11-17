# Traffic Flow

## Cross-Region Traffic Path

This diagram traces the path of a packet from a host in DC-East to a host in DC-West, showing how traffic flows through the local fabric, WAN edge, GRE tunnel, VPC peering, and remote fabric.

```mermaid
flowchart TB
    START["host-a (DC-East)<br/>10.10.1.1<br/>ping → 10.11.1.1"]

    STEP1["1. host-a → leaf1<br/>Gateway: 10.10.1.254<br/>(directly connected)"]

    STEP2["2. leaf1 has route to 10.11.0.0/16<br/>via spine1/spine2<br/>(learned from wan-east via BGP)"]

    STEP3["3. spine1 → wan-east<br/>Underlay /31 link<br/>(OSPF route to wan-east loopback)"]

    STEP4["4. wan-east → GRE tunnel<br/>tun-west: 10.110.0.1/30<br/>Encapsulates in GRE<br/>Src: wan-east mgmt IP → NAT to EC2-East VPC IP<br/>Dst: EC2-West VPC IP"]

    STEP5["5. GRE packet traverses<br/>VPC Peering connection<br/>10.0.0.0/16 → 10.1.0.0/16<br/>(AWS backbone)"]

    STEP6["6. EC2-West DNATs GRE to wan-west<br/>Decapsulates on<br/>tun-east: 10.110.0.2/30"]

    STEP7["7. wan-west → spine1/spine2<br/>Has route to 10.11.1.0/24<br/>(learned from local leaf via BGP)"]

    STEP8["8. spine → leaf1 (DC-West)<br/>Re-advertised over eBGP<br/>(has 10.11.1.0/24)"]

    STEP9["9. leaf1 → host-a (DC-West)<br/>10.11.1.1<br/>(directly connected)"]

    START --> STEP1
    STEP1 --> STEP2
    STEP2 --> STEP3
    STEP3 --> STEP4
    STEP4 --> STEP5
    STEP5 --> STEP6
    STEP6 --> STEP7
    STEP7 --> STEP8
    STEP8 --> STEP9

    style START fill:#5cb85c,color:#fff
    style STEP4 fill:#d9534f,color:#fff
    style STEP5 fill:#e27d3a,color:#fff
    style STEP6 fill:#d9534f,color:#fff
    style STEP9 fill:#5cb85c,color:#fff
```

## Route Learning — Step by Step

```mermaid
flowchart LR
    subgraph "DC-East"
        EA["leaf1<br/>networks 10.10.1.0/24"]
        EB["spine1/spine2<br/>re-advertises (eBGP) to<br/>wan-east + all leaves"]
        EC["wan-east<br/>aggregates to<br/>10.10.0.0/16"]
    end

    subgraph "WAN"
        WD["eBGP over GRE<br/>wan-east → wan-west<br/>advertises 10.10.0.0/16"]
        WE["eBGP over GRE<br/>wan-east → wan-eu<br/>advertises 10.10.0.0/16"]
    end

    subgraph "DC-West"
        WF["wan-west<br/>receives 10.10.0.0/16<br/>injects to spines"]
        WG["spine1/spine2<br/>re-advertises (eBGP) to<br/>all leaves"]
        WH["leaf1-4<br/>install route<br/>10.10.0.0/16 via spine"]
    end

    subgraph "DC-EU"
        WI["wan-eu<br/>receives 10.10.0.0/16<br/>injects to spines"]
        WJ["spine1/spine2<br/>re-advertises (eBGP) to<br/>all leaves"]
        WK["leaf1-4<br/>install route<br/>10.10.0.0/16 via spine"]
    end

    EA --> EB
    EB --> EC
    EC --> WD
    EC --> WE
    WD --> WF
    WF --> WG
    WG --> WH
    WE --> WI
    WI --> WJ
    WJ --> WK

    style EA fill:#5cb85c,color:#fff
    style EC fill:#d9534f,color:#fff
    style WD fill:#e27d3a,color:#fff
    style WE fill:#e27d3a,color:#fff
    style WF fill:#d9534f,color:#fff
    style WI fill:#d9534f,color:#fff
```

## BGP Path Selection — Direct vs Transitive

With the full mesh, each WAN edge has two paths to each remote region. BGP prefers the shorter AS path (direct), and the transitive path through the third region serves as backup.

```mermaid
flowchart TB
    WE["wan-east<br/>AS 65010"]
    WW["wan-west<br/>AS 65020"]
    WEU["wan-eu<br/>AS 65030"]

    WE -->|"Path 1: DIRECT (preferred)<br/>1 hop via GRE tunnel<br/>AS path: 65020<br/>Metric: shortest"| WW

    WE -->|"Path 2: VIA EU (backup)<br/>2 hops through wan-eu<br/>AS path: 65030 65020<br/>Metric: longer AS path"| WEU

    WEU -->|"Backup leg<br/>AS path: 65020"| WW

    style WE fill:#d9534f,color:#fff
    style WW fill:#d9534f,color:#fff
    style WEU fill:#d9534f,color:#fff
```

## Data Plane vs Control Plane

```mermaid
graph TB
    subgraph "Control Plane (BGP)"
        CP_E["wan-east<br/>BGP sessions:<br/>• spine1 (AS 65001)<br/>• spine2 (AS 65001)<br/>• wan-west (AS 65020)<br/>• wan-eu (AS 65030)"]
        CP_W["wan-west<br/>BGP sessions:<br/>• spine1 (AS 65001)<br/>• spine2 (AS 65001)<br/>• wan-east (AS 65010)<br/>• wan-eu (AS 65030)"]
        CP_EU["wan-eu<br/>BGP sessions:<br/>• spine1 (AS 65001)<br/>• spine2 (AS 65001)<br/>• wan-east (AS 65010)<br/>• wan-west (AS 65020)"]

        CP_E <-->|"BGP over GRE<br/>BFD 300ms×3"| CP_W
        CP_E <-->|"BGP over GRE<br/>BFD 300ms×3"| CP_EU
        CP_W <-->|"BGP over GRE<br/>BFD 300ms×3"| CP_EU
    end

    subgraph "Data Plane (User Traffic)"
        DP_E["DC-East hosts<br/>10.10.0.0/16"]
        DP_W["DC-West hosts<br/>10.11.0.0/16"]
        DP_EU["DC-EU hosts<br/>10.12.0.0/16"]

        DP_E -->|"GRE encapsulated<br/>user traffic"| DP_W
        DP_E -->|"GRE encapsulated<br/>user traffic"| DP_EU
        DP_W -->|"GRE encapsulated<br/>user traffic"| DP_EU
    end

    style CP_E fill:#4a90d9,color:#fff
    style CP_W fill:#4a90d9,color:#fff
    style CP_EU fill:#4a90d9,color:#fff
    style DP_E fill:#5cb85c,color:#fff
    style DP_W fill:#5cb85c,color:#fff
    style DP_EU fill:#5cb85c,color:#fff
```
