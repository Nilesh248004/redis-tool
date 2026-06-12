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