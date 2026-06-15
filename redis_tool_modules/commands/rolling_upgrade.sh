# Purpose: implement Phase 4, which upgrades Redis nodes while checking availability.

upgrade_command() {
  TARGET_VERSION="7.2.6"
  STRATEGY="rolling"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --target-version)
        TARGET_VERSION="$2"
        shift 2
        ;;
      --strategy)
        STRATEGY="$2"
        shift 2
        ;;
      *)
        echo "[ERROR] Unknown option: $1"
        exit 1
        ;;
    esac
  done

  if [ "$STRATEGY" != "rolling" ]; then
    echo "[ERROR] Only rolling upgrade strategy is supported."
    exit 1
  fi

  if all_cluster_nodes_at_version "$TARGET_VERSION"; then
    {
      echo "===== Redis Rolling Upgrade Started ====="
      date
      echo "Target version: $TARGET_VERSION"
      echo "Strategy: $STRATEGY"
      echo ""
      printf '%s' "$CLUSTER_VERSION_REPORT"
      echo ""
      echo "All cluster nodes are already running Redis $TARGET_VERSION."
      echo "No upgrade is required; exiting cleanly without restarting any node."
      echo "UPGRADE NO-OP - all nodes already at target version"
      echo "===== Redis Rolling Upgrade Completed ====="
      date
    } | tee "$UPGRADE_NOOP_OUTPUT"

    structured_log "INFO" "all" "upgrade" "skipped" \
      "all nodes already at target_version=$TARGET_VERSION"
    return 0
  fi

  echo "Starting Redis rolling upgrade..."
  echo "Target version: $TARGET_VERSION"
  echo "Strategy: $STRATEGY"
  create_rollback_inventory_args

  {
    echo "===== Redis Rolling Upgrade Started ====="
    date
    echo "Target version: $TARGET_VERSION"
    echo "Strategy: $STRATEGY"
    echo ""
    echo "===== Pre-upgrade Cluster Info ====="
    ansible -i "$INVENTORY" redis-node-1 -m shell -a "redis-cli -h 10.10.0.11 -p 6379 cluster info"
    echo ""
    echo "===== Pre-upgrade Data Verification ====="
    ansible-playbook -i "$INVENTORY" ansible/playbooks/data_verify.yml -e keys=1000
    echo ""
    echo "===== Rolling Upgrade Playbook ====="
    echo "Starting cluster-aware availability monitor..."
    start_availability_monitor

    if ansible-playbook \
      "${ROLLBACK_INVENTORY_ARGS[@]}" \
      ansible/playbooks/upgrade.yml \
      -e target_version="$TARGET_VERSION"; then
      echo ""
      echo "===== Rolling Upgrade Availability Result ====="

      if ! stop_availability_monitor; then
        echo "[ERROR] Client-visible read outage detected during rolling upgrade."
        return 1
      fi
    else
      upgrade_rc=$?
      stop_availability_monitor || true
      return "$upgrade_rc"
    fi

    echo ""
    echo "===== Post-upgrade Cluster Info ====="
    ansible -i "$INVENTORY" redis-node-1 -m shell -a "redis-cli -h 10.10.0.11 -p 6379 cluster info"
    echo ""
    echo "===== Post-upgrade Cluster Nodes ====="
    ansible -i "$INVENTORY" redis-node-1 -m shell -a "redis-cli -h 10.10.0.11 -p 6379 cluster nodes"
    echo ""
    echo "===== Post-upgrade Redis Versions ====="
    ansible "${ROLLBACK_INVENTORY_ARGS[@]}" redis_nodes -m shell -a "redis-server --version"
    echo ""
    echo "===== Post-upgrade Data Verification ====="
    ansible-playbook -i "$INVENTORY" ansible/playbooks/data_verify.yml -e keys=1000
    echo ""
    echo "===== Post-upgrade Cluster Status ====="
    ansible-playbook -i "$INVENTORY" ansible/playbooks/status.yml
    echo ""
    echo "UPGRADE COMPLETE - all nodes on v$TARGET_VERSION, data integrity verified"
    echo "===== Redis Rolling Upgrade Completed ====="
    date
  } | tee "$UPGRADE_OUTPUT"
}
