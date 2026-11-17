# Security and Access

Trust boundaries, the operator access path, and the security group rules defined in [docs/deployment-phases.md](../deployment-phases.md). The same pattern applies in all three regions.

## Trust Boundaries

```mermaid
flowchart TB
    NET["Internet"]

    subgraph VPC["VPC (10.x.0.0/16) — per region"]
        subgraph PUB["Public subnet 10.x.1.0/24"]
            BAS["Bastion<br/>t3.micro · public IP"]
        end
        subgraph PRIV["Private subnet 10.x.2.0/24 — no public IP"]
            subgraph EC2["EC2 lab host (t3.xlarge)"]
                subgraph DOCKER["Docker-internal — not routable from VPC"]
                    FAB["Containerlab fabric<br/>mgmt 10.255.255.0/24<br/>hosts 10.1x.0.0/16"]
                    MON["Monitoring stack<br/>services 10.2x.0.0/24"]
                end
            end
        end
    end

    PEER["Other regions<br/>(VPC peering)"]

    NET -->|"SSH :22<br/>public SG"| BAS
    BAS -->|"SSH :22<br/>private SG (source: public SG)"| EC2
    PEER <-->|"GRE (IP proto 47)<br/>from peer VPC CIDRs<br/>DNAT to wan-edge by gre-nat.sh"| EC2
    EC2 -->|"127.0.0.1 only<br/>Grafana 300x · Prometheus 909x · Batfish (opt.)"| MON

    style NET fill:#d9534f,color:#fff
    style BAS fill:#f0ad4e,color:#fff
    style EC2 fill:#4a90d9,color:#fff
    style DOCKER fill:#5cb85c,color:#fff
```

## Operator Access Path

The lab host has no public IP. Reach it, and the dashboards on it, through the bastion.

```mermaid
sequenceDiagram
    participant O as Operator
    participant B as Bastion (public subnet)
    participant L as EC2 lab host (private subnet)
    participant C as Containers

    O->>B: SSH :22 (key pair networking-lab)
    B->>L: SSH :22 (ProxyJump)
    O->>L: SSH local forward, e.g. -L 3000:localhost:3000
    L->>C: docker exec / vtysh / published ports
    C-->>O: Grafana, Prometheus, Suzieq, Batfish via localhost
```

Example (replace placeholders):

```bash
ssh -i ~/.ssh/networking-lab.pem \
  -J ec2-user@<bastion-public-ip> \
  -L 3000:localhost:3000 -L 9090:localhost:9090 \
  ec2-user@<lab-host-private-ip>
```

## Security Group Rules

| SG | Direction | Protocol / Port | Source | Purpose | Phase |
|----|-----------|-----------------|--------|---------|-------|
| Public (bastion) | Inbound | TCP 22 | 0.0.0.0/0 | Operator SSH | 1 |
| Private (lab host) | Inbound | TCP 22 | Public SG | SSH from bastion only | 1 |
| Private (lab host) | Inbound | All | Own VPC CIDR | Intra-VPC traffic | 1 |
| Private (lab host) | Inbound | All | Each peer VPC CIDR (2 rules) | GRE tunnels, BGP, cross-region data | 2 |
| Both | Outbound | All | 0.0.0.0/0 | AWS default | — |

```mermaid
graph LR
    ANY["0.0.0.0/0"] -->|"TCP 22"| SGP["Public SG<br/>(bastion)"]
    SGP -->|"TCP 22"| SGL["Private SG<br/>(lab host)"]
    VPCL["Own VPC /16"] -->|"all"| SGL
    VPCA["Peer VPC /16 #1"] -->|"all"| SGL
    VPCB["Peer VPC /16 #2"] -->|"all"| SGL

    style SGP fill:#f0ad4e,color:#fff
    style SGL fill:#4a90d9,color:#fff
```

## Secrets and Credentials

| Item | Where it lives | In repo? |
|------|----------------|----------|
| EC2 SSH key pair | `~/.ssh/networking-lab*.pem` on the operator machine | No (`*.pem` in `.gitignore`) |
| Grafana admin | `GRAFANA_ADMIN_PASSWORD` env var | No (falls back to lab default `admin`) |
| Ansible to routers | `docker exec` on the lab host | No credentials needed |
| SuzieQ SSH key (optional) | `monitoring/suzieq/ssh/` | No (git-ignored) |

## Hardening Notes (lab vs. production)

These choices fit a lab and should change for anything longer-lived:

- Restrict the bastion's SSH rule from `0.0.0.0/0` to your own IP, or replace the bastion with AWS Systems Manager Session Manager.
- Narrow the cross-region rule from "all traffic" to GRE (IP protocol 47) between the lab hosts' private IPs.
- Set `GRAFANA_ADMIN_PASSWORD` (or pull it from AWS Secrets Manager) instead of the `admin` default.
- GRE is unencrypted. Traffic stays on the AWS backbone over VPC peering, but add IPsec if confidentiality between regions matters.
