# Redis Cluster Lifecycle Tool

## Project Overview

This project is about creating a Redis Cluster automation tool using Docker, Ansible, and a custom CLI called `redis-tool`.

The goal is to automate the Redis cluster setup instead of doing everything manually. In Phase 1, I created the basic infrastructure, connected to all containers using SSH, installed Redis, configured cluster mode, and created a working Redis Cluster with 3 masters and 3 replicas.

---

## Phase 1: Infrastructure and Redis Cluster Provisioning

### 1. Created Dockerfile

First, I created a Dockerfile inside the `infra/` folder.

The Dockerfile is used to build an Ubuntu-based image. This image contains the required packages for SSH access, Python support for Ansible, and a separate `ansible` user.

The main purpose of this Dockerfile is to make each container behave like a small Linux server. Redis is not directly installed through Dockerfile. Instead, Redis installation is automated later using Ansible.

---

### 2. Created 6 Ubuntu Containers Using `compose.yml`

Next, I created a `compose.yml` file to start 6 Ubuntu containers.

The containers are named:

```text
redis-node-1
redis-node-2
redis-node-3
redis-node-4
redis-node-5
redis-node-6
```

Each container runs in the same Docker network and has a static IP address:

```text
redis-node-1 -> 10.10.0.11
redis-node-2 -> 10.10.0.12
redis-node-3 -> 10.10.0.13
redis-node-4 -> 10.10.0.14
redis-node-5 -> 10.10.0.15
redis-node-6 -> 10.10.0.16
```

This setup is required because Redis Cluster nodes must communicate with each other using stable IP addresses.

---

### 3. Configured SSH Access

After creating the containers, I configured SSH access for all 6 containers.

My Mac acts as the Ansible control node, and the 6 containers act as managed nodes.

I created an SSH key pair and added the public key inside the containers for the `ansible` user. This allows Ansible to connect to each container without using passwords.

The private key is not pushed to GitHub for security reasons. Only the public key file is included.

---

### 4. Checked All Containers Are Running

After starting the containers using Docker Compose, I checked whether all 6 containers were running successfully.

I used Docker commands to confirm the containers were active and also verified SSH connectivity from my Mac to each container.

I also tested Ansible connectivity using:

```bash
ansible -i ansible/inventory/hosts.ini redis_nodes -m ping
```

All 6 nodes returned successful `pong` responses, which confirmed that Ansible was able to connect to every container.

---

## Redis Installation and Cluster Creation

After confirming the infrastructure and SSH setup, I used Ansible playbooks to install Redis 7.0.15 on all 6 nodes.

The playbooks used in Phase 1 are:

```text
ansible/playbooks/install_redis.yml
ansible/playbooks/configure_redis.yml
ansible/playbooks/create_cluster.yml
```

Redis was installed from source to make sure the exact required version, Redis 7.0.15, was installed on every node.

After installation, I configured Redis in cluster mode by enabling:

```text
cluster-enabled yes
cluster-config-file nodes.conf
cluster-node-timeout 5000
```

Then I created the Redis Cluster with:

```text
3 master nodes
3 replica nodes
```

The final cluster status showed:

```text
cluster_state:ok
cluster_slots_assigned:16384
cluster_slots_ok:16384
cluster_known_nodes:6
cluster_size:3
```

This confirms that the Redis Cluster was created successfully.

---

## CLI Command for Phase 1

The Phase 1 provisioning can be executed using:

```bash
./redis-tool provision --version 7.0.15 --masters 3 --replicas-per-master 1
```

This command runs the Ansible playbooks for Redis installation, Redis configuration, and Redis Cluster creation.

The output is saved in:

```text
output/provision_output.txt
```

---

## Phase 1 Status

Phase 1 is completed successfully.

Completed work:

```text
Created Dockerfile
Created 6 Ubuntu containers using compose.yml
Configured SSH access
Verified all containers are running
Verified Ansible connectivity
Installed Redis 7.0.15 on all nodes
Configured Redis cluster mode
Created Redis Cluster with 3 masters and 3 replicas
Verified cluster_state:ok
Saved provision output
```

---

## Phase 2: Data Seed and Verification

In Phase 2, I added data seeding and verification for the Redis Cluster.

The main goal of this phase is to insert test data into the cluster and then verify that the same data can be read back correctly.

---

### 1. Created Data Seed Playbook

I created an Ansible playbook named:

```text
ansible/playbooks/data_seed.yml
```

This playbook connects to the Redis Cluster through `redis-node-1` and inserts 1000 deterministic key-value pairs.

The keys are created in this format:

```text
user:1   -> value-1
user:2   -> value-2
user:3   -> value-3
...
user:1000 -> value-1000
```

I used deterministic data because it makes verification simple. Since the expected value is already known for each key, we can easily check whether the data is correct or not.

---

### 2. Used Redis Cluster Mode While Seeding Data

While inserting data, I used the Redis CLI with cluster mode enabled:

```bash
redis-cli -c
```

The `-c` option is important because this is a Redis Cluster. Keys may belong to different hash slots, and Redis may redirect the command to the correct master node.

So even though the command starts from `10.10.0.11`, Redis Cluster automatically routes the key to the correct node.

---

### 3. Created Data Verify Playbook

I created another Ansible playbook named:

```text
ansible/playbooks/data_verify.yml
```

This playbook checks all 1000 keys one by one.

For every key, it compares the actual value from Redis with the expected value.

Example:

```text
Expected: user:10 -> value-10
Actual:   user:10 -> value-10
Result:   matched
```

If any key has a wrong value or is missing, the playbook reports a failure.

---

### 4. Added CLI Support for Data Commands

I updated the `redis-tool` CLI to support Phase 2 commands.

The seed command is:

```bash
./redis-tool data seed --keys 1000
```

The verify command is:

```bash
./redis-tool data verify
```

These commands internally run the Ansible playbooks:

```text
ansible/playbooks/data_seed.yml
ansible/playbooks/data_verify.yml
```

---

### 5. Saved Phase 2 Output Files

The output of the seed command is saved in:

```text
output/data_seed_output.txt
```

The output of the verify command is saved in:

```text
output/verify_output.txt
```

The final verification output showed:

```text
Verification successful: all 1000 keys matched
```

This confirms that all 1000 keys were inserted and verified successfully.

---

## Phase 2 Status

Phase 2 is completed successfully.

Completed work:

```text
Created data seed playbook
Created data verify playbook
Inserted 1000 deterministic keys
Verified all 1000 keys
Added CLI support for data seed
Added CLI support for data verify
Saved data seed output
Saved verify output
```

---

## Phase 3: Redis Cluster Status Command

In Phase 3, I added a status command to check the current health and details of the Redis Cluster.

The main goal of this phase is to provide one command that shows the complete status of the cluster, including node details, roles, Redis versions, key count, memory usage, and cluster topology.

---

### 1. Created Status Playbook

I created an Ansible playbook named:

```text
ansible/playbooks/status.yml