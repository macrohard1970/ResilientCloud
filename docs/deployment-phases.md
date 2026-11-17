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

# Key pairs are created per region by build_region (Phase 1A).
# If a "networking-lab" key pair already exists in a region, delete it first
# or the create-key-pair step fails.
```

### Phase 1A: Define the Region Builder

All three regions are built the same way, from scratch. Paste this function
once; it creates one region's VPC, subnets, internet gateway, route tables,
security groups, key pair, bastion and lab host, and exports the IDs that
Phase 2 needs as `<NAME>_<SUFFIX>` variables (e.g. `VPC_EAST`, `SG_PRIV_WEST`).

```bash
# build_region <region> <suffix> <vpc-cidr-prefix> <az-a> <az-b>
build_region() {
  local R=$1 S=$2 P=$3 AZA=$4 AZB=$5 tag=netlab-${2,,}
  local VPC PUB PRIV WAN IGW PUBRT PRIVRT SGPUB SGPRIV AMI
  VPC=$(aws ec2 create-vpc --cidr-block $P.0.0/16 --region $R \
    --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=$tag-vpc}]" \
    --query Vpc.VpcId --output text)
  aws ec2 modify-vpc-attribute --vpc-id $VPC --enable-dns-hostnames --region $R

  PUB=$(aws ec2 create-subnet --vpc-id $VPC --cidr-block $P.1.0/24 --availability-zone $AZA --region $R \
    --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=$tag-public}]" --query Subnet.SubnetId --output text)
  PRIV=$(aws ec2 create-subnet --vpc-id $VPC --cidr-block $P.2.0/24 --availability-zone $AZB --region $R \
    --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=$tag-private}]" --query Subnet.SubnetId --output text)
  # Reserved; GRE runs from the lab host's primary IP
  WAN=$(aws ec2 create-subnet --vpc-id $VPC --cidr-block $P.3.0/28 --availability-zone $AZA --region $R \
    --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=$tag-wan}]" --query Subnet.SubnetId --output text)

  IGW=$(aws ec2 create-internet-gateway --region $R \
    --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=$tag-igw}]" \
    --query InternetGateway.InternetGatewayId --output text)
  aws ec2 attach-internet-gateway --internet-gateway-id $IGW --vpc-id $VPC --region $R

  PUBRT=$(aws ec2 create-route-table --vpc-id $VPC --region $R --query RouteTable.RouteTableId --output text)
  aws ec2 create-route --route-table-id $PUBRT --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW --region $R >/dev/null
  aws ec2 associate-route-table --route-table-id $PUBRT --subnet-id $PUB --region $R >/dev/null
  PRIVRT=$(aws ec2 create-route-table --vpc-id $VPC --region $R --query RouteTable.RouteTableId --output text)
  aws ec2 associate-route-table --route-table-id $PRIVRT --subnet-id $PRIV --region $R >/dev/null

  SGPUB=$(aws ec2 create-security-group --vpc-id $VPC --group-name $tag-public-sg \
    --description "Bastion SSH" --region $R --query GroupId --output text)
  # Lab default: SSH from anywhere. Narrow to your IP: --cidr <your-ip>/32
  aws ec2 authorize-security-group-ingress --group-id $SGPUB --protocol tcp --port 22 --cidr 0.0.0.0/0 --region $R >/dev/null
  SGPRIV=$(aws ec2 create-security-group --vpc-id $VPC --group-name $tag-private-sg \
    --description "Lab host" --region $R --query GroupId --output text)
  aws ec2 authorize-security-group-ingress --group-id $SGPRIV --protocol tcp --port 22 --source-group $SGPUB --region $R >/dev/null
  aws ec2 authorize-security-group-ingress --group-id $SGPRIV --protocol all --cidr $P.0.0/16 --region $R >/dev/null

  # Key pair per region (EC2 key pairs are regional)
  aws ec2 create-key-pair --key-name networking-lab --region $R \
    --query KeyMaterial --output text > ~/.ssh/networking-lab-${S,,}.pem
  chmod 400 ~/.ssh/networking-lab-${S,,}.pem

  AMI=$(aws ssm get-parameters --names /aws/service/ami-amazon-linux/2023/recommended/ami_id \
    --query 'Parameters[0].Value' --output text --region $R)
  aws ec2 run-instances --image-id $AMI --instance-type t3.xlarge --subnet-id $PRIV \
    --security-group-ids $SGPRIV --key-name networking-lab --region $R \
    --block-device-mappings 'DeviceName=/dev/xvda,Ebs={VolumeSize=50,VolumeType=gp3}' \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$tag}]" >/dev/null
  aws ec2 run-instances --image-id $AMI --instance-type t3.micro --subnet-id $PUB \
    --security-group-ids $SGPUB --key-name networking-lab --associate-public-ip-address --region $R \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$tag-bastion}]" >/dev/null

  export VPC_$S=$VPC IGW_$S=$IGW PUB_SUB_$S=$PUB PRIV_SUB_$S=$PRIV WAN_SUB_$S=$WAN \
         PUB_RT_$S=$PUBRT PRIV_RT_$S=$PRIVRT SG_PUB_$S=$SGPUB SG_PRIV_$S=$SGPRIV
  echo "$S: vpc=$VPC public=$PUB private=$PRIV sg-private=$SGPRIV"
}
```

### Phase 1B: Build All Three Regions

```bash
build_region us-east-1 EAST 10.0 us-east-1a us-east-1b
build_region us-west-2 WEST 10.1 us-west-2a us-west-2b
build_region eu-west-1 EU   10.2 eu-west-1a eu-west-1b

# Keep the IDs for Phase 2 and teardown (new shells need them)
env | grep -E '^(VPC|IGW|PUB_SUB|PRIV_SUB|WAN_SUB|PUB_RT|PRIV_RT|SG_PUB|SG_PRIV)_(EAST|WEST|EU)=' \
  | sed 's/^/export /' > ~/netlab-ids.env
# Later: source ~/netlab-ids.env
```

| Resource | DC-East (us-east-1) | DC-West (us-west-2) | DC-EU (eu-west-1) |
|----------|--------------------|--------------------|-------------------|
| VPC | `netlab-east-vpc` 10.0.0.0/16 | `netlab-west-vpc` 10.1.0.0/16 | `netlab-eu-vpc` 10.2.0.0/16 |
| Public subnet (bastion) | 10.0.1.0/24 | 10.1.1.0/24 | 10.2.1.0/24 |
| Private subnet (lab host) | 10.0.2.0/24 | 10.1.2.0/24 | 10.2.2.0/24 |
| WAN subnet (reserved) | 10.0.3.0/28 | 10.1.3.0/28 | 10.2.3.0/28 |
| Instances | `netlab-east`, `netlab-east-bastion` | `netlab-west`, `netlab-west-bastion` | `netlab-eu`, `netlab-eu-bastion` |
| SSH key | `~/.ssh/networking-lab-east.pem` | `~/.ssh/networking-lab-west.pem` | `~/.ssh/networking-lab-eu.pem` |

### Phase 1C: Provision Containerlab on Each EC2 Host

After EC2 instances are running, SSH to each lab host via its bastion:

```bash
# Install Docker, the compose plugin, git and Containerlab (Amazon Linux 2023)
sudo dnf install -y docker git
sudo systemctl enable --now docker
sudo usermod -aG docker $USER && newgrp docker
sudo mkdir -p /usr/local/lib/docker/cli-plugins
sudo curl -fsSL -o /usr/local/lib/docker/cli-plugins/docker-compose \
  https://github.com/docker/compose/releases/download/v2.29.7/docker-compose-linux-x86_64
sudo chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
bash -c "$(curl -sL https://get.containerlab.dev)"

# Clone the repo and deploy this host's region (dc-east | dc-west | dc-eu)
git clone https://github.com/macrohard80/ResilientCloud.git && cd ResilientCloud
scripts/fetch-frr-exporter.sh                  # optional: FRR metrics
scripts/deploy-multi-region.sh deploy dc-east  # topology + Prometheus/Grafana
```

### Phase 1 Verification

```bash
# Each host: verify lab is running
sudo containerlab inspect -t topology-dc-east.clab.yml
docker exec dc-east-spine1 vtysh -c "show ip bgp summary"
docker exec dc-east-host-a ping -c 3 10.10.3.1   # intra-region only
```

---

## Phase 2: VPC Peering Full-Mesh

Connect the three VPCs with cross-region peering connections.

### Phase 2A: Create VPC Peering Connections

```bash
# East ↔ West
PCX_EW=$(aws ec2 create-vpc-peering-connection \
  --vpc-id $VPC_EAST --peer-vpc-id $VPC_WEST \
  --peer-region us-west-2 \
  --query 'VpcPeeringConnection.VpcPeeringConnectionId' --output text --region us-east-1)
aws ec2 accept-vpc-peering-connection --vpc-peering-connection-id $PCX_EW --region us-west-2

# East ↔ EU
PCX_EE=$(aws ec2 create-vpc-peering-connection \
  --vpc-id $VPC_EAST --peer-vpc-id $VPC_EU \
  --peer-region eu-west-1 \
  --query 'VpcPeeringConnection.VpcPeeringConnectionId' --output text --region us-east-1)
aws ec2 accept-vpc-peering-connection --vpc-peering-connection-id $PCX_EE --region eu-west-1

# West ↔ EU
PCX_WE=$(aws ec2 create-vpc-peering-connection \
  --vpc-id $VPC_WEST --peer-vpc-id $VPC_EU --peer-region eu-west-1 \
  --query 'VpcPeeringConnection.VpcPeeringConnectionId' --output text --region us-west-2)
aws ec2 accept-vpc-peering-connection --vpc-peering-connection-id $PCX_WE --region eu-west-1
```

### Phase 2B: Update Route Tables (All 6 Route Tables)

```bash
# DC-East: add routes to 10.1.0.0/16 and 10.2.0.0/16 via peering
for RT in $PUB_RT_EAST $PRIV_RT_EAST; do
  aws ec2 create-route --route-table-id $RT --destination-cidr-block 10.1.0.0/16 \
    --vpc-peering-connection-id $PCX_EW --region us-east-1
  aws ec2 create-route --route-table-id $RT --destination-cidr-block 10.2.0.0/16 \
    --vpc-peering-connection-id $PCX_EE --region us-east-1
done

# DC-West: add routes to 10.0.0.0/16 and 10.2.0.0/16 via peering
for RT in $PUB_RT_WEST $PRIV_RT_WEST; do
  aws ec2 create-route --route-table-id $RT --destination-cidr-block 10.0.0.0/16 \
    --vpc-peering-connection-id $PCX_EW --region us-west-2
  aws ec2 create-route --route-table-id $RT --destination-cidr-block 10.2.0.0/16 \
    --vpc-peering-connection-id $PCX_WE --region us-west-2
done

# DC-EU: add routes to 10.0.0.0/16 and 10.1.0.0/16 via peering
for RT in $PUB_RT_EU $PRIV_RT_EU; do
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
aws ec2 authorize-security-group-ingress --group-id $SG_PRIV_EAST \
  --protocol all --cidr 10.1.0.0/16 --region us-east-1
aws ec2 authorize-security-group-ingress --group-id $SG_PRIV_EAST \
  --protocol all --cidr 10.2.0.0/16 --region us-east-1

# DC-West private SG:
aws ec2 authorize-security-group-ingress --group-id $SG_PRIV_WEST \
  --protocol all --cidr 10.0.0.0/16 --region us-west-2
aws ec2 authorize-security-group-ingress --group-id $SG_PRIV_WEST \
  --protocol all --cidr 10.2.0.0/16 --region us-west-2

# DC-EU private SG:
aws ec2 authorize-security-group-ingress --group-id $SG_PRIV_EU \
  --protocol all --cidr 10.0.0.0/16 --region eu-west-1
aws ec2 authorize-security-group-ingress --group-id $SG_PRIV_EU \
  --protocol all --cidr 10.1.0.0/16 --region eu-west-1
```

The rules above allow all traffic between the VPCs, which includes GRE. The
minimum the WAN needs is IP protocol 47 (GRE) between the three lab hosts,
e.g. `--ip-permissions IpProtocol=47,IpRanges=[{CidrIp=10.1.2.0/24}]`.

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
# On each EC2 lab host (gre-nat.sh also sets this at runtime):
echo 'net.ipv4.ip_forward = 1' | sudo tee /etc/sysctl.d/99-lab.conf
sudo sysctl --system
```

### Phase 3B: Redeploy Each Region With Its WAN Peers

The WAN edge builds its GRE tunnels at startup from `REMOTE_*`, and the deploy
script runs `scripts/gre-nat.sh` so inbound GRE reaches the container.

```bash
# DC-East host
REMOTE_WEST=<dc-west-private-ip> REMOTE_EU=<dc-eu-private-ip> scripts/deploy-multi-region.sh deploy dc-east
# DC-West host
REMOTE_EAST=<dc-east-private-ip> REMOTE_EU=<dc-eu-private-ip> scripts/deploy-multi-region.sh deploy dc-west
# DC-EU host
REMOTE_EAST=<dc-east-private-ip> REMOTE_WEST=<dc-west-private-ip> scripts/deploy-multi-region.sh deploy dc-eu
```

To push config edits later without redeploying:

```bash
cd automation/ansible
ansible-galaxy collection install -r requirements.yml
ansible-playbook -i inventory-multi-region.yml playbooks/deploy-configs.yml -l dc_east
```

### Phase 3C: Verify Cross-Region BGP

```bash
# Check WAN edge BGP sessions (should show 4 neighbors: 2 spines + 2 remote wan-edges)
docker exec wan-east vtysh -c "show ip bgp summary"

# Verify remote routes learned:
docker exec wan-east vtysh -c "show ip bgp" | grep "10.11.0.0/16\|10.12.0.0/16"

# Verify remote routes propagated to fabric:
docker exec dc-east-spine1 vtysh -c "show ip bgp" | grep "10.11.0.0/16\|10.12.0.0/16"

# End-to-end connectivity across regions:
docker exec dc-east-host-a ping -c 3 10.11.1.1   # DC-East → DC-West
docker exec dc-east-host-a ping -c 3 10.12.1.1   # DC-East → DC-EU
docker exec dc-east-host-a traceroute 10.11.1.1  # Show path
```

### Phase 3D: Verify Resilience / Failover

```bash
# Shut down the East↔West tunnel, verify traffic reroutes through EU:
docker exec wan-east vtysh -c "configure terminal" -c "interface tun-west" -c "shutdown"

# Trace should show hop through wan-eu:
docker exec dc-east-host-a traceroute 10.11.1.1

# Restore:
docker exec wan-east vtysh -c "configure terminal" -c "interface tun-west" -c "no shutdown"
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

Stopping is enough between sessions (only EBS is billed while stopped):

```bash
source ~/netlab-ids.env
for R in us-east-1 us-west-2 eu-west-1; do
  ids=$(aws ec2 describe-instances --region $R --filters "Name=tag:Name,Values=netlab-*" \
    "Name=instance-state-name,Values=running" --query 'Reservations[].Instances[].InstanceId' --output text)
  [ -n "$ids" ] && aws ec2 stop-instances --region $R --instance-ids $ids
done
```

Full decommission (irreversible):

```bash
source ~/netlab-ids.env
# 1. Lab containers (on each lab host, if still running)
scripts/deploy-multi-region.sh destroy dc-east     # dc-west / dc-eu on the others

# 2. Peering connections
for pcx in $PCX_EW $PCX_EE; do aws ec2 delete-vpc-peering-connection --vpc-peering-connection-id $pcx --region us-east-1; done
aws ec2 delete-vpc-peering-connection --vpc-peering-connection-id $PCX_WE --region us-west-2

# 3. Each region: instances (EBS root volumes delete with them), then the VPC in dependency order
teardown_region() {  # <region> <suffix>
  local R=$1 S=$2; local v; v() { eval echo \$${1}_$S; }
  ids=$(aws ec2 describe-instances --region $R --filters "Name=vpc-id,Values=$(v VPC)" \
    "Name=instance-state-name,Values=pending,running,stopping,stopped" --query 'Reservations[].Instances[].InstanceId' --output text)
  [ -n "$ids" ] && aws ec2 terminate-instances --region $R --instance-ids $ids >/dev/null \
    && aws ec2 wait instance-terminated --region $R --instance-ids $ids
  # The private SG references the public SG, so clear rules before deleting either
  for sg in $(v SG_PRIV) $(v SG_PUB); do
    perms=$(aws ec2 describe-security-groups --region $R --group-ids $sg --query 'SecurityGroups[0].IpPermissions' --output json)
    [ "$perms" != "[]" ] && aws ec2 revoke-security-group-ingress --region $R --group-id $sg --ip-permissions "$perms" >/dev/null
  done
  aws ec2 delete-security-group --region $R --group-id $(v SG_PRIV)
  aws ec2 delete-security-group --region $R --group-id $(v SG_PUB)
  for sn in $(v PUB_SUB) $(v PRIV_SUB) $(v WAN_SUB); do aws ec2 delete-subnet --region $R --subnet-id $sn; done
  for rt in $(v PUB_RT) $(v PRIV_RT); do aws ec2 delete-route-table --region $R --route-table-id $rt; done
  aws ec2 detach-internet-gateway --region $R --internet-gateway-id $(v IGW) --vpc-id $(v VPC)
  aws ec2 delete-internet-gateway --region $R --internet-gateway-id $(v IGW)
  aws ec2 delete-vpc --region $R --vpc-id $(v VPC)
  aws ec2 delete-key-pair --region $R --key-name networking-lab
  echo "$S decommissioned"
}
teardown_region us-east-1 EAST
teardown_region us-west-2 WEST
teardown_region eu-west-1 EU
```
