# Network Topology

## Per-Region Spine-Leaf Fabric

Each region runs an identical Containerlab topology: 2 spines, 4 leaves, 4 endpoint hosts, and 1 WAN edge router. The spines peer iBGP with each other and eBGP with every leaf and the WAN edge, with OSPF area 0 as the underlay. Device names carry the region prefix (dc-east-spine1, dc-west-leaf3, ...). Leaves peer eBGP with both spines and advertise their host /24 subnets.

```mermaid
graph TB
    subgraph "Containerlab Fabric (Per Region)"
        SPINE1["spine1<br/>AS 65001<br/>Lo: 10.x.0.1/32"]
        SPINE2["spine2<br/>AS 65001<br/>Lo: 10.x.0.2/32"]

        LEAF1["leaf1<br/>AS 65101<br/>Host: 10.y.1.0/24"]
        LEAF2["leaf2<br/>AS 65102<br/>Host: 10.y.2.0/24"]
        LEAF3["leaf3<br/>AS 65103<br/>Host: 10.y.3.0/24"]
        LEAF4["leaf4<br/>AS 65104<br/>Host: 10.y.4.0/24"]

        WAN["wan-edge<br/>AS 65010/20/30<br/>GRE tunnels to<br/>other regions"]

        HOSTA["host-a<br/>Alpine<br/>10.y.1.1"]
        HOSTB["host-b<br/>Alpine<br/>10.y.2.1"]
        HOSTC["host-c<br/>Alpine<br/>10.y.3.1"]
        HOSTD["host-d<br/>Alpine<br/>10.y.4.1"]
    end

    SPINE1 ===|"iBGP<br/>OSPF"| SPINE2

    SPINE1 -->|"eBGP<br/>/31 P2P"| LEAF1
    SPINE1 -->|"eBGP<br/>/31 P2P"| LEAF2
    SPINE1 -->|"eBGP<br/>/31 P2P"| LEAF3
    SPINE1 -->|"eBGP<br/>/31 P2P"| LEAF4

    SPINE2 -->|"eBGP<br/>/31 P2P"| LEAF1
    SPINE2 -->|"eBGP<br/>/31 P2P"| LEAF2
    SPINE2 -->|"eBGP<br/>/31 P2P"| LEAF3
    SPINE2 -->|"eBGP<br/>/31 P2P"| LEAF4

    SPINE1 -->|"eBGP"| WAN
    SPINE2 -->|"eBGP"| WAN

    LEAF1 --> HOSTA
    LEAF2 --> HOSTB
    LEAF3 --> HOSTC
    LEAF4 --> HOSTD

    style SPINE1 fill:#4a90d9,color:#fff
    style SPINE2 fill:#4a90d9,color:#fff
    style LEAF1 fill:#5cb85c,color:#fff
    style LEAF2 fill:#5cb85c,color:#fff
    style LEAF3 fill:#5cb85c,color:#fff
    style LEAF4 fill:#5cb85c,color:#fff
    style WAN fill:#d9534f,color:#fff
    style HOSTA fill:#f0ad4e,color:#333
    style HOSTB fill:#f0ad4e,color:#333
    style HOSTC fill:#f0ad4e,color:#333
    style HOSTD fill:#f0ad4e,color:#333
```

## Underlay /31 Point-to-Point Links

Each spine-leaf pair uses /31 point-to-point links in OSPF area 0. The WAN edge also has uplinks to both spines.

```mermaid
graph LR
    subgraph "Underlay — DC-East (10.99.0.0/24)"
        S1["spine1"]
        S2["spine2"]
        L1["leaf1"]
        L2["leaf2"]
        L3["leaf3"]
        L4["leaf4"]
        WE["wan-east"]

        S1 -->|"eth1: 10.99.0.0/31"| L1
        S1 -->|"eth2: 10.99.0.2/31"| L2
        S1 -->|"eth3: 10.99.0.4/31"| L3
        S1 -->|"eth4: 10.99.0.6/31"| L4
        S1 ===|"eth5: 10.99.0.16/31"| S2
        S1 -->|"eth6: 10.99.0.18/31"| WE

        S2 -->|"eth1: 10.99.0.8/31"| L1
        S2 -->|"eth2: 10.99.0.10/31"| L2
        S2 -->|"eth3: 10.99.0.12/31"| L3
        S2 -->|"eth4: 10.99.0.14/31"| L4
        S2 -->|"eth6: 10.99.0.20/31"| WE
    end

    style S1 fill:#4a90d9,color:#fff
    style S2 fill:#4a90d9,color:#fff
    style WE fill:#d9534f,color:#fff
    style L1 fill:#5cb85c,color:#fff
    style L2 fill:#5cb85c,color:#fff
    style L3 fill:#5cb85c,color:#fff
    style L4 fill:#5cb85c,color:#fff
```

## Management & Services Networks (Docker-Internal)

These networks exist only inside each EC2 host's Docker namespace. They are not routable across regions.

```mermaid
graph TB
    subgraph "Docker Networks — Per EC2 Host"
        MGMT["Management Network<br/>10.255.255.0/24<br/>(clab-netlab-&lt;east|west|eu&gt;-mgmt)"]
        SVC["Services Network<br/>10.20.0.0/24<br/>(rc-&lt;region&gt;-services)"]

        subgraph "Network Devices"
            S["&lt;region&gt;-spine1/2<br/>.11 .12"]
            L["&lt;region&gt;-leaf1-4<br/>.21 .22 .23 .24"]
            W["wan-&lt;region&gt;<br/>.50"]
            H["&lt;region&gt;-host-a..d<br/>.31 .32 .33 .34"]
        end

        subgraph "Monitoring Containers"
            PROM["Prometheus<br/>.41 (default)"]
            GRAF["Grafana<br/>.42 (default)"]
            SUZ["SuzieQ<br/>.43 (optional)"]
            BAT["Batfish<br/>services only (optional)"]
            DNS["dnsmasq<br/>.46 (optional)"]
        end

        MGMT --- S
        MGMT --- L
        MGMT --- W
        MGMT --- H
        SVC --- PROM
        SVC --- GRAF
        SVC --- SUZ
        SVC --- BAT
        SVC --- DNS
    end

    style MGMT fill:#4a90d9,color:#fff
    style SVC fill:#e27d3a,color:#fff
```

## IP Address Allocation Map

```
AWS VPC LEVEL (routable across regions)
├── 10.0.0.0/16  ── DC-East VPC (us-east-1)
├── 10.1.0.0/16  ── DC-West VPC (us-west-2)
└── 10.2.0.0/16  ── DC-EU VPC (eu-west-1)

CONTAINERLAB INTERNAL (Docker-isolated, BGP-advertised)
├── 10.10.0.0/16 ── DC-East host subnets (advertised)
├── 10.11.0.0/16 ── DC-West host subnets (advertised)
├── 10.12.0.0/16 ── DC-EU host subnets (advertised)
├── 10.255.0.0/24 ── DC-East loopbacks (advertised)
├── 10.254.0.0/24 ── DC-West loopbacks (advertised)
└── 10.253.0.0/24 ── DC-EU loopbacks (advertised)

WAN INTERCONNECT (GRE tunnels over VPC peering)
└── 10.110.0.0/24 ── Inter-region tunnel /30s

DOCKER-INTERNAL (not advertised, unique per region)
├── 10.99.0.0/24    ── DC-East underlay P2P
├── 10.100.0.0/24  ── DC-West underlay P2P
├── 10.200.0.0/24  ── DC-EU underlay P2P
├── 10.255.255.0/24 ── DC-East mgmt
├── 10.254.255.0/24 ── DC-West mgmt
├── 10.253.255.0/24 ── DC-EU mgmt
├── 10.20.0.0/24   ── DC-East services
├── 10.21.0.0/24   ── DC-West services
└── 10.22.0.0/24   ── DC-EU services
```
