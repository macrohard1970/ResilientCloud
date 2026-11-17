# Changelog

All fixes from the November 2026 review. Each entry gives the problem, why it mattered, and what changed. Every fix was checked against FRR 10.2.1 and Alpine containers in Docker; a full multi-host Containerlab deployment was not run (see "Not verified" at the end).

## Deployment guide after decommission

The original DC-East VPC (`vpc-0287cc4e662371bcb`), its subnets, security groups and both t3.micro instances were decommissioned on 2026-11-17, so `docs/deployment-phases.md` no longer treats DC-East as existing infrastructure.

| Problem | Fix |
|---------|-----|
| Phase 1A reused hard-coded DC-East VPC/subnet/SG/IGW IDs that no longer exist | One `build_region` function builds every region from scratch (VPC, 3 subnets, IGW, route tables, SGs, key pair, bastion, lab host) |
| Phase 1C (DC-EU) only said "same pattern" and pointed at a script that creates no AWS resources, so `$VPC_E`, `$SG_PRIV_E`, `$PUB_RT_E` used in Phase 2 were never set | DC-EU is built by the same function; IDs exported as `<NAME>_EAST/WEST/EU` and saved to `~/netlab-ids.env` |
| Teardown deleted VPCs without their dependencies (fails while subnets, SGs or the IGW exist) and kept DC-East | `teardown_region` removes instances, SGs, subnets, route tables, IGW, VPC and key pair in dependency order, for all three regions |

Checked with `bash -n` and a stubbed AWS CLI: 27 IDs exported, 36 delete calls issued in teardown.

## FRR configs — `8d8c837`

| Problem | Impact | Fix |
|---------|--------|-----|
| DC-East underlay used 10.0.0.0/24, inside the DC-East VPC (10.0.0.0/16) | Lab routes could shadow real VPC addresses on the EC2 host | Moved to 10.99.0.0/24 (West 10.100.0.0/24, EU 10.200.0.0/24 unchanged) |
| DC-East devices were named `spine1`, `leaf1`, ...; other regions `dc-west-spine1` | Names collided across regions (inventory, DNS, dashboards) | Renamed to `dc-east-*`; configs moved to `configs/frr/dc-east-*`, hosts to `configs/hosts/dc-east/` |
| `neighbor X route-reflector-client` on eBGP sessions | FRR rejects it (RR is iBGP-only); 29 lines silently dropped | Removed; spines re-advertise to leaves over eBGP |
| BFD `peer X` with `minimum-ttl 1` (single-hop syntax for loopback peers) | Rejected; no BFD sessions were created | BFD `profile FABRIC` / `WAN` bound with `neighbor X bfd profile`; bgpd builds multihop sessions |
| Router-level `passive-interface lo` | Rejected by FRR 10 | `ip ospf passive` under `interface lo` |
| DC-EU configs said `frr version 8.4` | Inconsistent with the 10.2.1 image | All configs `frr version 10.2.1` |
| WAN edges: `network 10.x.0.0/16` + `no bgp network import-check`, prefix-lists defined but unused, wan-eu had a different layout | /16 advertised even with the fabric down (black hole); no filtering on the WAN | One template for all three: `aggregate-address`, route-maps `WAN-IN`, `WAN-OUT`, `FABRIC-OUT` applied |
| Host init `apk add ... ping bash` | `ping` is not an Alpine package, so the whole install failed | `apk add iproute2 iputils` |

Verification: all 21 configs booted in `quay.io/frrouting/frr:10.2.1`; `frr-reload.py --test` showed every line accepted. Scan of 150 addresses and 33 device names across the three regions found no duplicates and no lab address inside a VPC CIDR.

## Topologies and WAN tunnels — `52e7d1b`

| Problem | Impact | Fix |
|---------|--------|-----|
| Image `frrouting/frr:10.2.1` does not exist on Docker Hub | `containerlab deploy` failed on the first router | `quay.io/frrouting/frr:10.2.1` |
| Container names `clab-netlab-<lab>-spine1` | Same short names in every region | `prefix: ""` and node names `dc-east-spine1`, ...; container name = device name |
| `exec: frrinit.sh start` | FRR is already started by the image entrypoint; the second start only errored | Replaced by an optional frr_exporter start |
| GRE sourced from `LOCAL_IP` (EC2 VPC IP) inside the container | The container doesn't own that IP; return GRE never reached it | GRE source = container mgmt IP; `scripts/gre-nat.sh` masquerades/DNATs GRE on the host |
| `REMOTE_*: ""` hard-coded in topologies | Tunnels could never be created | `${REMOTE_WEST:=}` etc., read from the shell at deploy time; unset = tunnel skipped |
| No tunnel MTU | Fragmentation over VPC peering | MTU 1476 |

New: `scripts/fetch-frr-exporter.sh` (pinned v1.12.0, SHA-256 checked), `scripts/gre-nat.sh`.

## Ansible — `1155eaa`

| Problem | Impact | Fix |
|---------|--------|-----|
| Multi-region inventory used `spine1` etc. in all three regions | Ansible merged them into one host with the last region's vars | Inventory names = device names (33 unique hosts) |
| SSH connection to containers | FRR and Alpine images have no sshd; every task would fail | `community.docker.docker` (docker exec); `requirements.yml` |
| Paths `$PWD/../configs/...` | Broke from every documented working directory | `playbook_dir`-relative |
| `copy` onto bind-mounted `/etc/frr/frr.conf` | Failed with `EBUSY` (atomic rename onto a bind mount) | `unsafe_writes: true` |
| Handler `frrinit.sh reload` | Restarts watchfrr, the container's main process, so the node stopped | `frr-reload.py --reload` (applies the diff) |
| Host checks used `command` | Alpine has no Python | `raw` module; ping target per region |
| group_vars listed DC-East RR clients | Wrong for other regions and for the eBGP design | Region-neutral vars |

Verification: playbook run against FRR + Alpine containers; a stale config was pushed and applied without stopping the node; second run `changed=0`.

## Monitoring — `2965856`

| Problem | Impact | Fix |
|---------|--------|-----|
| gNMIc subscribed to OpenConfig paths | FRR has no gNMI server; no router metrics at all | frr_exporter in every FRR node, Prometheus `file_sd` targets per region (21 routers) |
| Compose hard-coded DC-East networks/IPs, external `clab-netlab-services` that nothing created | Stack failed to start, and was wrong for West/EU | `env/<region>.env`; compose creates `rc-<region>-services`; containers `rc-<region>-*` |
| Deploy scripts pre-created the mgmt network without a subnet | Containerlab then could not assign `10.x.255.0/24` mgmt IPs | Removed; Containerlab creates it |
| `netenglabs/suzieq:0.22.1`, `astridyu/dnsmasq` images missing | Pull failures | SuzieQ 0.25.0; dnsmasq on `alpine:3.20` |
| SuzieQ inventory in pre-0.16 format, WAN edges missing | Poller would not start | New format, all routers; sshd prerequisite documented |
| Grafana `suzieq` datasource | No such plugin | Removed |
| All six services always on, ports on 0.0.0.0, dnsmasq on host :53 | Wasted EC2 resources; exposed ports; clash with host resolver | Default = Prometheus + Grafana; others are compose profiles; ports on 127.0.0.1; dnsmasq not published |

Verification: `docker compose config` for all three regions; Prometheus scraped frr_exporter on an FRR node at 10.255.255.11 (target up, 6 BGP peer series).

## Documentation

README, `docs/*.md` and `docs/diagrams/*.md` updated to match: device names, 10.99.0.0/24 underlay, WAN tunnel range 10.110.0.0/24 (was mislabelled 10.100.0.0/24), tunnel interface names, no route reflection, aggregate-only WAN policy, frr_exporter monitoring, deploy commands, and GRE NAT.

## Not verified

These need the real three-host deployment:

- BGP/OSPF/BFD sessions between containers (Containerlab links were not built in the test environment).
- GRE across VPC peering, including `gre-nat.sh` with the EC2 kernel's GRE conntrack.
- End-to-end cross-region ping and the failover test.
