# IP Addressing Plan

## Network Allocation Summary

| Network | Subnet | Mask | Purpose |
|---------|--------|------|---------|
| Management | 10.255.255.0/24 | 255.255.255.0 | Out-of-band mgmt (Containerlab clab-mgmt network) |
| Loopbacks | 10.255.0.0/24 | 255.255.255.0 | Router IDs, BGP update-source, services reachability |
| Underlay P2P | 10.0.0.0/24 | /31 per link | Spine-leaf point-to-point interconnects |
| Host subnets | 10.10.0.0/16 | /24 per leaf | Endpoint connectivity |
| Services | 10.20.0.0/24 | 255.255.255.0 | Monitoring & DNS containers |

---

## 1. Management Network — 10.255.255.0/24

Containerlab creates a `clab-netlab-mgmt` bridge network. Every container gets a static management IP for SSH, Ansible, and telemetry access.

| Device | Management IP | Notes |
|--------|---------------|-------|
| spine1 | 10.255.255.11 | FRR mgmt interface |
| spine2 | 10.255.255.12 | FRR mgmt interface |
| leaf1 | 10.255.255.21 | FRR mgmt interface |
| leaf2 | 10.255.255.22 | FRR mgmt interface |
| leaf3 | 10.255.255.23 | FRR mgmt interface |
| leaf4 | 10.255.255.24 | FRR mgmt interface |
| fw1 | 10.255.255.254 | VyOS firewall mgmt |
| host-a | 10.255.255.31 | Alpine host mgmt |
| host-b | 10.255.255.32 | Alpine host mgmt |
| host-c | 10.255.255.33 | Alpine host mgmt |
| host-d | 10.255.255.34 | Alpine host mgmt |
| prometheus | 10.255.255.41 | Monitoring |
| grafana | 10.255.255.42 | Monitoring |
| suzieq | 10.255.255.43 | Monitoring |
| batfish | 10.255.255.44 | Monitoring |
| gnmic | 10.255.255.45 | Monitoring |
| dnsmasq | 10.255.255.46 | DNS/DHCP |

**Gateway:** 10.255.255.1 (clab bridge interface — host)

---

## 2. Loopback Addresses — 10.255.0.0/24

Each router gets a /32 loopback used as its OSPF Router ID and BGP update-source. This ensures routing protocol adjacency is independent of physical link state.

| Device | Loopback IP | Router ID | ASN |
|--------|-------------|-----------|-----|
| spine1 | 10.255.0.1/32 | 10.255.0.1 | 65001 |
| spine2 | 10.255.0.2/32 | 10.255.0.2 | 65001 |
| leaf1 | 10.255.0.11/32 | 10.255.0.11 | 65101 |
| leaf2 | 10.255.0.12/32 | 10.255.0.12 | 65102 |
| leaf3 | 10.255.0.13/32 | 10.255.0.13 | 65103 |
| leaf4 | 10.255.0.14/32 | 10.255.0.14 | 65104 |

**Spines share ASN 65001** (iBGP between spine1 and spine2).
**Each leaf has a unique ASN** (eBGP to both spines).

Reserved for future use: 10.255.0.20–10.255.0.254

---

## 3. Underlay P2P Links — 10.0.0.0/24 (using /31 per link)

Each spine-to-leaf connection uses a /31 (point-to-point, no broadcast/network waste).

| Link | Spine side | Leaf side | Subnet |
|------|-----------|-----------|--------|
| spine1 ↔ leaf1 | 10.0.0.0/31 | 10.0.0.1/31 | 10.0.0.0/31 |
| spine1 ↔ leaf2 | 10.0.0.2/31 | 10.0.0.3/31 | 10.0.0.2/31 |
| spine1 ↔ leaf3 | 10.0.0.4/31 | 10.0.0.5/31 | 10.0.0.4/31 |
| spine1 ↔ leaf4 | 10.0.0.6/31 | 10.0.0.7/31 | 10.0.0.6/31 |
| spine2 ↔ leaf1 | 10.0.0.8/31 | 10.0.0.9/31 | 10.0.0.8/31 |
| spine2 ↔ leaf2 | 10.0.0.10/31 | 10.0.0.11/31 | 10.0.0.10/31 |
| spine2 ↔ leaf3 | 10.0.0.12/31 | 10.0.0.13/31 | 10.0.0.12/31 |
| spine2 ↔ leaf4 | 10.0.0.14/31 | 10.0.0.15/31 | 10.0.0.14/31 |
| spine1 ↔ spine2 | 10.0.0.16/31 | 10.0.0.17/31 | 10.0.0.16/31 |

**Interface naming convention:**
- Spines: `eth1`–`eth5` (eth0 = mgmt)
- Leaves: `eth1`–`eth2` (uplinks to spines), `eth3` (downlink to host)

### Spine interface map

| Interface | Connected to | IP |
|-----------|-------------|-----|
| spine1 eth1 | leaf1 | 10.0.0.0/31 |
| spine1 eth2 | leaf2 | 10.0.0.2/31 |
| spine1 eth3 | leaf3 | 10.0.0.4/31 |
| spine1 eth4 | leaf4 | 10.0.0.6/31 |
| spine1 eth5 | spine2 | 10.0.0.16/31 |
| spine2 eth1 | leaf1 | 10.0.0.8/31 |
| spine2 eth2 | leaf2 | 10.0.0.10/31 |
| spine2 eth3 | leaf3 | 10.0.0.12/31 |
| spine2 eth4 | leaf4 | 10.0.0.14/31 |
| spine2 eth5 | spine1 | 10.0.0.17/31 |

### Leaf interface map

| Interface | Connected to | IP |
|-----------|-------------|-----|
| leaf1 eth1 | spine1 | 10.0.0.1/31 |
| leaf1 eth2 | spine2 | 10.0.0.9/31 |
| leaf2 eth1 | spine1 | 10.0.0.3/31 |
| leaf2 eth2 | spine2 | 10.0.0.11/31 |
| leaf3 eth1 | spine1 | 10.0.0.5/31 |
| leaf3 eth2 | spine2 | 10.0.0.13/31 |
| leaf4 eth1 | spine1 | 10.0.0.7/31 |
| leaf4 eth2 | spine2 | 10.0.0.15/31 |

**Used:** 10.0.0.0–10.0.0.17 (18 IPs, 9 /31 subnets)
**Remaining:** 10.0.0.18–10.0.0.255 (available for expansion)

---

## 4. Host Subnets — 10.10.0.0/16

Each leaf has a /24 for its connected hosts. The leaf's `eth3` interface is the gateway for its host.

| Leaf | Subnet | Gateway (eth3) | Host IP | VLAN ID |
|------|--------|----------------|---------|---------|
| leaf1 | 10.10.1.0/24 | 10.10.1.254 | host-a: 10.10.1.1 | 10 |
| leaf2 | 10.10.2.0/24 | 10.10.2.254 | host-b: 10.10.2.1 | 20 |
| leaf3 | 10.10.3.0/24 | 10.10.3.254 | host-c: 10.10.3.1 | 30 |
| leaf4 | 10.10.4.0/24 | 10.10.4.254 | host-d: 10.10.4.1 | 40 |

**Remaining:** 10.10.5.0/24–10.10.255.0/24 for future expansion.

### Host interface map

| Host | Interface | Connected to | IP |
|------|-----------|-------------|-----|
| host-a | eth1 | leaf1 eth3 | 10.10.1.1/24 |
| host-b | eth1 | leaf2 eth3 | 10.10.2.1/24 |
| host-c | eth1 | leaf3 eth3 | 10.10.3.1/24 |
| host-d | eth1 | leaf4 eth3 | 10.10.4.1/24 |

**Default gateway for each host:** the leaf's eth3 IP.

---

## 5. Services Network — 10.20.0.0/24

Monitoring and DNS containers run on this network. This is a separate Docker network (`clab-netlab-services`) to keep them off the data plane.

| Service | IP | Port(s) | Notes |
|---------|----|---------|-------|
| prometheus | 10.20.0.10 | 9090 | Metrics scraper |
| grafana | 10.20.0.11 | 3000 | Dashboard UI |
| suzieq | 10.20.0.12 | 8000 (API) | Network observability |
| batfish | 10.20.0.13 | 9996 (API), 9000 (UI) | Config analysis |
| gnmic | 10.20.0.14 | 7890 (gNMI), 9804 (metrics) | Telemetry collector |
| dnsmasq | 10.20.0.15 | 53/tcp+udp | DNS resolver |

**Remaining:** 10.20.0.16–10.20.0.254 for future services.

---

## 6. BGP ASN Plan

| ASN | Devices | Type | Purpose |
|-----|---------|------|---------|
| 65001 | spine1, spine2 | iBGP | Spine fabric, advertises routes between leaves |
| 65101 | leaf1 | eBGP | Connects to spine1 + spine2, advertises 10.10.1.0/24 |
| 65102 | leaf2 | eBGP | Connects to spine1 + spine2, advertises 10.10.2.0/24 |
| 65103 | leaf3 | eBGP | Connects to spine1 + spine2, advertises 10.10.3.0/24 |
| 65104 | leaf4 | eBGP | Connects to spine1 + spine2, advertises 10.10.4.0/24 |

- **Spines (AS 65001):** iBGP between spine1 and spine2 over the direct link (10.0.0.16/31). Full-mesh iBGP. OSPF area 0 underlay.
- **Leaves (AS 6510X):** eBGP to both spines using loopback as update-source. Advertise connected host /24s.
- **Route reflectors:** Spines act as route reflectors for leaves (client role).

---

## 7. OSPF Plan

- **Area:** 0 (backbone)
- **Protocol:** OSPFv2 for IPv4
- **Participating:** All spine and leaf routers
- **Advertised:** P2P link subnets and loopbacks
- **Router ID:** Each device's loopback IP
- **Network type:** point-to-point on /31 links

---

## IP Allocation Map (visual)

```
10.255.255.0/24  ─── Management (OOB)     [10.255.255.11–10.255.255.46]
10.255.0.0/24    ─── Loopbacks            [10.255.0.1–10.255.0.14]
10.0.0.0/24      ─── Underlay P2P /31s    [10.0.0.0–10.0.0.17]
10.10.0.0/16     ─── Host subnets /24s    [10.10.1.0–10.10.4.0]
10.20.0.0/24     ─── Services network     [10.20.0.10–10.20.0.15]
```

No overlaps. Every device has a unique IP on each network it participates in. Total IPs in use: ~50 out of a combined 65,790 address space, leaving ample room for expansion.
