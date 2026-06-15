# Purpose: start Redis containers, configure SSH access, and prepare new nodes.
ensure_ssh_key_ready() {
  echo "Checking SSH key setup..."

  mkdir -p "$HOME/.ssh"

  if [ ! -f "$SSH_KEY" ] || [ ! -f "$SSH_PUBLIC_KEY" ]; then
    echo "[WARN] SSH key not found. Creating new Redis cluster SSH key..."

    ssh-keygen -t rsa -b 4096 -f "$SSH_KEY" -N "" -C "redis-cluster-key" >/dev/null

    chmod 600 "$SSH_KEY"
    chmod 644 "$SSH_PUBLIC_KEY"

    echo "[OK] SSH key created: $SSH_KEY"
  else
    echo "[OK] SSH key already exists: $SSH_KEY"
  fi
}

patch_ssh_key_to_containers() {
  echo "Patching SSH public key into Redis containers..."

  ensure_ssh_key_ready

  local public_key
  public_key=$(cat "$SSH_PUBLIC_KEY")
  local nodes=("$@")

  for node in "${nodes[@]}"; do
    echo "Patching SSH key into $node..."

    if ! is_container_running "$node"; then
      echo "[ERROR] $node is not running. Cannot patch SSH key."
      exit 1
    fi

    container_exec_root "$node" mkdir -p /home/ansible/.ssh
    container_exec_root "$node" bash -c "touch /home/ansible/.ssh/authorized_keys"
    container_exec_root "$node" bash -c "grep -qxF '$public_key' /home/ansible/.ssh/authorized_keys || echo '$public_key' >> /home/ansible/.ssh/authorized_keys"
    container_exec_root "$node" chown -R ansible:ansible /home/ansible/.ssh
    container_exec_root "$node" chmod 700 /home/ansible/.ssh
    container_exec_root "$node" chmod 600 /home/ansible/.ssh/authorized_keys

    echo "[OK] SSH key patched into $node"
  done
}

ensure_infra_running() {
  echo "Checking Redis container infrastructure..."

  if [ ! -f "$COMPOSE_FILE" ]; then
    echo "[ERROR] Compose file not found: $COMPOSE_FILE"
    exit 1
  fi

  local missing_or_stopped=0

  for node in "${REQUIRED_PROVISION_NODES[@]}"; do
    if is_container_running "$node"; then
      echo "[OK] $node is running"
    else
      echo "[WARN] $node is not running"
      missing_or_stopped=1
    fi
  done

  if [ "$missing_or_stopped" -eq 1 ]; then
    echo "Starting Redis containers..."
    compose_cmd up -d redis-node-1 redis-node-2 redis-node-3 redis-node-4 redis-node-5 redis-node-6
    echo "Waiting for containers to initialize..."
    sleep 5
  else
    echo "[OK] All required Redis containers are already running"
  fi

  patch_ssh_key_to_containers "${REQUIRED_PROVISION_NODES[@]}"
  wait_for_ssh_ports "${REQUIRED_SSH_PORTS[@]}"
}

wait_for_ssh_ports() {
  echo "Waiting for SSH access on Redis nodes..."
  local ports=("$@")

  for port in "${ports[@]}"; do
    echo "Checking SSH on localhost:$port..."

    for attempt in {1..20}; do
      if nc -z localhost "$port" >/dev/null 2>&1; then
        echo "[OK] SSH ready on port $port"
        break
      fi

      if [ "$attempt" -eq 20 ]; then
        echo "[ERROR] SSH not ready on localhost:$port"
        echo "Check container status:"
        echo "  docker ps"
        echo "Check container logs:"
        echo "  docker logs redis-node-1"
        exit 1
      fi

      sleep 2
    done
  done
}

ensure_scale_out_infra_running() {
  echo "Creating Redis scale-out container infrastructure dynamically..."

  if ! is_container_running redis-node-1; then
    echo "[ERROR] redis-node-1 is not running. Provision the base cluster first."
    exit 1
  fi

  local image
  local network
  image=$(inspect_container_image redis-node-1)
  network=$(inspect_container_network redis-node-1)

  if [ -z "$image" ] || [ -z "$network" ]; then
    echo "[ERROR] Could not detect the base Redis image or container network."
    exit 1
  fi

  echo "Base image: $image"
  echo "Cluster network: $network"

  local index
  for index in 0 1; do
    local node="${SCALE_OUT_NODES[$index]}"
    local ssh_port="${SCALE_OUT_SSH_PORTS[$index]}"
    local internal_ip="10.10.0.$((17 + index))"
    local node_image

    if cluster_has_node_ip "$internal_ip"; then
      if ! is_container_running "$node"; then
        echo "[ERROR] $node is a cluster member but its container is not running."
        echo "Start or recover that container before retrying scale-out."
        exit 1
      fi

      echo "[OK] $node already exists in the Redis cluster"
      structured_log "INFO" "$node" "scale_out_container" "already_present" \
        "address=$internal_ip ssh_port=$ssh_port"
      continue
    fi

    node_image=$(tag_scale_out_image "$image" "$node")

    if container_exists "$node"; then
      echo "Removing stale non-cluster container $node..."
      remove_container "$node"
    fi

    echo "Creating $node at $internal_ip with SSH port $ssh_port..."
    run_scale_out_container "$node" "$ssh_port" "$internal_ip" "$node_image" "$network" >/dev/null
    echo "[OK] Created $node"
    structured_log "INFO" "$node" "scale_out_container" "created" \
      "address=$internal_ip ssh_port=$ssh_port image=$node_image network=$network"
  done

  patch_ssh_key_to_containers "${SCALE_OUT_NODES[@]}"
  wait_for_ssh_ports "${SCALE_OUT_SSH_PORTS[@]}"
}
