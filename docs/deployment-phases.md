# Phased Deployment Plan

Three-phase rollout: independent regions first, then VPC peering full-mesh, then WAN edge routing.

## Phase Overview

| Phase | Goal | Duration | Regions Active | Inter-Region |
|-------|------|----------|---------------|-------------|
| Phase 1 | Stand up 3 independent regional datacenters | 30 min | 3 (isolated) | None |
| Phase 2 | VPC peering full-mesh + GRE tunnels | 15 min | 3 (connected at L3) | VPC peering only |
| Phase 3 | WAN edge BGP for cross-region routing | 20 min | 3 (full routing) | BGP over GRE tunnels |

---

## Phase 1: Independent Regional Datacenters

Deploy three VPCs with EC2 instances, each running Containerlab independently. No inter-region connectivity yet.

### Prerequisites

```bash
# Verify AWS access
aws sts get-caller-identity

# Ensure key pair exists (create if needed)
aws ec2 create-key-pair --key-name networking-lab \
  --query 'KeyMaterial' --output text --region us-east-1 > ~/.ssh/networking-lab.pem
chmod 400 ~/.ssh/networking-lab.pem
```

### Phase 1A: DC-East (us-east-1) — Update Existing Infra

The existing VPC (`networking-lab-vpc`, 10.0.0.0/16) already has public/private subnets and two t3.micro instances. We need to:
1. Add a WAN subnet (10.0.3.0/28)
2. Update the route table to include an IGW route for the public subnet
3. Launch a larger EC2 instance for Containerlab (t3.xlarge or t3.2xlarge)
4. Tag all resources consistently

```bash
# ── DC-EAST: us-east-1 ──────────────────────────────────────────

REGION=us-east-1
VPC_ID=vpc-0287cc4e662371bcb        # existing
IGW_ID=igw-0fcd99507b2227246        # existing
PUB_SUB=subnet-0cd12e907aa08b4b3    # existing 10.0.1.0/24
PRIV_SUB=subnet-0a4a7bdcaa742bbdf   # existing 10.0.2.0/24

# Create WAN subnet
WAN_SUB=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block 10.0.3.0/28 \
  --availability-zone us-east-1a \
  --query 'Subnet.SubnetId' --output text --region $REGION)
aws ec2 create-tags --resources $WAN_SUB \
  --tags Key=Name,Value=networking-lab-wan-subnet --region $REGION

# Find latest Amazon Linux 2023 AMI
AMI_ID=$(aws ssm get-parameters \
  --names /aws/service/ami-amazon-linux/2023/recommended/ami_id \
  --query 'Parameters[0].Value' --output text --region $REGION)

# Launch Containerlab host (private subnet, no public IP)
aws ec2 run-instances \
  --image-id $AMI_ID \
  --instance-type t3.xlarge \
  --subnet-id $PRIV_SUB \
  --security-group-ids sg-0720662ad963afe34 \
  --key-name networking-lab \
  --block-device-mappings 'DeviceName=/dev/xvda,Ebs={VolumeSize=50,VolumeType=gp3}' \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=netlab-east}]' \
  --region $REGION

# Launch bastion (public subnet, with public IP)
aws ec2 run-instances \
  --image-id $AMI_ID \
  --instance-type t3.micro \
  --subnet-id $PUB_SUB \
  --security-group-ids sg-0a6826440476ab48f \
  --key-name networking-lab \
  --associate-public-ip-address \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=netlab-east-bastion}]' \
  --region $REGION

# Add IGW route to public route table
PUB_RT=$(aws ec2 describe-route-tables \
  --filters "Name=vpc-id,Values=$VPC_ID" "Name=association.subnet-id,Values=$PUB_SUB" \
  --query 'RouteTables[0].RouteTableId' --output text --region $REGION)
aws ec2 create-route --route-table-id $PUB_RT \
  --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW_ID \
  --region $REGION
```

### Phase 1B: DC-West (us-west-2) — New VPC

```bash
# ── DC-WEST: us-west-2 ───────────────────────────────────────────

REGION=us-west-2

# Create VPC
VPC_W=$(aws ec2 create-vpc --cidr-block 10.1.0.0/16 \
  --query 'Vpc.VpcId' --output text --region $REGION)
aws ec2 create-tags --resources $VPC_W \
  --tags Key=Name,Value=networking-lab-vpc-west --region $REGION
aws ec2 modify-vpc-attribute --vpc-id $VPC_W --enable-dns-hostnames --region $REGION

# Subnets
PUB_SUB_W=$(aws ec2 create-subnet --vpc-id $VPC_W \
  --cidr-block 10.1.1.0/24 --availability-zone us-west-2a \
  --query 'Subnet.SubnetId' --output text --region $REGION)
aws ec2 create-tags --resources $PUB_SUB_W --tags Key=Name,Value=netlab-west-public --region $REGION

PRIV_SUB_W=$(aws ec2 create-subnet --vpc-id $VPC_W \
  --cidr-block 10.1.2.0/24 --availability-zone us-west-2b \
  --query 'Subnet.SubnetId' --output text --region $REGION)
aws ec2 create-tags --resources $PRIV_SUB_W --tags Key=Name,Value=netlab-west-private --region $REGION

WAN_SUB_W=$(aws ec2 create-subnet --vpc-id $VPC_W \
  --cidr-block 10.1.3.0/28 --availability-zone us-west-2a \
  --query 'Subnet.SubnetId' --output text --region $REGION)
aws ec2 create-tags --resources $WAN_SUB_W --tags Key=Name,Value=netlab-west-wan --region $REGION

# IGW
IGW_W=$(aws ec2 create-internet-gateway --query 'InternetGateway.InternetGatewayId' --output text --region $REGION)
aws ec2 attach-internet-gateway --internet-gateway-id $IGW_W --vpc-id $VPC_W --region $REGION

# Route tables
PUB_RT_W=$(aws ec2 create-route-table --vpc-id $VPC_W --query 'RouteTable.RouteTableId' --output text --region $REGION)
aws ec2 create-route --route-table-id $PUB_RT_W --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW_W --region $REGION
aws ec2 associate-route-table --route-table-id $PUB_RT_W --subnet-id $PUB_SUB_W --region $REGION
PRIV_RT_W=$(aws ec2 create-route-table --vpc-id $VPC_W --query 'RouteTable.RouteTableId' --output text --region $REGION)
aws ec2 associate-route-table --route-table-id $PRIV_RT_W --subnet-id $PRIV_SUB_W --region $REGION

# Security groups
SG_PUB_W=$(aws ec2 create-security-group --vpc-id $VPC_W \
  --group-name netlab-west-public-sg --description "Public SSH" \
  --query 'GroupId' --output text --region $REGION)
aws ec2 authorize-security-group-ingress --group-id $SG_PUB_W --protocol tcp --port 22 --cidr 0.0.0.0/0 --region $REGION

SG_PRIV_W=$(aws ec2 create-security-group --vpc-id $VPC_W \
  --group-name netlab-west-private-sg --description "Private lab" \
  --query 'GroupId' --output text --region $REGION)
aws ec2 authorize-security-group-ingress --group-id $SG_PRIV_W --protocol tcp --port 22 --source-group $SG_PUB_W --region $REGION
aws ec2 authorize-security-group-ingress --group-id $SG_PRIV_W --protocol all --cidr 10.1.0.0/16 --region $REGION

# Key pair + AMI
aws ec2 create-key-pair --key-name networking-lab \
  --query 'KeyMaterial' --output text --region $REGION > ~/.ssh/networking-lab-west.pem
chmod 400 ~/.ssh/networking-lab-west.pem
AMI_W=$(aws ssm get-parameters --names /aws/service/ami-amazon-linux/2023/recommended/ami_id \
  --query 'Parameters[0].Value' --output text --region $REGION)

# Launch instances
aws ec2 run-instances --image-id $AMI_W --instance-type t3.xlarge \
  --subnet-id $PRIV_SUB_W --security-group-ids $SG_PRIV_W --key-name networking-lab \
  --block-device-mappings 'DeviceName=/dev/xvda,Ebs={VolumeSize=50,VolumeType=gp3}' \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=netlab-west}]' --region $REGION

aws ec2 run-instances --image-id $AMI_W --instance-type t3.micro \
  --subnet-id $PUB_SUB_W --security-group-ids $SG_PUB_W --key-name networking-lab \
  --associate-public-ip-address \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=netlab-west-bastion}]' --region $REGION
```

### Phase 1C: DC-EU (eu-west-1) — New VPC

Same pattern as DC-West with `eu-west-1` region, `10.2.0.0/16` VPC CIDR, and `10.2.{1,2,3}.0` subnets. See `scripts/deploy-multi-region.sh` for the full script.

### Phase 1D: Provision Containerlab on Each EC2 Host

After EC2 instances are running, SSH to each lab host via its bastion:

```bash
# Install Docker + Containerlab
sudo dnf install -y docker
sudo systemctl enable --now docker
sudo usermod -aG docker $USER
bash -c "$(curl -sL https://get.containerlab.dev)"

# Clone repo, deploy region-specific topology
git clone <repo-url> networking-lab && cd networking-lab
sudo containerlab deploy -t topology.clab.yml          # region-specific
ansible-playbook -i inventory.yml playbooks/deploy-configs.yml
cd monitoring && docker compose up -d
```

### Phase 1 Verification

```bash
# Each host: verify lab is running
containerlab inspect -t topology.clab.yml
docker exec clab-netlab-spine1 vtysh -c "show ip bgp summary"
docker exec clab-netlab-host-a ping -c 3 10.10.3.1   # intra-region only
```

---

## Phase 2: VPC Peering Full-Mesh

Connect the three VPCs with cross-region peering connections.

### Phase 2A: Create VPC Peering Connections

```bash
# East ↔ West
PCX_EW=$(aws ec2 create-vpc-peering-connection \
  --vpc-id vpc-0287cc4e662371bcb --peer-vpc-id $VPC_W \
  --peer-region us-west-2 \
  --query 'VpcPeeringConnection.VpcPeeringConnectionId' --output text --region us-east-1)
aws ec2 accept-vpc-peering-connection --vpc-peering-connection-id $PCX_EW --region us-west-2

# East ↔ EU
PCX_EE=$(aws ec2 create-vpc-peering-connection \
  --vpc-id vpc-0287cc4e662371bcb --peer-vpc-id $VPC_E \
  --peer-region eu-west-1 \
  --query 'VpcPeeringConnection.VpcPeeringConnectionId' --output text --region us-east-1)
aws ec2 accept-vpc-peering-connection --vpc-peering-connection-id $PCX_EE --region eu-west-1

# West ↔ EU
PCX_WE=$(aws ec2 create-vpc-peering-connection \
  --vpc-id $VPC_W --peer-vpc-id $VPC_E --peer-region eu-west-1 \
  --query 'VpcPeeringConnection.VpcPeeringConnectionId' --output text --region us-west-2)
aws ec2 accept-vpc-peering-connection --vpc-peering-connection-id $PCX_WE --region eu-west-1
```

### Phase 2B: Update Route Tables (All 6 Route Tables)

```bash
# DC-East: add routes to 10.1.0.0/16 and 10.2.0.0/16 via peering
for RT in $PUB_RT $PRIV_RT; do
  aws ec2 create-route --route-table-id $RT --destination-cidr-block 10.1.0.0/16 \
    --vpc-peering-connection-id $PCX_EW --region us-east-1
  aws ec2 create-route --route-table-id $RT --destination-cidr-block 10.2.0.0/16 \
    --vpc-peering-connection-id $PCX_EE --region us-east-1
done

# DC-West: add routes to 10.0.0.0/16 and 10.2.0.0/16 via peering
for RT in $PUB_RT_W $PRIV_RT_W; do
  aws ec2 create-route --route-table-id $RT --destination-cidr-block 10.0.0.0/16 \
    --vpc-peering-connection-id $PCX_EW --region us-west-2
  aws ec2 create-route --route-table-id $RT --destination-cidr-block 10.2.0.0/16 \
    --vpc-peering-connection-id $PCX_WE --region us-west-2
done

# DC-EU: add routes to 10.0.0.0/16 and 10.1.0.0/16 via peering
for RT in $PUB_RT_E $PRIV_RT_E; do
  aws ec2 create-route --route-table-id $RT --destination-cidr-block 10.0.0.0/16 \
    --vpc-peering-connection-id $PCX_EE --region eu-west-1
  aws ec2 create-route --route-table-id $RT --destination-cidr-block 10.1.0.0/16 \
    --vpc-peering-connection-id $PCX_WE --region eu-west-1
done
```

### Phase 2C: Update Security Groups for Cross-Region Traffic

```bash
# Allow all traffic between VPC CIDRs (lab environment)
# DC-East private SG:
aws ec2 authorize-security-group-ingress --group-id sg-0720662ad963afe34 \
  --protocol all --cidr 10.1.0.0/16 --region us-east-1
aws ec2 authorize-security-group-ingress --group-id sg-0720662ad963afe34 \
  --protocol all --cidr 10.2.0.0/16 --region us-east-1

# DC-West private SG:
aws ec2 authorize-security-group-ingress --group-id $SG_PRIV_W \
  --protocol all --cidr 10.0.0.0/16 --region us-west-2
aws ec2 authorize-security-group-ingress --group-id $SG_PRIV_W \
  --protocol all --cidr 10.2.0.0/16 --region us-west-2

# DC-EU private SG:
aws ec2 authorize-security-group-ingress --group-id $SG_PRIV_E \
  --protocol all --cidr 10.0.0.0/16 --region eu-west-1
aws ec2 authorize-security-group-ingress --group-id $SG_PRIV_E \
  --protocol all --cidr 10.1.0.0/16 --region eu-west-1
```

### Phase 2 Verification

```bash
# From DC-East bastion, ping DC-West and DC-EU private hosts
ping -c 3 <dc-west-lab-private-ip>
ping -c 3 <dc-eu-lab-private-ip>

# Verify peering connections are active
aws ec2 describe-vpc-peering-connections --region us-east-1 \
  --filters "Name=status-code,Values=active" \
  --query 'VpcPeeringConnections[].{ID:VpcPeeringConnectionId,Status:Status.Code}' --output table
```

---

## Phase 3: WAN Edge BGP Routing

Deploy the WAN edge FRR routers with GRE tunnels and BGP for cross-region route exchange.

### Phase 3A: Enable Host-Level Forwarding

```bash
# On each EC2 lab host:
sudo sysctl -w net.ipv4.ip_forward=1
echo 'net.ipv4.ip_forward = 1' | sudo tee -a /etc/sysctl.d/99-lab.conf
```

### Phase 3B: Deploy WAN Edge Configs

```bash
# On each EC2 host, deploy updated FRR configs including wan-edge:
cd networking-lab/automation/ansible
ansible-playbook -i inventory.yml playbooks/deploy-configs.yml
```

### Phase 3C: Verify Cross-Region BGP

```bash
# Check WAN edge BGP sessions (should show 4 neighbors: 2 spines + 2 remote wan-edges)
docker exec clab-netlab-wan-east vtysh -c "show ip bgp summary"

# Verify remote routes learned:
docker exec clab-netlab-wan-east vtysh -c "show ip bgp" | grep "10.11.0.0/16\|10.12.0.0/16"

# Verify remote routes propagated to fabric:
docker exec clab-netlab-spine1 vtysh -c "show ip bgp" | grep "10.11.0.0/16\|10.12.0.0/16"

# End-to-end connectivity across regions:
docker exec clab-netlab-host-a ping -c 3 10.11.1.1   # DC-East → DC-West
docker exec clab-netlab-host-a ping -c 3 10.12.1.1   # DC-East → DC-EU
docker exec clab-netlab-host-a traceroute 10.11.1.1  # Show path
```

### Phase 3D: Verify Resilience / Failover

```bash
# Shut down the East↔West tunnel, verify traffic reroutes through EU:
docker exec clab-netlab-wan-east vtysh -c "configure terminal" -c "interface tun-west" -c "shutdown"

# Trace should show hop through wan-eu:
docker exec clab-netlab-host-a traceroute 10.11.1.1

# Restore:
docker exec clab-netlab-wan-east vtysh -c "configure terminal" -c "interface tun-west" -c "no shutdown"
```

---

## Resource Inventory & Cost

### Per Region

| Resource | Spec | Monthly (On-Demand) |
|----------|------|---------------------|
| VPC + subnets + IGW + route tables | — | $0 |
| Security groups | 2 | $0 |
| Bastion EC2 | t3.micro | $7.59 |
| Lab EC2 | t3.xlarge (4 vCPU, 16 GB) | $121.47 |
| Lab EBS | gp3 50 GB | $4.00 |
| VPC peering (×2) | cross-region | $0 + $0.02/GB transfer |

### Three-Region Total

| Deployment | Monthly Cost |
|-----------|-------------|
| On-Demand (all 3 regions) | ~$399 |
| Spot lab hosts (73% savings) | ~$116 |
| Data transfer (lab traffic, internal) | ~$0 |

---

## Teardown

```bash
# Destroy Containerlab on each host (SSH to each first):
containerlab destroy -t topology.clab.yml --cleanup
cd monitoring && docker compose down

# Terminate EC2 instances in each region
aws ec2 terminate-instances --instance-ids <east-id> --region us-east-1
aws ec2 terminate-instances --instance-ids <west-id> --region us-west-2
aws ec2 terminate-instances --instance-ids <eu-id> --region eu-west-1

# Delete VPC peering connections
aws ec2 delete-vpc-peering-connection --vpc-peering-connection-id $PCX_EW --region us-east-1
aws ec2 delete-vpc-peering-connection --vpc-peering-connection-id $PCX_EE --region us-east-1
aws ec2 delete-vpc-peering-connection --vpc-peering-connection-id $PCX_WE --region us-west-2

# Delete VPCs (DC-West and DC-EU; keep DC-East existing infra):
aws ec2 delete-vpc --vpc-id $VPC_W --region us-west-2
aws ec2 delete-vpc --vpc-id $VPC_E --region eu-west-1
```
