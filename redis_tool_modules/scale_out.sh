# Purpose: create redis-node-7 and redis-node-8 and add them to the cluster.
ensure_scale_out_infra_running() {
  echo "Creating Redis scale-out container infrastructure dynamically..."

  if ! is_container_running redis-node-1; then
    echo "[ERROR] redis-node-1 is not running. Provision the base cluster first."
    exit 1
  fi

  local image
  local network
  local index
  image=$(inspect_container_image redis-node-1)
  network=$(inspect_container_network redis-node-1)

  if [ -z "$image" ] || [ -z "$network" ]; then
    echo "[ERROR] Could not detect the base Redis image or container network."
    exit 1
  fi

  for index in 0 1; do
    local node="${SCALE_OUT_NODES[$index]}"
    local ssh_port="${SCALE_OUT_SSH_PORTS[$index]}"
    local internal_ip="10.10.0.$((17 + index))"
    local node_image

    if cluster_has_node_ip "$internal_ip"; then
      if ! is_container_running "$node"; then
        echo "[ERROR] $node is a cluster member but its container is not running."
        exit 1
      fi
      echo "[OK] $node already exists in the Redis cluster"
      continue
    fi

    node_image=$(tag_scale_out_image "$image" "$node")

    if container_exists "$node"; then
      remove_container "$node"
    fi

    echo "Creating $node at $internal_ip with SSH port $ssh_port..."
    run_scale_out_container "$node" "$ssh_port" "$internal_ip" "$node_image" "$network" >/dev/null
    structured_log "INFO" "$node" "scale_out_container" "created" \
      "address=$internal_ip ssh_port=$ssh_port image=$node_image network=$network"
  done

  patch_ssh_key_to_containers "${SCALE_OUT_NODES[@]}"
  wait_for_ssh_ports "${SCALE_OUT_SSH_PORTS[@]}"
}

scale_command() {
  local action="${1:-}"
  
  if [ -z "$action" ]; then
    echo "Usage:"
    echo "  ./redis-tool scale --add-nodes 2"
    echo "  ./redis-tool scale --remove-node <node-ip>"
    exit 1
  fi
  
  # Dispatch to appropriate handler
  case "$action" in
    --add-nodes)
      scale_out_add_nodes "$@"
      ;;
    --remove-node)
      scale_in_command "$@"
      ;;
    *)
      echo "[ERROR] Unknown scale action: $action"
      echo "Usage:"
      echo "  ./redis-tool scale --add-nodes 2"
      echo "  ./redis-tool scale --remove-node <node-ip>"
      exit 1
      ;;
  esac
}

scale_out_add_nodes() {
  local action="${1:-}"
  local value="${2:-}"

  if [ "$action" != "--add-nodes" ] || [ "$value" != "2" ] || [ "$#" -ne 2 ]; then
    echo "Usage:"
    echo "  ./redis-tool scale --add-nodes 2"
    exit 1
  fi

  require_healthy_cluster "Scale out"

  echo "Starting Redis Cluster scale out..."
  echo "Adding 2 nodes: 1 master and 1 replica"
  create_scale_out_inventory

  {
    echo "===== Redis Scale Out Started ====="
    date
    echo ""
    echo "===== Creating Dynamic Scale-Out Infrastructure ====="
    ensure_scale_out_infra_running
    echo ""
    echo "===== Running Scale Out Playbook ====="
    ansible-playbook \
      -i "$INVENTORY" \
      -i "$SCALE_OUT_INVENTORY" \
      ansible/playbooks/scale_out.yml
    echo ""
    echo "===== Full Verification After Scale Out ====="
    ansible-playbook -i "$INVENTORY" ansible/playbooks/verify_full.yml
    echo ""
    structured_log "INFO" "redis-node-7" "scale_out" "success" \
      "role=master address=10.10.0.17:6379 slots=rebalanced"
    structured_log "INFO" "redis-node-8" "scale_out" "success" \
      "role=replica address=10.10.0.18:6379 master=redis-node-7"
    echo "SCALE OUT COMPLETE - added redis-node-7 master and redis-node-8 replica"
    echo "===== Redis Scale Out Completed ====="
    date
  } | tee "$SCALE_OUT_OUTPUT"
}
