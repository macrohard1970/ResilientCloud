# BGP Peering Topology

## ASN Allocation

Internal fabric ASNs (65001, 65101-65104) are reused across all three regions because each Containerlab fabric is Docker-isolated and never peers externally. Only the WAN edge ASNs (65010, 65020, 65030) are unique and visible across regions.

```mermaid
graph TB
    subgraph "DC-East (us-east-1)"
        WE_E["wan-east<br/>AS 65010<br/>Lo: 10.255.0.100"]
        SP_E1["spine1<br/>AS 65001"]
        SP_E2["spine2<br/>AS 65001"]
        LF_E1["leaf1<br/>AS 65101"]
        LF_E2["leaf2<br/>AS 65102"]
        LF_E3["leaf3<br/>AS 65103"]
        LF_E4["leaf4<br/>AS 65104"]

        WE_E -->|"eBGP"| SP_E1
        WE_E -->|"eBGP"| SP_E2
        SP_E1 -->|"eBGP"| LF_E1
        SP_E1 -->|"eBGP"| LF_E2
        SP_E1 -->|"eBGP"| LF_E3
        SP_E1 -->|"eBGP"| LF_E4
        SP_E2 -->|"eBGP"| LF_E1
        SP_E2 -->|"eBGP"| LF_E2
        SP_E2 -->|"eBGP"| LF_E3
        SP_E2 -->|"eBGP"| LF_E4
        SP_E1 ===|"iBGP"| SP_E2
    end

    subgraph "DC-West (us-west-2)"
        WE_W["wan-west<br/>AS 65020<br/>Lo: 10.254.0.100"]
        SP_W1["spine1<br/>AS 65001"]
        SP_W2["spine2<br/>AS 65001"]
        LF_W1["leaf1<br/>AS 65101"]
        LF_W2["leaf2<br/>AS 65102"]
        LF_W3["leaf3<br/>AS 65103"]
        LF_W4["leaf4<br/>AS 65104"]

        WE_W -->|"eBGP"| SP_W1
        WE_W -->|"eBGP"| SP_W2
        SP_W1 -->|"eBGP"| LF_W1
        SP_W1 -->|"eBGP"| LF_W2
        SP_W1 -->|"eBGP"| LF_W3
        SP_W1 -->|"eBGP"| LF_W4
        SP_W2 -->|"eBGP"| LF_W1
        SP_W2 -->|"eBGP"| LF_W2
        SP_W2 -->|"eBGP"| LF_W3
        SP_W2 -->|"eBGP"| LF_W4
        SP_W1 ===|"iBGP"| SP_W2
    end

    subgraph "DC-EU (eu-west-1)"
        WE_EU["wan-eu<br/>AS 65030<br/>Lo: 10.253.0.100"]
        SP_EU1["spine1<br/>AS 65001"]
        SP_EU2["spine2<br/>AS 65001"]
        LF_EU1["leaf1<br/>AS 65101"]
        LF_EU2["leaf2<br/>AS 65102"]
        LF_EU3["leaf3<br/>AS 65103"]
        LF_EU4["leaf4<br/>AS 65104"]

        WE_EU -->|"eBGP"| SP_EU1
        WE_EU -->|"eBGP"| SP_EU2
        SP_EU1 -->|"eBGP"| LF_EU1
        SP_EU1 -->|"eBGP"| LF_EU2
        SP_EU1 -->|"eBGP"| LF_EU3
        SP_EU1 -->|"eBGP"| LF_EU4
        SP_EU2 -->|"eBGP"| LF_EU1
        SP_EU2 -->|"eBGP"| LF_EU2
        SP_EU2 -->|"eBGP"| LF_EU3
        SP_EU2 -->|"eBGP"| LF_EU4
        SP_EU1 ===|"iBGP"| SP_EU2
    end

    WE_E ===|"eBGP<br/>GRE tunnel<br/>10.110.0.0/30<br/>BFD"| WE_W
    WE_E ===|"eBGP<br/>GRE tunnel<br/>10.110.0.4/30<br/>BFD"| WE_EU
    WE_W ===|"eBGP<br/>GRE tunnel<br/>10.110.0.8/30<br/>BFD"| WE_EU

    style WE_E fill:#d9534f,color:#fff
    style WE_W fill:#d9534f,color:#fff
    style WE_EU fill:#d9534f,color:#fff
    style SP_E1 fill:#4a90d9,color:#fff
    style SP_E2 fill:#4a90d9,color:#fff
    style SP_W1 fill:#4a90d9,color:#fff
    style SP_W2 fill:#4a90d9,color:#fff
    style SP_EU1 fill:#4a90d9,color:#fff
    style SP_EU2 fill:#4a90d9,color:#fff
```

## WAN Edge Peering (Inter-Region eBGP Full Mesh)

```mermaid
graph LR
    WE_E["wan-east<br/>AS 65010<br/>DC-East"]

    WE_E -->|"Advertises:<br/>10.10.0.0/16<br/>(+ transit /16s)"| WE_W["wan-west<br/>AS 65020<br/>DC-West"]
    WE_E -->|"Advertises:<br/>10.10.0.0/16<br/>(+ transit /16s)"| WE_EU["wan-eu<br/>AS 65030<br/>DC-EU"]

    WE_W -->|"Advertises:<br/>10.11.0.0/16<br/>(+ transit /16s)"| WE_E
    WE_W -->|"Advertises:<br/>10.11.0.0/16<br/>(+ transit /16s)"| WE_EU

    WE_EU -->|"Advertises:<br/>10.12.0.0/16<br/>(+ transit /16s)"| WE_E
    WE_EU -->|"Advertises:<br/>10.12.0.0/16<br/>(+ transit /16s)"| WE_W

    style WE_E fill:#d9534f,color:#fff
    style WE_W fill:#d9534f,color:#fff
    style WE_EU fill:#d9534f,color:#fff
```

## BGP Route Propagation Flow

```mermaid
flowchart TB
    subgraph "What crosses the WAN (inter-region)"
        OUT["route-map WAN-OUT<br/>Permit: own /16 aggregate<br/>Permit: remote /16s (transit)<br/>Deny: everything else"]
        IN["route-map WAN-IN<br/>Permit: remote /16 aggregates<br/>Deny: everything else"]
    end

    subgraph "What stays in the local fabric"
        LOCAL["Local Fabric Only:<br/>• Individual /24 host subnets<br/>• Loopbacks<br/>• Underlay /31 P2P links<br/>• Management /24<br/>• Services /24"]
    end

    LEAF["Leaf advertises<br/>host /24 to spines"]
    SPINE["Spine reflects /24<br/>to all leaves + WAN edge"]
    WAN["WAN edge aggregates<br/>4 × /24 → /16"]
    REMOTE["Remote WAN edge<br/>receives /16"]

    LEAF --> SPINE
    SPINE --> WAN
    WAN -->|"WAN-OUT<br/>/16 aggregates only"| REMOTE
    WAN --> LOCAL

    style OUT fill:#5cb85c,color:#fff
    style IN fill:#5cb85c,color:#fff
    style LOCAL fill:#d9534f,color:#fff
    style WAN fill:#d9534f,color:#fff
```

## GRE Tunnel Mesh

```mermaid
graph TB
    subgraph "WAN Tunnel Network — 10.110.0.0/24"
        TUN_EW["East ↔ West<br/>10.110.0.0/30<br/>wan-east: .1<br/>wan-west: .2"]
        TUN_EEU["East ↔ EU<br/>10.110.0.4/30<br/>wan-east: .5<br/>wan-eu: .6"]
        TUN_WEU["West ↔ EU<br/>10.110.0.8/30<br/>wan-west: .9<br/>wan-eu: .10"]
    end

    EC2_E["DC-East EC2<br/>VPC Private IP"]
    EC2_W["DC-West EC2<br/>VPC Private IP"]
    EC2_EU["DC-EU EC2<br/>VPC Private IP"]

    EC2_E -->|"VPC Peering"| EC2_W
    EC2_E -->|"VPC Peering"| EC2_EU
    EC2_W -->|"VPC Peering"| EC2_EU

    TUN_EW -.->|"GRE encapsulated<br/>over VPC peering"| EC2_E
    TUN_EW -.->|"GRE encapsulated<br/>over VPC peering"| EC2_W
    TUN_EEU -.->|"GRE encapsulated"| EC2_E
    TUN_EEU -.->|"GRE encapsulated"| EC2_EU
    TUN_WEU -.->|"GRE encapsulated"| EC2_W
    TUN_WEU -.->|"GRE encapsulated"| EC2_EU

    style TUN_EW fill:#d9534f,color:#fff
    style TUN_EEU fill:#d9534f,color:#fff
    style TUN_WEU fill:#d9534f,color:#fff
    style EC2_E fill:#4a90d9,color:#fff
    style EC2_W fill:#4a90d9,color:#fff
    style EC2_EU fill:#4a90d9,color:#fff
```
