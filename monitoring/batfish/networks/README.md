# Batfish networks directory
#
# Place FRR config snapshots here for pre-deployment validation:
#   networks/
#   └── current/
#       ├── spine1/  (frr.conf)
#       ├── spine2/  (frr.conf)
#       ├── leaf1/   (frr.conf)
#       ├── leaf2/   (frr.conf)
#       ├── leaf3/   (frr.conf)
#       └── leaf4/   (frr.conf)
#
# Then run:
#   curl -X POST http://localhost:9996/v2/set/snapshot/new-snapshot \
#     -d '{"snapshot":"current","network":"netlab"}'
#
# Batfish will analyze configs for routing loops, ACL conflicts,
# reachability, and other issues without deploying to live routers.
