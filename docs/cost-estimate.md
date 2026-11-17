# Cost & Credit Estimate

## Executive Summary

| Deployment | Monthly Cost | Notes |
|-----------|-------------|-------|
| **Local (laptop/desktop/server)** | **$0** | Recommended. All tools are free. |
| AWS EC2 — On-Demand (min spec) | ~$125/mo | t3.xlarge, 4 vCPU, 16 GB |
| AWS EC2 — On-Demand (recommended) | ~$247/mo | t3.2xlarge, 8 vCPU, 32 GB |
| AWS EC2 — Spot (min spec) | ~$35/mo | t3.xlarge, interruptible |
| AWS EC2 — Spot (recommended) | ~$67/mo | t3.2xlarge, interruptible |

**Verdict:** The lab is designed to run locally on any Linux host and costs **$0 in software**. Cloud deployment is optional and only needed if you lack a suitable local machine. Whether available credits suffice depends on your credit balance and how long you keep the cloud instance running (see analysis below).

---

## 1. Software Licensing Costs: $0

Every component in this lab is free and open-source:

| Component | License | Cost |
|-----------|---------|------|
| Containerlab | BSD-3-Clause | Free |
| FRRouting (FRR) | GPL-2.0 | Free |
| Alpine Linux | MIT | Free |
| Ansible | GPL-3.0 | Free |
| Prometheus | Apache-2.0 | Free |
| Grafana (OSS edition) | AGPL-3.0 | Free |
| Suzieq | Apache-2.0 | Free |
| Batfish | Apache-2.0 | Free |
| frr_exporter | MIT | Free |
| dnsmasq | GPL-2.0 | Free |
| Docker Engine | Apache-2.0 | Free |

**No paid licenses, subscriptions, or per-node fees.**

---

## 2. Local Deployment: $0

Running the lab on a local Linux host costs nothing beyond the hardware you already own.

### Minimum requirements
| Resource | Minimum | Recommended |
|----------|---------|-------------|
| CPU | 4 vCPU | 8+ vCPU |
| RAM | 16 GB | 32 GB |
| Disk | 50 GB | 100 GB |
| OS | Ubuntu 22.04+ / Debian 12 | Same |

### What you already have (AWS CloudShell)
CloudShell provides a free environment for running commands, but it has limitations that prevent running the lab directly:

- **No nested Docker** — CloudShell runs in a container itself; Containerlab needs Docker to create containers inside containers (requires `--privileged` or DinD)
- **1 GB persistent storage** — lab images alone need ~2 GB
- **Session limits** — 120-minute idle timeout
- **No KVM** — no hardware virtualization for VM-based nodes

**CloudShell is suitable for managing a remote EC2 instance, not for running the lab itself.**

---

## 3. Cloud Deployment Cost Analysis

If you deploy on AWS EC2 (e.g., controlled from CloudShell), here are the costs:

### EC2 Pricing (us-east-1, Linux, On-Demand)

| Instance | vCPU | RAM | On-Demand $/hr | Monthly (730h) |
|----------|------|-----|----------------|-----------------|
| t3.medium | 2 | 4 GB | $0.0416 | $30.37 |
| t3.large | 2 | 8 GB | $0.0832 | $60.74 |
| **t3.xlarge** | **4** | **16 GB** | **$0.1664** | **$121.47** |
| **t3.2xlarge** | **8** | **32 GB** | **$0.3328** | **$242.94** |
| m5.xlarge | 4 | 16 GB | $0.1920 | $140.16 |
| c5.2xlarge | 8 | 16 GB | $0.3400 | $248.20 |

**t3.xlarge** is the minimum that meets our 4 vCPU / 16 GB spec.
**t3.2xlarge** is recommended for the full monitoring stack.

### Spot Pricing (same region, current)

| Instance | Spot $/hr | Monthly | Savings vs On-Demand |
|----------|-----------|---------|---------------------|
| t3.xlarge | ~$0.042 | ~$30.66 | 75% |
| t3.2xlarge | ~$0.091 | ~$66.43 | 73% |

Spot instances are 73-75% cheaper but can be terminated with 2-minute warning. Fine for lab work where you can redeploy with one `containerlab deploy` command.

### EBS Storage

| Type | $/GB-month | 50 GB cost |
|------|-----------|------------|
| gp3 | $0.08 | $4.00/mo |
| gp2 | $0.10 | $5.00/mo |

### Full Monthly Cost Scenarios

| Scenario | Compute | Storage | Total/mo | Notes |
|----------|---------|---------|----------|-------|
| t3.xlarge On-Demand | $121.47 | $4.00 | **$125.47** | Min spec, persistent |
| t3.2xlarge On-Demand | $242.94 | $4.00 | **$246.94** | Recommended, persistent |
| t3.xlarge Spot | $30.66 | $4.00 | **$34.66** | Min spec, interruptible |
| t3.2xlarge Spot | $66.43 | $4.00 | **$70.43** | Recommended, interruptible |

### Data Transfer (minimal)

| Transfer | Rate | Est. Monthly |
|----------|------|-------------|
| Inbound | $0.00 | $0.00 |
| Outbound (first 100 GB) | $0.09/GB | ~$0 (lab traffic stays internal) |
| Inter-AZ (if multi-AZ) | $0.01/GB | ~$0 (single AZ recommended) |

Lab traffic is entirely internal to the VPC, so data transfer costs are effectively $0.

---

## 4. Credit Sufficiency Analysis

### AWS Free Tier

| Resource | Free Tier | Lab Needs | Sufficient? |
|----------|-----------|-----------|-------------|
| t2.micro/t3.micro | 750 hrs/mo for 12 mo | N/A (too small) | ❌ |
| EBS | 30 GB gp2/gp3 for 12 mo | 50 GB | ❌ (partial) |
| Data transfer | 100 GB/mo out | ~0 | ✅ |

The AWS Free Tier's compute allocation (t2/t3.micro, 1 GB RAM) is **insufficient** for this lab. It requires at least 16 GB RAM.

### Scenario: You have AWS credits

Common credit amounts and how long they last:

| Credits | t3.xlarge OD | t3.2xlarge OD | t3.xlarge Spot | t3.2xlarge Spot |
|---------|-------------|---------------|---------------|-----------------|
| $25 | 6 days | 3 days | 22 days | 11 days |
| $50 | 12 days | 6 days | 44 days | 22 days |
| $100 | 24 days | 12 days | 89 days | 44 days |
| $300 | 59 days | 30 days | 266 days | 133 days |
| $500 | 98 days | 49 days | 444 days | 222 days |
| $1,000 | 197 days | 99 days | 889 days | 444 days |

(Calculated as credits ÷ daily cost; daily cost = monthly ÷ 30.4)

### Recommendation by credit amount

- **$0 credits:** Run locally. Free.
- **$25–$50 credits:** Use spot instances for short experiments (days to weeks). Terminate when not actively learning.
- **$100–$300 credits:** Spot t3.xlarge gives you 1–9 months of lab time. On-demand for 1–3 months.
- **$500+ credits:** Comfortable on-demand for months, or spot for very long-term access.

### Cost optimization tips

1. **Use Spot instances** — 73-75% savings. The lab deploys in under 5 minutes via `containerlab deploy`, so interruption is low-friction.
2. **Terminate when idle** — EC2 charges by the hour (rounded up). Shut down when not actively working:
   ```bash
   # Save your work, then:
   aws ec2 terminate-instances --instance-ids i-xxxxxxxxx --region us-east-1
   ```
3. **Use gp3 EBS** — 20% cheaper than gp2 with better performance.
4. **Right-size the instance** — Start with t3.xlarge (16 GB) and only upgrade to t3.2xlarge if the monitoring stack is sluggish.
5. **Use EBS snapshots** — Snapshot the configured instance ($0.05/GB-month) so you can restore quickly without reconfiguring:
   ```bash
   aws ec2 create-snapshot --volume-id vol-xxxxxxxxx --description "netlab-configured" --region us-east-1
   ```

---

## 5. Deployment Architecture

### Option A: Local (recommended, $0)
```
[Your Laptop] → Containerlab → Docker containers (FRR, Alpine, monitoring)
```

### Option B: Cloud (from CloudShell)
```
[AWS CloudShell] ──SSH──→ [EC2 Instance] → Containerlab → Docker containers
```

CloudShell acts as your control plane. You SSH into the EC2 instance to run Containerlab commands.

### Deploying via CloudShell to EC2

```bash
# 1. Launch EC2 instance
aws ec2 run-instances \
  --image-id ami-0c02fb55956c7d316 \
  --instance-type t3.xlarge \
  --key-name my-key \
  --security-group-ids sg-xxxxxxxxx \
  --subnet-id subnet-xxxxxxxxx \
  --block-device-mappings 'DeviceName=/dev/sda1,Ebs={VolumeSize=50,VolumeType=gp3}' \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=netlab}]' \
  --region us-east-1

# 2. SSH in and install prerequisites
ssh -i my-key.pem ec2-user@<instance-ip>
sudo yum install -y docker
sudo systemctl enable --now docker
bash -c "$(curl -sL https://get.containerlab.dev)"

# 3. Clone your lab repo and deploy
git clone https://github.com/macrohard80/ResilientCloud.git
cd ResilientCloud
sudo containerlab deploy -t topology.clab.yml
```

---

## 6. Summary

| Question | Answer |
|----------|--------|
| Software cost? | **$0** — all free and open source |
| Local deployment? | **$0** — run on existing hardware |
| Minimum cloud cost? | **~$35/mo** (spot) or **~$125/mo** (on-demand) |
| Free tier sufficient? | **No** — t2/t3.micro (1 GB RAM) too small |
| Credits needed? | Depends on balance and usage duration; see table above |
| Best value? | Local deployment, or spot t3.xlarge if cloud is required |
