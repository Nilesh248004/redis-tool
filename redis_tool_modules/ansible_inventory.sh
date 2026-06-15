# Purpose: create temporary Ansible inventories for scale-out, upgrade, and rollback.
create_scale_out_inventory() {
  SCALE_OUT_INVENTORY=$(mktemp /tmp/redis-scale-out-inventory.XXXXXX)
  TEMP_FILES+=("$SCALE_OUT_INVENTORY")

  {
    echo "[redis_new_nodes]"
    echo "redis-node-7 ansible_host=localhost ansible_port=2217 internal_ip=10.10.0.17"
    echo "redis-node-8 ansible_host=localhost ansible_port=2218 internal_ip=10.10.0.18"
    echo ""
    echo "[redis_new_nodes:vars]"
    echo "ansible_user=ansible"
    echo "ansible_ssh_private_key_file=$SSH_KEY"
    echo "ansible_python_interpreter=/usr/bin/python3"
    echo "ansible_ssh_common_args=-o StrictHostKeyChecking=no"
  } > "$SCALE_OUT_INVENTORY"
}

create_rollback_inventory_args() {
  local cluster_nodes
  local dynamic_nodes=()

  ROLLBACK_INVENTORY_ARGS=(-i "$INVENTORY")
  cluster_nodes=$(cluster_nodes_raw)

  if printf '%s\n' "$cluster_nodes" | grep -q '[[:space:]]10.10.0.17:6379@'; then
    dynamic_nodes+=("redis-node-7 ansible_host=localhost ansible_port=2217 internal_ip=10.10.0.17")
  fi

  if printf '%s\n' "$cluster_nodes" | grep -q '[[:space:]]10.10.0.18:6379@'; then
    dynamic_nodes+=("redis-node-8 ansible_host=localhost ansible_port=2218 internal_ip=10.10.0.18")
  fi

  if [ "${#dynamic_nodes[@]}" -eq 0 ]; then
    return
  fi

  ROLLBACK_INVENTORY=$(mktemp /tmp/redis-rollback-inventory.XXXXXX)
  TEMP_FILES+=("$ROLLBACK_INVENTORY")

  {
    echo "[redis_nodes]"
    printf '%s\n' "${dynamic_nodes[@]}"
    echo ""
    echo "[redis_nodes:vars]"
    echo "ansible_user=ansible"
    echo "ansible_ssh_private_key_file=$SSH_KEY"
    echo "ansible_python_interpreter=/usr/bin/python3"
    echo "ansible_ssh_common_args=-o StrictHostKeyChecking=no"
  } > "$ROLLBACK_INVENTORY"

  ROLLBACK_INVENTORY_ARGS+=(-i "$ROLLBACK_INVENTORY")
}
