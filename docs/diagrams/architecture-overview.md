# Architecture Overview

## AWS Multi-Region Cloud Topology

This diagram shows the high-level three-region AWS architecture with VPC peering full-mesh connecting DC-East, DC-West, and DC-EU.

```mermaid
graph TB
    subgraph "AWS Cloud — 3 Regions"
        subgraph "us-east-1"
            DC_EAST["DC-East<br/>VPC: 10.0.0.0/16<br/>Hosts: 10.10.0.0/16<br/>WAN: AS 65010"]
            EC2_EAST["EC2 Lab Host<br/>t3.xlarge<br/>Containerlab"]
            BASTION_EAST["Bastion<br/>t3.micro<br/>Public IP"]
            DC_EAST --- EC2_EAST
            DC_EAST --- BASTION_EAST
        end

        subgraph "us-west-2"
            DC_WEST["DC-West<br/>VPC: 10.1.0.0/16<br/>Hosts: 10.11.0.0/16<br/>WAN: AS 65020"]
            EC2_WEST["EC2 Lab Host<br/>t3.xlarge<br/>Containerlab"]
            BASTION_WEST["Bastion<br/>t3.micro<br/>Public IP"]
            DC_WEST --- EC2_WEST
            DC_WEST --- BASTION_WEST
        end

        subgraph "eu-west-1"
            DC_EU["DC-EU<br/>VPC: 10.2.0.0/16<br/>Hosts: 10.12.0.0/16<br/>WAN: AS 65030"]
            EC2_EU["EC2 Lab Host<br/>t3.xlarge<br/>Containerlab"]
            BASTION_EU["Bastion<br/>t3.micro<br/>Public IP"]
            DC_EU --- EC2_EU
            DC_EU --- BASTION_EU
        end
    end

    DC_EAST <-->|"VPC Peering<br/>pcx-east-west"| DC_WEST
    DC_EAST <-->|"VPC Peering<br/>pcx-east-eu"| DC_EU
    DC_WEST <-->|"VPC Peering<br/>pcx-west-eu"| DC_EU

    style DC_EAST fill:#4a90d9,color:#fff
    style DC_WEST fill:#e27d3a,color:#fff
    style DC_EU fill:#5cb85c,color:#fff
```

## VPC Subnet Layout Per Region

```mermaid
graph LR
    subgraph "VPC — Each Region"
        VPC["VPC /16<br/>e.g. 10.0.0.0/16"]
        PUB["Public Subnet /24<br/>10.x.1.0/24<br/>Bastion EC2"]
        PRIV["Private Subnet /24<br/>10.x.2.0/24<br/>Lab EC2 (no public IP)"]
        WAN["WAN Subnet /28<br/>10.x.3.0/28<br/>WAN edge ENI"]
        IGW["Internet Gateway"]

        VPC --- PUB
        VPC --- PRIV
        VPC --- WAN
        IGW -.->|"0.0.0.0/0"| PUB
    end

    style VPC fill:#4a90d9,color:#fff
    style PUB fill:#f0ad4e,color:#fff
    style PRIV fill:#5cb85c,color:#fff
    style WAN fill:#d9534f,color:#fff
    style IGW fill:#9d9d9d,color:#fff
```

## Route Table — Full Mesh

Each VPC has routes to both other regions via peering connections:

```mermaid
graph LR
    subgraph "DC-East Route Table"
        RT_E["10.0.0.0/16 → local<br/>10.1.0.0/16 → pcx-east-west<br/>10.2.0.0/16 → pcx-east-eu<br/>0.0.0.0/0 → IGW"]
    end

    subgraph "DC-West Route Table"
        RT_W["10.1.0.0/16 → local<br/>10.0.0.0/16 → pcx-east-west<br/>10.2.0.0/16 → pcx-west-eu<br/>0.0.0.0/0 → IGW"]
    end

    subgraph "DC-EU Route Table"
        RT_EU["10.2.0.0/16 → local<br/>10.0.0.0/16 → pcx-east-eu<br/>10.1.0.0/16 → pcx-west-eu<br/>0.0.0.0/0 → IGW"]
    end

    RT_E <-->|"VPC Peering"| RT_W
    RT_E <-->|"VPC Peering"| RT_EU
    RT_W <-->|"VPC Peering"| RT_EU
```
