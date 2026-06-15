# Purpose: implement Phase 1, which provisions the base six-node Redis Cluster.
provision() {
  local version="7.0.15"
  local masters="3"
  local replicas_per_master="1"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --version)
        require_option_value "$1" "${2:-}"
        version="$2"
        shift 2
        ;;
      --masters)
        require_option_value "$1" "${2:-}"
        masters="$2"
        shift 2
        ;;
      --replicas-per-master)
        require_option_value "$1" "${2:-}"
        replicas_per_master="$2"
        shift 2
        ;;
      *)
        echo "[ERROR] Unknown option: $1"
        exit 1
        ;;
    esac
  done

  validate_redis_version "$version"

  if [ "$masters" != "3" ] || [ "$replicas_per_master" != "1" ]; then
    echo "[ERROR] This six-node topology requires --masters 3 --replicas-per-master 1."
    exit 1
  fi

  ensure_infra_running

  if healthy_existing_cluster; then
    collect_required_node_versions

    {
      echo "===== Redis Cluster Provision Started ====="
      date
      echo "Redis version requested: $version"
      echo "Masters: $masters"
      echo "Replicas per master: $replicas_per_master"
      echo ""
      echo "Redis Cluster is already provisioned and healthy."
      echo "Provisioning was skipped to preserve the existing cluster and data."
      echo ""
      printf '%s' "$REQUIRED_NODE_VERSION_REPORT"
      echo ""
      echo "Use './redis-tool upgrade --target-version $version --strategy rolling' to change versions safely."
      echo "PROVISION SKIPPED - existing healthy cluster was left unchanged"
      echo "===== Redis Cluster Provision Completed ====="
      date
    } | tee "$PROVISION_OUTPUT"

    structured_log "INFO" "all" "provision" "skipped" \
      "healthy cluster already exists; requested_version=$version; data_preserved=true"
    return 0
  fi

  if partial_existing_cluster; then
    structured_log "ERROR" "all" "provision" "blocked" \
      "existing cluster is not healthy; destructive reprovision refused"
    echo "[ERROR] Existing Redis Cluster state was detected, but it is not healthy."
    echo "Provisioning was stopped to avoid data loss. Repair or remove the existing cluster explicitly."
    return 1
  fi

  echo "Provisioning Redis Cluster..."
  echo "Version: $version"
  echo "Masters: $masters"
  echo "Replicas per master: $replicas_per_master"

  {
    echo "===== Redis Cluster Provision Started ====="
    date
    echo "Redis version: $version"
    echo "Masters: $masters"
    echo "Replicas per master: $replicas_per_master"
    echo ""
    echo "===== Running Provision Playbook ====="
    ansible-playbook -i "$INVENTORY" ansible/playbooks/provision.yml -e redis_version="$version"
    echo ""
    echo "===== Final Cluster Info ====="
    ansible -i "$INVENTORY" redis-node-1 -m shell -a "redis-cli -h 10.10.0.11 -p 6379 cluster info"
    echo ""
    echo "===== Final Cluster Nodes ====="
    ansible -i "$INVENTORY" redis-node-1 -m shell -a "redis-cli -h 10.10.0.11 -p 6379 cluster nodes"
    echo ""
    echo "===== Redis Cluster Provision Completed ====="
    date
  } | tee "$PROVISION_OUTPUT"
}

data_command() {
  local action="${1:-}"
  local keys="1000"

  if [ -z "$action" ]; then
    echo "Usage:"
    echo "  ./redis-tool data seed --keys 1000"
    echo "  ./redis-tool data verify"
    exit 1
  fi

  case "$action" in
    seed|verify)
      ;;
    *)
      echo "Usage:"
      echo "  ./redis-tool data seed --keys 1000"
      echo "  ./redis-tool data verify"
      exit 1
      ;;
  esac

  shift || true

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --keys)
        require_option_value "$1" "${2:-}"
        keys="$2"
        shift 2
        ;;
      *)
        echo "[ERROR] Unknown option: $1"
        exit 1
        ;;
    esac
  done

  if ! [[ "$keys" =~ ^[1-9][0-9]*$ ]]; then
    echo "[ERROR] --keys must be a positive integer."
    exit 1
  fi

  require_healthy_cluster "Data operations"

  case "$action" in
    seed)
      echo "Seeding $keys keys into Redis Cluster..."
      {
        echo "===== Redis Data Seed Started ====="
        date
        echo "Keys: $keys"
        ansible-playbook -i "$INVENTORY" ansible/playbooks/data_seed.yml -e keys="$keys"
        echo "===== Redis Data Seed Completed ====="
        date
      } | tee "$DATA_SEED_OUTPUT"
      ;;
    verify)
      echo "Verifying Redis Cluster data..."
      {
        echo "===== Redis Data Verify Started ====="
        date
        echo "Keys: $keys"
        ansible-playbook -i "$INVENTORY" ansible/playbooks/data_verify.yml -e keys="$keys"
        echo "===== Redis Data Verify Completed ====="
        date
      } | tee "$VERIFY_OUTPUT"
      ;;
  esac
}

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
  local nodes=("$@")
  public_key=$(cat "$SSH_PUBLIC_KEY")

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
        exit 1
      fi

      sleep 2
    done
  done
}

ensure_infra_running() {
  echo "Checking Redis container infrastructure..."

  if [ ! -f "$COMPOSE_FILE" ]; then
    echo "[ERROR] Compose file not found: $COMPOSE_FILE"
    exit 1
  fi

  local missing_or_stopped=0
  local node

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
