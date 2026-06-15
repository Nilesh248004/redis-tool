# Redis Cluster Lifecycle Tool

This project automates Redis Cluster lifecycle operations using Docker or Podman, Ansible, Redis, and a Bash CLI named `redis-tool`.

---

## Bring Up The Container Infrastructure

The project works with either Docker or Podman. Podman is preferred automatically by `redis-tool` if both Docker and Podman are installed.

Manual Docker commands:

```bash
docker compose -f infra/compose.yml build
docker compose -f infra/compose.yml up -d
```

Manual Podman commands:

```bash
podman compose -f infra/compose.yml build
podman compose -f infra/compose.yml up -d
```

To stop and remove the infrastructure:

```bash
docker compose -f infra/compose.yml down
```

or:

```bash
podman compose -f infra/compose.yml down
```

The base infrastructure creates six Ubuntu-based Redis node containers:

```text
redis-node-1
redis-node-2
redis-node-3
redis-node-4
redis-node-5
redis-node-6
```

Normally, you do not need to start the containers manually. The provision command checks and starts the required containers automatically.

## Project Structure

```text
submission/
├── redis-tool
├── README.md
├── ansible/
│   ├── ansible.cfg
│   ├── inventory/
│   │   └── hosts.ini
│   └── playbooks/
│       ├── configure_redis.yml
│       ├── create_cluster.yml
│       ├── data_seed.yml
│       ├── data_verify.yml
│       ├── install_redis.yml
│       ├── provision.yml
│       ├── rollback.yml
│       ├── scale_out.yml
│       ├── status.yml
│       ├── upgrade.yml
│       ├── verify_full.yml
│       └── tasks/
│           └── rollback_node.yml
├── infra/
│   ├── Dockerfile
│   └── compose.yml
├── logs/
│   └── .gitkeep
├── output/
│   ├── data_seed_output.txt
│   ├── full_verify_output.txt
│   ├── provision_output.txt
│   ├── rollback_output.txt
│   ├── scale_out_output.txt
│   ├── status_output.txt
│   ├── upgrade_output.txt
│   └── verify_output.txt
└── redis_tool_modules/
    ├── health.sh
    ├── inventory.sh
    ├── logs.sh
    ├── prerequisite.sh
    ├── provision.sh
    ├── rollback.sh
    ├── scale_out.sh
    ├── status_check.sh
    ├── upgrade.sh
    └── verify.sh
```

---

## Run Each redis-tool Command

Run repository verification first:

```bash
./redis_tool_modules/verify.sh
```

Provision the base six-node Redis Cluster:

```bash
./redis-tool provision --version 7.0.15 --masters 3 --replicas-per-master 1
```

Output:

```text
output/provision_output.txt
```

Seed deterministic test data:

```bash
./redis-tool data seed --keys 1000
```

Output:

```text
output/data_seed_output.txt
```

Verify deterministic test data:

```bash
./redis-tool data verify
```

Output:

```text
output/verify_output.txt
```

Check cluster status:

```bash
./redis-tool status
```

Output:

```text
output/status_output.txt
```

Run a rolling upgrade:

```bash
./redis-tool upgrade --target-version 7.2.6 --strategy rolling
```

Output:

```text
output/upgrade_output.txt
```

Run full cluster verification:

```bash
./redis-tool verify --full
```

Output:

```text
output/full_verify_output.txt
```

Scale out the cluster:

```bash
./redis-tool scale --add-nodes 2
```

This adds:

```text
redis-node-7 -> master
redis-node-8 -> replica of redis-node-7
```

Output:

```text
output/scale_out_output.txt
```

Rollback to a target Redis version:

```bash
./redis-tool rollback --target-version 7.0.15
```

Output:

```text
output/rollback_output.txt
```

Recommended demo flow:

```bash
./redis_tool_modules/verify.sh
./redis-tool provision --version 7.0.15 --masters 3 --replicas-per-master 1
./redis-tool data seed --keys 1000
./redis-tool data verify
./redis-tool status
./redis-tool upgrade --target-version 7.2.6 --strategy rolling
./redis-tool verify --full
./redis-tool scale --add-nodes 2
./redis-tool rollback --target-version 7.0.15
```

---

## Rolling Upgrade Strategy

The rolling upgrade avoids stopping the full Redis Cluster at once.

High-level flow:

```text
Check cluster health
Upgrade replica nodes first
Use failover when a master must be upgraded
Upgrade the old master after failover
Restart Redis on the upgraded node
Verify the node version
Verify cluster health
Continue to the next node
```

Why this strategy:

- Upgrading one node at a time reduces cluster risk.
- Replicas are upgraded before masters so a healthy replica is available for failover.
- Master failover allows the cluster to keep serving while the old master is upgraded.
- The tool verifies versions, cluster health, replica links, and data integrity after upgrade.
- A lightweight availability monitor runs during upgrade to detect client-visible read outages.

If all nodes are already at the requested target version, upgrade exits cleanly:

```text
UPGRADE SKIPPED - all nodes already at target version
```

---

## Assumptions And Trade-Offs

- The project is designed for local DevOps practice.
- Redis nodes run inside local Docker/Podman containers instead of real cloud servers.
- Ansible connects to containers through SSH to simulate real server automation.
- The base topology is fixed to 3 masters and 3 replicas.
- Scale-out currently supports exactly two added nodes: one master and one replica.
- Redis is built from source to control exact versions, which is slower than package installation.
- Full verification expects deterministic test data: `user:1` through `user:1000`.
- Rollback removes potentially incompatible local RDB/AOF files before starting an older Redis version, then restores deterministic test data. This is acceptable for the lab, but it is not a production backup/restore strategy.
- The private SSH key is generated locally at `~/.ssh/redis_cluster_key` and must not be committed. The public key is patched into containers at runtime.

---

## Known Limitations

- No Kubernetes or managed Redis Cloud integration.
- No production monitoring stack such as Prometheus or Grafana.
- No automatic scale-in implemented yet.
- Scale-out is fixed to adding two nodes.
- The base provision topology is fixed to 3 masters and 3 replicas.
- Local-container performance is not equivalent to real distributed production infrastructure.
- Rollback compatibility is handled for deterministic lab data, not arbitrary production data.
- `--auto-install` is not implemented; the tool prints install instructions instead of changing the host automatically.

---

## Prerequisites

`redis-tool` checks required dependencies before running supported lifecycle commands.

Required host tools:

```text
Docker Engine or Podman
Docker Compose plugin or Podman Compose
Ansible 2.14+
nc
ssh-keygen
```

If dependencies are present, the tool prints versions and continues:

```text
[OK] Docker version ... found
[OK] Ansible ... found
Proceeding...
```

If something is missing, the tool prints install guidance and exits nonzero. It does not auto-install dependencies.

---

## Module-Based CLI Structure

`redis-tool` is the entrypoint and router. It loads focused modules from `redis_tool_modules/` using `source`.

```text
prerequisite.sh   Shared config, dependency checks, Docker/Podman helpers
provision.sh      Provision, data seed/verify, and SSH setup helpers
status_check.sh   Cluster status command
upgrade.sh        Rolling upgrade command
verify.sh         Full cluster verification and repository verification
rollback.sh       Rollback command
scale_out.sh      Scale-out command
health.sh         Cluster health and version checks
logs.sh           Structured logging
inventory.sh      Temporary dynamic inventories
```

---

## Stretch Goals Implemented

```text
S1 Scale Out
S3 Rollback
S4 Idempotency
S5 Structured Logging
```

Provision is idempotent on a healthy existing cluster:

```bash
PROVISION SKIPPED - existing healthy cluster was left unchanged
```

Every supported command creates a timestamped structured log under `logs/`.

Log format:

```bash
timestamp=... level=... command=... node=... action=... outcome=... details="..."
```

Example log entry:

```bash
timestamp=2026-06-16T14:32:45Z level=INFO command=provision node=redis-node-1 action=provision_container outcome=success details="address=10.10.0.11 ssh_port=2211 image=infra-redis-node-1 network=infra_redis-cluster-net"
```