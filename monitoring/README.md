# Monitoring

One monitoring stack per region, started on that region's EC2 lab host after
the Containerlab topology (which creates the region's management network).

```bash
cd monitoring
docker compose --env-file env/dc-east.env up -d          # dc-west.env / dc-eu.env on the other hosts
```

| Service | Default | Container | Mgmt IP | Host port (127.0.0.1) |
|---------|---------|-----------|---------|-----------------------|
| Prometheus | on | `rc-<region>-prometheus` | `.41` | 9090 / 9091 / 9092 (east / west / eu) |
| Grafana | on | `rc-<region>-grafana` | `.42` | 3000 / 3001 / 3002 |
| SuzieQ poller | `--profile suzieq` | `rc-<region>-suzieq` | `.43` | — |
| Batfish | `--profile batfish` | `rc-<region>-batfish` | services net only | 9996 / 10006 / 10016 |
| dnsmasq | `--profile dns` | `rc-<region>-dnsmasq` | `.46` | — (not published) |

Mgmt IPs are in the region's management subnet (`10.255.255.0/24` east,
`10.254.255.0/24` west, `10.253.255.0/24` eu). Each stack also creates its own
services network (`10.20.0.0/24`, `10.21.0.0/24`, `10.22.0.0/24`).

Ports bind to localhost only. From your machine:

```bash
ssh -J ec2-user@<bastion> -L 3000:localhost:3000 -L 9090:localhost:9090 ec2-user@<lab-host>
```

Grafana login is `admin` / `admin` unless `GRAFANA_ADMIN_PASSWORD` is exported
before `docker compose up`.

## Metrics: frr_exporter

Every FRR node runs [frr_exporter](https://github.com/tynany/frr_exporter) on
`:9342` if `bin/frr_exporter` exists when the topology is deployed:

```bash
scripts/fetch-frr-exporter.sh      # once per EC2 host, before containerlab deploy
```

Prometheus reads its targets from `prometheus/targets/<region>.yml` (7 FRR
nodes per region, labelled with `device`, `role`, `region`). Metrics include
BGP peer state and prefixes, OSPF neighbors, BFD peer state, and route counts.
A ready-made Grafana dashboard is published as ID
[22943](https://grafana.com/grafana/dashboards/22943-frr-exporter-bgp/)
(Dashboards → Import).

This replaces gNMIc: FRR has no OpenConfig gNMI server, so gNMIc had nothing
to subscribe to.

## Batfish (optional)

Batfish analyses configs offline. Build a snapshot, then query it with pybatfish:

```bash
R=dc-east; mkdir -p batfish/snapshots/$R/configs
for d in ../configs/frr/$R-* ../configs/frr/wan-${R#dc-}; do
  cp "$d/frr.conf" "batfish/snapshots/$R/configs/$(basename "$d").cfg"
done
docker compose --env-file env/$R.env --profile batfish up -d
pip install pybatfish
python3 - <<'PY'
from pybatfish.client.session import Session
bf = Session(host="localhost")
bf.set_network("resilientcloud")
bf.init_snapshot("batfish/snapshots/dc-east", name="dc-east", overwrite=True)
print(bf.q.initIssues().answer().frame())
print(bf.q.bgpSessionCompatibility().answer().frame())
PY
```

Batfish parses FRR through its Cumulus/FRR support; expect some lines to be
reported as unrecognized.

## SuzieQ (optional)

SuzieQ polls devices over SSH, and the FRR image has no SSH server. To use it:

1. Put a key pair in `suzieq/ssh/` (`id_ed25519`, git-ignored).
2. On each FRR node: `apk add openssh`, add the public key to
   `/root/.ssh/authorized_keys`, run `ssh-keygen -A && /usr/sbin/sshd`.
3. `docker compose --env-file env/<region>.env --profile suzieq up -d`

The inventory for each region is `suzieq/inventory.<region>.yml`.
