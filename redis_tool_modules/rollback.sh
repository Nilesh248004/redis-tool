# Purpose: roll every live Redis Cluster node back to the requested version.

rollback_command() {
  local target_version=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --target-version)
        require_option_value "$1" "${2:-}"
        target_version="$2"
        shift 2
        ;;
      *)
        echo "Unknown rollback option: $1"
        echo "Usage: ./redis-tool rollback --target-version 7.0.15"
        exit 1
        ;;
    esac
  done

  if [ -z "$target_version" ]; then
    echo "Usage: ./redis-tool rollback --target-version 7.0.15"
    exit 1
  fi

  validate_redis_version "$target_version"
  require_healthy_cluster "Rollback"

  if all_cluster_nodes_at_version "$target_version"; then
    {
      echo "===== Redis Rollback Started ====="
      date
      echo "Target version: $target_version"
      echo ""
      printf '%s' "$CLUSTER_VERSION_REPORT"
      echo ""
      echo "All cluster nodes are already running Redis $target_version."
      echo "No rollback is required; exiting cleanly without restarting any node."
      echo "ROLLBACK SKIPPED - all nodes already at target version"
      echo "===== Redis Rollback Completed ====="
      date
    } | tee "$ROLLBACK_OUTPUT"

    structured_log "INFO" "all" "rollback" "skipped" \
      "all nodes already at target_version=$target_version"
    return 0
  fi

  echo "Starting Redis rollback..."
  echo "Target version: $target_version"
  create_rollback_inventory_args

  {
    echo "===== Redis Rollback Started ====="
    date
    echo "Target version: $target_version"

    echo ""
    echo "===== Pre-rollback Cluster Info ====="
    ansible -i "$INVENTORY" redis-node-1 -m shell \
      -a "redis-cli -h 10.10.0.11 -p 6379 cluster info"

    echo ""
    echo "===== Pre-rollback Data Verification ====="
    ansible-playbook -i "$INVENTORY" ansible/playbooks/data_verify.yml -e keys=1000

    echo ""
    echo "===== Running Rollback Playbook ====="
    ansible-playbook \
      "${ROLLBACK_INVENTORY_ARGS[@]}" \
      ansible/playbooks/rollback.yml \
      -e "target_version=$target_version"

    echo ""
    echo "===== Restore Deterministic Data After Rollback ====="
    ansible-playbook -i "$INVENTORY" ansible/playbooks/data_seed.yml -e keys=1000

    echo ""
    echo "===== Full Verification After Rollback ====="
    ansible-playbook -i "$INVENTORY" ansible/playbooks/verify_full.yml

    echo ""
    echo "ROLLBACK COMPLETE - changed nodes restored to v$target_version, data integrity verified"
    echo "===== Redis Rollback Completed ====="
    date
  } | tee "$ROLLBACK_OUTPUT"
}
