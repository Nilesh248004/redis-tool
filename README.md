# Redis Cluster Lifecycle Tool

## Project Overview

This project is about automating the setup and management of a Redis Cluster.

Redis is a fast database used to store data in memory. In this project, I created a Redis Cluster with 6 nodes using Docker, Ansible, and a custom command-line tool called `redis-tool`.

The main purpose of this project is to avoid doing the setup manually and automate the Redis Cluster lifecycle step by step.

---

## What This Project Does

This project can:

```text
Create 6 Redis server containers
Install Redis automatically
Create a Redis Cluster
Add test data into the cluster
Verify the stored data
Show cluster health and node status
Upgrade Redis safely from one version to another
```

---

## Tools Used

```text
Docker  -> To create Redis server containers
Ansible -> To automate installation and configuration
Redis   -> Database used in the cluster
Bash    -> To create the redis-tool CLI
```

---

## Redis Cluster Setup

The cluster contains 6 Redis nodes.

```text
3 nodes work as masters
3 nodes work as replicas
```

Master nodes handle the main data operations.

Replica nodes keep a copy of the master data and help during failover.

This setup improves availability because if one master has an issue, its replica can take over.

---

## Phase 1: Cluster Provisioning

In Phase 1, I created the Redis Cluster.

I used Docker to create 6 Ubuntu containers. Then I used Ansible to install Redis `7.0.15` on all nodes and configure them in cluster mode.

Command used:

```bash
./redis-tool provision --version 7.0.15 --masters 3 --replicas-per-master 1
```

Result:

```text
Redis Cluster created successfully
Cluster state: ok
Total nodes: 6
Masters: 3
Replicas: 3
All 16384 hash slots assigned
```

---

## Phase 2: Data Seed and Verification

In Phase 2, I added test data into the Redis Cluster.

I inserted 1000 key-value pairs into Redis.

Example:

```text
user:1 -> value-1
user:2 -> value-2
user:3 -> value-3
```

Command used to add data:

```bash
./redis-tool data seed --keys 1000
```

Then I verified whether all the data was stored correctly.

Command used:

```bash
./redis-tool data verify
```

Result:

```text
Key distribution across masters:
10.10.0.11:6379 -> 332 keys
10.10.0.12:6379 -> 337 keys
10.10.0.13:6379 -> 331 keys

PASS - 1000/1000 keys inserted; failures: 0
PASS - 1000/1000 keys verified
```

If verification fails, the command reports missing keys and mismatched values
separately and exits with a non-zero status.

---

## Phase 3: Cluster Status

In Phase 3, I added a status command.

This command shows the current health of the Redis Cluster.

Command used:

```bash
./redis-tool status
```

It shows:

```text
Cluster health
Master nodes
Replica nodes
Redis version
Hash slots
Key count
Memory usage
```

Result:

```text
Cluster state: ok
All nodes were connected properly
```

---

## Phase 4: Rolling Upgrade

In Phase 4, I upgraded Redis from version `7.0.15` to `7.2.6`.

The important part is that I did not stop the full cluster at once.

I used a rolling upgrade method, which means one node is upgraded at a time.

Command used:

```bash
./redis-tool upgrade --target-version 7.2.6 --strategy rolling
```

Before upgrading master nodes, I used failover.

Failover means the replica becomes the new master before the old master is upgraded.

This helps reduce downtime.

Result:

```text
All 6 nodes upgraded to Redis 7.2.6
Cluster state: ok
All 16384 hash slots covered
Availability probes: 531
Client-visible read outages: 0
PASS - 1000/1000 keys verified
UPGRADE COMPLETE - all nodes on v7.2.6, data integrity verified
```

The promoted replicas become the new masters, while the former masters rejoin
as replicas after their upgrade. This role swap is expected.

---

## Output Files

The command outputs are saved inside the `output/` folder.

```text
provision_output.txt  -> Cluster creation output
data_seed_output.txt  -> Data seed output
verify_output.txt     -> Data verification output
status_output.txt     -> Cluster status output
upgrade_output.txt    -> Rolling upgrade output
```

---

## Current Progress

The project currently includes Redis Cluster provisioning, data seeding, data verification, status checking, and rolling upgrade automation.

Further verification and final improvements can be added in the next phase.

---

## Phase 5: Full Verification

In Phase 5, I added a full verification command to check the Redis Cluster after the rolling upgrade.

The command is:

```bash
./redis-tool verify --full
```

This command performs a complete health check of the cluster.

It checks:

```text
Data integrity
Redis version consistency
Cluster state
Hash slot coverage
Master and replica topology
Replica connection status
```

The full verification confirmed:

```text
Cluster state is ok
All 16384 hash slots are covered
All 6 cluster nodes are present and reachable
All 6 nodes are running Redis 7.2.6
Topology has 3 masters and 3 replicas
Every master has at least one replica
All 3 replicas have master_link_status:up
Data integrity verified: 1000/1000 keys matched
```

Final result:

```text
Passed checks: 7
Failed checks: 0
FULL VERIFICATION RESULT: PASS
```

The output is saved in:

```text
output/full_verify_output.txt
```

Stretch Goal S1: Scale Out

The default Docker Compose file and Ansible inventory define only:

```text
redis-node-1 through redis-node-6
```

The scale-out command dynamically creates two additional containers by using
the same image and Docker network as the existing cluster. It also generates a
temporary Ansible inventory for the new nodes, installs the Redis version
currently running in the cluster, and configures their cluster announce
addresses.

Command used:

```bash
./redis-tool scale --add-nodes 2
```

Before scale out:

```text
3 masters + 3 replicas = 6 nodes
```

After scale out:

```text
4 masters + 4 replicas = 8 nodes
```

New nodes added:

```text
redis-node-7 -> 10.10.0.17 -> master
redis-node-8 -> 10.10.0.18 -> replica of redis-node-7
```

The playbook adds `redis-node-7` as a master, adds `redis-node-8` as its
replica, rebalances hash slots across all four masters, waits for the expected
topology, and runs full cluster verification.

Final result:

```text
Cluster state: ok
All 16384 slots covered
Every master has a replica
1000 keys verified
FULL VERIFICATION RESULT: PASS
```

Output file:

```text
output/scale_out_output.txt
```

⸻

Stretch Goal S3: Rollback

I implemented rollback to downgrade Redis to a previous version if needed.

Command used:

./redis-tool rollback --target-version 7.0.15

Rollback tested:

Redis 7.2.6 -> Redis 7.0.15

The rollback command downgrades Redis one node at a time and checks cluster health after each node.

During rollback, Redis 7.0.15 could not read some Redis 7.2.6 persistence files, so the playbook removes incompatible AOF/RDB files before restarting Redis.

Final rollback result:

All 8 nodes running Redis 7.0.15
Cluster state: ok
All 16384 slots covered
Every master has a replica

After rollback, data was reseeded:

./redis-tool data seed --keys 1000

Then full verification passed:

Data integrity verified: all 1000 keys matched
FULL VERIFICATION RESULT: PASS

Output file:

output/rollback_output.txt

⸻

Stretch Goal S4: Idempotency

Provisioning is safe to run against an existing healthy cluster:

```bash
./redis-tool provision --version 7.0.15 --masters 3 --replicas-per-master 1
```

The command detects all six healthy cluster nodes and exits without
reinstalling Redis, restarting nodes, clearing persistence files, or recreating
the cluster:

```text
PROVISION NO-OP - existing healthy cluster was left unchanged
```

The provision playbook has the same protection when executed directly. A
second run completed with `changed=0` on every node.

Upgrade also checks every live cluster node before starting the rolling
workflow:

```bash
./redis-tool upgrade --target-version 7.0.15 --strategy rolling
```

When every node is already at the target version, it exits successfully before
starting the availability monitor or running upgrade tasks:

```text
All cluster nodes are already running Redis 7.0.15.
No upgrade is required; exiting cleanly without restarting any node.
UPGRADE NO-OP - all nodes already at target version
```

After the provision no-op, full verification confirmed:

```text
Data integrity verified: 1000/1000 keys matched
FULL VERIFICATION RESULT: PASS
```

Stretch Goal S5: Structured Logging

Every `redis-tool` invocation creates a unique operation log in `logs/`:

```text
logs/YYYYMMDDTHHMMSSZ_<command>_<process-id>.log
```

Logs contain UTC timestamps, command names, node names, actions, outcomes,
details, the complete operation output, and the final exit code. Structured
records use this format:

```text
timestamp=2026-06-14T18:18:24Z level=INFO command=provision node=all action=provision outcome=skipped details="healthy cluster already exists; requested_version=7.0.15; data_preserved=true"
```

Successful, skipped, and failed commands are all recorded with the appropriate
final outcome.

⸻

Stretch Goal Summary

S1 Scale Out completed
S3 Rollback completed
S4 Idempotency completed
S5 Structured Logging completed

The stretch goals are available through the CLI:

./redis-tool scale --add-nodes 2
./redis-tool rollback --target-version 7.0.15

---
