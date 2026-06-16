# Purpose: implement Scale In (S2), which removes a master-replica pair from the cluster.

# Identify the master node and its replica from a given IP address
identify_node_pair() {
  local target_ip="$1"
  local cluster_nodes
  local node_info
  local node_id
  local node_role
  local master_id
  local master_info
  local replica_info
  local replica_id
  local replica_ip
  local peer_ip
  local remaining_slots
  
  echo "Identifying node pair for removal at $target_ip..."

  export SCALE_IN_REPLICA_ONLY="0"
  export SCALE_IN_ALREADY_REMOVED="0"
  cluster_nodes=$(cluster_nodes_raw)
  
  # Get the target node's info
  node_info=$(printf '%s\n' "$cluster_nodes" |
    awk -v ip="$target_ip" '$2 ~ "^" ip ":6379@" {print; exit}')
  
  if [ -z "$node_info" ]; then
    case "$target_ip" in
      10.10.0.17) peer_ip="10.10.0.18" ;;
      10.10.0.18) peer_ip="10.10.0.17" ;;
    esac

    if [ -n "$peer_ip" ]; then
      node_info=$(printf '%s\n' "$cluster_nodes" |
        awk -v ip="$peer_ip" '$2 ~ "^" ip ":6379@" && $3 !~ /fail/ {print; exit}')

      if [ -n "$node_info" ]; then
        remaining_slots=$(echo "$node_info" | awk '{
          for (i=9; i<=NF; i++) {
            if ($i !~ /^\[/) {
              print $i
            }
          }
        }')

        if [ -n "$remaining_slots" ]; then
          echo "[ERROR] Node at $target_ip is absent, but remaining scale-out node $peer_ip still owns slots: $remaining_slots"
          return 1
        fi

        replica_id=$(echo "$node_info" | awk '{print $1}')
        replica_ip="$peer_ip"
        master_id=$(echo "$node_info" | awk '{print $4}')

        export SCALE_IN_MASTER_ID="$master_id"
        export SCALE_IN_MASTER_IP="$target_ip"
        export SCALE_IN_REPLICA_ID="$replica_id"
        export SCALE_IN_REPLICA_IP="$replica_ip"
        export SCALE_IN_REPLICA_ONLY="1"

        echo "[WARN] Node $target_ip is already absent; found remaining scale-out node $replica_ip."
        echo "[OK] Remaining node: $replica_ip (ID: $replica_id)"
        return 0
      fi

      export SCALE_IN_MASTER_ID=""
      export SCALE_IN_MASTER_IP="$target_ip"
      export SCALE_IN_REPLICA_ID=""
      export SCALE_IN_REPLICA_IP="$peer_ip"
      export SCALE_IN_ALREADY_REMOVED="1"

      echo "[OK] Scale-out pair $target_ip/$peer_ip is already absent from the cluster."
      return 0
    fi

    echo "[ERROR] Node at $target_ip not found in cluster."
    return 1
  fi
  
  node_id=$(echo "$node_info" | awk '{print $1}')
  node_role=$(echo "$node_info" | awk '{print $3}')

  if echo "$node_role" | grep -q "fail"; then
    echo "[ERROR] Node at $target_ip is marked failed in the cluster: $node_role"
    return 1
  fi
  
  # If target is a master, find its replica
  if echo "$node_role" | grep -q "master"; then
    master_id="$node_id"
    replica_info=$(printf '%s\n' "$cluster_nodes" |
      awk -v master_id="$master_id" \
        '$3 ~ /slave/ && $3 !~ /fail/ && $4 == master_id {print; exit}')
    
    if [ -z "$replica_info" ]; then
      echo "[ERROR] No healthy replica found for master at $target_ip. Scale in removes a master-replica pair."
      return 1
    else
      replica_id=$(echo "$replica_info" | awk '{print $1}')
      replica_ip=$(echo "$replica_info" | awk -F: '{print $1}' | awk '{print $NF}')
    fi
  # If target is a replica, find its master
  elif echo "$node_role" | grep -q "slave"; then
    master_id=$(echo "$node_info" | awk '{print $4}')
    replica_id="$node_id"
    replica_ip="$target_ip"
    
    # Get the master's IP from cluster nodes
    master_info=$(printf '%s\n' "$cluster_nodes" |
      awk -v master_id="$master_id" '$1 == master_id {print; exit}')
    
    if [ -z "$master_info" ]; then
      if [[ "$target_ip" =~ ^10\.10\.0\.(17|18)$ ]] &&
         ! printf '%s\n' "$cluster_nodes" | awk '$2 ~ /^10.10.0.17:6379@/ {found=1} END {exit(found ? 0 : 1)}'; then
        export SCALE_IN_MASTER_ID="$master_id"
        export SCALE_IN_MASTER_IP=""
        export SCALE_IN_REPLICA_ID="$replica_id"
        export SCALE_IN_REPLICA_IP="$replica_ip"
        export SCALE_IN_REPLICA_ONLY="1"

        echo "[WARN] Master with ID $master_id is already absent; treating $replica_ip as a remaining scale-out node."
        return 0
      else
        echo "[ERROR] Master with ID $master_id not found."
        return 1
      fi
    fi
    
    target_ip=$(echo "$master_info" | awk -F: '{print $1}' | awk '{print $NF}')

    if ! [[ "$target_ip" =~ ^10\.10\.0\.(17|18)$ ]]; then
      echo "[ERROR] Refusing to remove replica $replica_ip because its master $target_ip is not a scale-out node."
      return 1
    fi
  else
    echo "[ERROR] Node at $target_ip has unsupported cluster role: $node_role"
    return 1
  fi
  
  export SCALE_IN_MASTER_ID="$master_id"
  export SCALE_IN_MASTER_IP="$target_ip"
  export SCALE_IN_REPLICA_ID="$replica_id"
  export SCALE_IN_REPLICA_IP="$replica_ip"
  
  echo "[OK] Master: $target_ip (ID: $master_id)"
  if [ -n "$replica_ip" ]; then
    echo "[OK] Replica: $replica_ip (ID: $replica_id)"
  fi
  
  return 0
}

# Verify the nodes to remove own no slots before removing
verify_node_migration_ready() {
  local master_slots
  local replica_slots
  
  echo "Verifying slots have been migrated..."
  
  master_slots=$(container_exec_root redis-node-1 \
    redis-cli -h 10.10.0.11 -p 6379 cluster nodes | \
    awk -v node_id="$SCALE_IN_MASTER_ID" \
      '$1 == node_id {
        for (i=9; i<=NF; i++) {
          if ($i !~ /^\[/) {
            print $i
          }
        }
      }')
  
  if [ -n "$master_slots" ]; then
    echo "[ERROR] Master still owns slots: $master_slots"
    return 1
  fi
  
  echo "[OK] Master owns no slots, ready for removal"
  return 0
}

# Get container names for the nodes to remove
get_container_names_for_removal() {
  local master_id="$1"
  local replica_id="$2"
  local cluster_nodes
  local master_container
  local replica_container
  local node_info
  
  cluster_nodes=$(cluster_nodes_raw)
  
  # Map node IDs back to container names
  node_info=$(echo "$cluster_nodes" | awk -v node_id="$master_id" '$1 == node_id {print}')
  if [ -n "$node_info" ]; then
    if echo "$node_info" | awk '$2 ~ /^10.10.0.17:6379@/ {found=1} END {exit(found ? 0 : 1)}'; then
      master_container="redis-node-7"
    elif echo "$node_info" | awk '$2 ~ /^10.10.0.18:6379@/ {found=1} END {exit(found ? 0 : 1)}'; then
      master_container="redis-node-8"
    fi
  fi

  if [ -n "$replica_id" ]; then
    node_info=$(echo "$cluster_nodes" | awk -v node_id="$replica_id" '$1 == node_id {print}')
    if [ -n "$node_info" ]; then
      if echo "$node_info" | awk '$2 ~ /^10.10.0.17:6379@/ {found=1} END {exit(found ? 0 : 1)}'; then
        replica_container="redis-node-7"
      elif echo "$node_info" | awk '$2 ~ /^10.10.0.18:6379@/ {found=1} END {exit(found ? 0 : 1)}'; then
        replica_container="redis-node-8"
      fi
    fi
  fi
  
  export SCALE_IN_MASTER_CONTAINER="$master_container"
  export SCALE_IN_REPLICA_CONTAINER="$replica_container"
}

remove_scale_out_container_if_present() {
  local container="$1"

  case "$container" in
    redis-node-7|redis-node-8)
      if is_container_running "$container"; then
        remove_container "$container" >/dev/null 2>&1
        echo "[OK] Stopped container $container"
      fi
      ;;
    "")
      return 0
      ;;
    *)
      echo "[ERROR] Refusing to stop non-scale-out container: $container"
      return 1
      ;;
  esac
}

scale_in_command() {
  local action="${1:-}"
  local node_spec="${2:-}"
  
  if [ "$action" != "--remove-node" ] || [ -z "$node_spec" ] || [ "$#" -ne 2 ]; then
    echo "Usage:"
    echo "  ./redis-tool scale --remove-node <node-ip>"
    echo ""
    echo "Example:"
    echo "  ./redis-tool scale --remove-node 10.10.0.17"
    exit 1
  fi
  
  require_healthy_cluster "Scale in"
  
  # Validate the node IP format
  if ! [[ "$node_spec" =~ ^10\.10\.0\.[0-9]+$ ]]; then
    echo "[ERROR] Invalid node IP format: $node_spec"
    exit 1
  fi
  
  # Prevent removal of base cluster nodes
  if [[ "$node_spec" =~ ^10\.10\.0\.(11|12|13|14|15|16)$ ]]; then
    echo "[ERROR] Cannot remove base cluster nodes (10.10.0.11-16). Only scale-out nodes (10.10.0.17-18) can be removed."
    exit 1
  fi
  
  echo "Starting Redis Cluster scale in..."
  echo "Removing node: $node_spec"
  
  if ! identify_node_pair "$node_spec"; then
    exit 1
  fi
  
  get_container_names_for_removal "$SCALE_IN_MASTER_ID" "$SCALE_IN_REPLICA_ID"
  
  {
    echo "===== Redis Scale In Started ====="
    date
    echo ""
    echo "===== Target Node Details ====="
    echo "Master IP: $SCALE_IN_MASTER_IP"
    echo "Master ID: $SCALE_IN_MASTER_ID"
    if [ -n "$SCALE_IN_REPLICA_IP" ]; then
      echo "Replica IP: $SCALE_IN_REPLICA_IP"
      echo "Replica ID: $SCALE_IN_REPLICA_ID"
    fi
    echo ""

    if [ "${SCALE_IN_ALREADY_REMOVED:-0}" = "1" ]; then
      echo "===== Scale-In Already Complete ====="
      echo "[OK] Requested scale-out pair is already absent"
      echo ""
      echo "===== Full Verification After Scale In ====="
      ansible-playbook -i "$INVENTORY" ansible/playbooks/verify_full.yml
      echo ""
      structured_log "INFO" "scale_in" "success" "already_complete" \
        "missing_master_ip=$SCALE_IN_MASTER_IP missing_replica_ip=$SCALE_IN_REPLICA_IP"
      echo "SCALE IN COMPLETE - requested nodes already absent"
      echo "===== Redis Scale In Completed ====="
      date
      return
    fi

    if [ "${SCALE_IN_REPLICA_ONLY:-0}" = "1" ]; then
      echo "===== Removing Remaining Scale-Out Node from Cluster ====="
      container_exec_root redis-node-1 \
        redis-cli --cluster del-node 10.10.0.11:6379 "$SCALE_IN_REPLICA_ID"
      echo "[OK] Removed remaining scale-out node from cluster"
      echo ""
      echo "===== Stopping Containers ====="
      remove_scale_out_container_if_present "$SCALE_IN_REPLICA_CONTAINER"
      echo ""
      echo "===== Full Verification After Scale In ====="
      ansible-playbook -i "$INVENTORY" ansible/playbooks/verify_full.yml
      echo ""
      structured_log "INFO" "scale_in" "success" "completed" \
        "removed_remaining_node_id=$SCALE_IN_REPLICA_ID missing_peer_ip=$SCALE_IN_MASTER_IP"
      echo "SCALE IN COMPLETE - removed remaining scale-out node"
      echo "===== Redis Scale In Completed ====="
      date
      return
    fi

    echo "===== Migrating Slots from Target Master ====="
    ansible-playbook -i "$INVENTORY" \
      ansible/playbooks/scale_in.yml \
      -e "target_master_id=$SCALE_IN_MASTER_ID" \
      -e "target_master_ip=$SCALE_IN_MASTER_IP" \
      -e "target_replica_id=$SCALE_IN_REPLICA_ID" \
      -e "target_replica_ip=$SCALE_IN_REPLICA_IP"
    echo ""
    echo "===== Verifying Slot Migration ====="
    if ! verify_node_migration_ready; then
      echo "[ERROR] Slot migration verification failed. Aborting scale in."
      exit 1
    fi
    echo ""
    echo "===== Removing Nodes from Cluster ====="
    
    container_exec_root redis-node-1 \
      redis-cli --cluster del-node 10.10.0.11:6379 "$SCALE_IN_REPLICA_ID"
    echo "[OK] Removed replica from cluster"
    
    container_exec_root redis-node-1 \
      redis-cli --cluster del-node 10.10.0.11:6379 "$SCALE_IN_MASTER_ID"
    echo "[OK] Removed master from cluster"
    
    echo ""
    echo "===== Stopping Containers ====="
    remove_scale_out_container_if_present "$SCALE_IN_REPLICA_CONTAINER"
    if [ "$SCALE_IN_MASTER_CONTAINER" != "$SCALE_IN_REPLICA_CONTAINER" ]; then
      remove_scale_out_container_if_present "$SCALE_IN_MASTER_CONTAINER"
    fi
    
    echo ""
    echo "===== Full Verification After Scale In ====="
    ansible-playbook -i "$INVENTORY" ansible/playbooks/verify_full.yml
    echo ""
    structured_log "INFO" "scale_in" "success" "completed" \
      "removed_master_id=$SCALE_IN_MASTER_ID removed_replica_id=$SCALE_IN_REPLICA_ID"
    echo "SCALE IN COMPLETE - removed master and replica"
    echo "===== Redis Scale In Completed ====="
    date
  } | tee "$SCALE_IN_OUTPUT"
}
