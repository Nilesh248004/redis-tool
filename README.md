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
Verification successful: all 1000 keys matched
```

This confirmed that the cluster was storing and returning data correctly.

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
All 1000 keys verified successfully
No data loss
```

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
All nodes are running Redis 7.2.6
Every master has at least one replica
All replicas have master_link_status:up
All 1000 keys matched successfully
```

Final result:

```text
FULL VERIFICATION RESULT: PASS
```

The output is saved in:

```text
output/full_verify_output.txt
```

Stretch Goal S1: Scale Out

I implemented scale out to add two more Redis nodes to the existing Redis Cluster.

Command used:

./redis-tool scale --add-nodes 2

Before scale out:

3 masters + 3 replicas = 6 nodes

After scale out:

4 masters + 4 replicas = 8 nodes

New nodes added:

redis-node-7 -> 10.10.0.17 -> master
redis-node-8 -> 10.10.0.18 -> replica of redis-node-7

The scale out command adds the new nodes, rebalances hash slots, and verifies the cluster.

Final result:

Cluster state: ok
All 16384 slots covered
Every master has a replica
1000 keys verified
FULL VERIFICATION RESULT: PASS

Output file:

output/scale_out_output.txt

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

Stretch Goal Summary

S1 Scale Out completed
S3 Rollback completed

Both are available through the CLI:

./redis-tool scale --add-nodes 2
./redis-tool rollback --target-version 7.0.15
---