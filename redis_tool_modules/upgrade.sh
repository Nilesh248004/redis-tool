# Purpose: implement Phase 4, which upgrades Redis nodes while checking availability.

upgrade_command() {
  local target_version="7.2.6"
  local strategy="rolling"
  local upgrade_rc

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --target-version)
        require_option_value "$1" "${2:-}"
        target_version="$2"
        shift 2
        ;;
      --strategy)
        require_option_value "$1" "${2:-}"
        strategy="$2"
        shift 2
        ;;
      *)
        echo "[ERROR] Unknown option: $1"
        exit 1
        ;;
    esac
  done

  validate_redis_version "$target_version"

  if [ "$strategy" != "rolling" ]; then
    echo "[ERROR] Only rolling upgrade strategy is supported."
    exit 1
  fi

  require_healthy_cluster "Rolling upgrade"

  if all_cluster_nodes_at_version "$target_version"; then
    {
      echo "===== Redis Rolling Upgrade Started ====="
      date
      echo "Target version: $target_version"
      echo "Strategy: $strategy"
      echo ""
      printf '%s' "$CLUSTER_VERSION_REPORT"
      echo ""
      echo "All cluster nodes are already running Redis $target_version."
      echo "No upgrade is required; exiting cleanly without restarting any node."
      echo "UPGRADE SKIPPED - all nodes already at target version"
      echo "===== Redis Rolling Upgrade Completed ====="
      date
    } | tee "$UPGRADE_OUTPUT"

    structured_log "INFO" "all" "upgrade" "skipped" \
      "all nodes already at target_version=$target_version"
    return 0
  fi

  echo "Starting Redis rolling upgrade..."
  echo "Target version: $target_version"
  echo "Strategy: $strategy"
  create_rollback_inventory_args

  {
    echo "===== Redis Rolling Upgrade Started ====="
    date
    echo "Target version: $target_version"
    echo "Strategy: $strategy"
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
      -e target_version="$target_version"; then
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
    echo "UPGRADE COMPLETE - all nodes on v$target_version, data integrity verified"
    echo "===== Redis Rolling Upgrade Completed ====="
    date
  } | tee "$UPGRADE_OUTPUT"
}

monitor_cluster_availability() {
  local stop_file="$1"
  local summary_file="$2"
  local log_file="$3"
  local probes=0
  local outages=0

  while [ ! -f "$stop_file" ]; do
    probes=$((probes + 1))
    local available=0
    local node

    for node in "${REQUIRED_PROVISION_NODES[@]}"; do
      local value
      value=$(container_exec_root "$node" redis-cli -c -h 127.0.0.1 -p 6379 GET user:1 2>/dev/null || true)

      if [ "$value" = "value-1" ]; then
        available=1
        break
      fi
    done

    if [ "$available" -eq 0 ]; then
      outages=$((outages + 1))
      printf '%s Cluster read failed across all six nodes\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" >> "$log_file"
    fi

    sleep 0.5
  done

  printf '%s %s\n' "$probes" "$outages" > "$summary_file"
}

start_availability_monitor() {
  AVAILABILITY_SUMMARY_FILE=$(mktemp /tmp/redis-upgrade-availability.XXXXXX)
  AVAILABILITY_STOP_FILE="${AVAILABILITY_SUMMARY_FILE}.stop"
  AVAILABILITY_LOG_FILE="${AVAILABILITY_SUMMARY_FILE}.log"

  monitor_cluster_availability \
    "$AVAILABILITY_STOP_FILE" \
    "$AVAILABILITY_SUMMARY_FILE" \
    "$AVAILABILITY_LOG_FILE" &
  AVAILABILITY_MONITOR_PID=$!
}

stop_availability_monitor() {
  touch "$AVAILABILITY_STOP_FILE"
  wait "$AVAILABILITY_MONITOR_PID"

  local probes
  local outages
  read -r probes outages < "$AVAILABILITY_SUMMARY_FILE"

  echo "Availability probes: $probes"
  echo "Client-visible read outages: $outages"

  if [ -s "$AVAILABILITY_LOG_FILE" ]; then
    cat "$AVAILABILITY_LOG_FILE"
  fi

  rm -f \
    "$AVAILABILITY_STOP_FILE" \
    "$AVAILABILITY_SUMMARY_FILE" \
    "$AVAILABILITY_LOG_FILE"

  [ "$outages" -eq 0 ]
}
