# Purpose: implement Phase 3, which displays Redis Cluster health and topology.

status_command() {
  echo "Checking Redis Cluster status..."

  local all_running=1
  local node

  for node in "${REQUIRED_PROVISION_NODES[@]}"; do
    if ! is_container_running "$node"; then
      all_running=0
      break
    fi
  done

  if [ "$all_running" -eq 0 ]; then
    echo "[ERROR] Redis containers are not running."
    echo ""
    echo "To start the cluster, run:"
    echo "  ./redis-tool provision --version 7.0.15 --masters 3 --replicas-per-master 1"
    echo ""
    echo "Current container status:"
    compose_cmd ps 2>/dev/null || true
    exit 1
  fi

  {
    echo "===== Redis Cluster Status Started ====="
    date
    ansible-playbook -i "$INVENTORY" ansible/playbooks/status.yml
    echo "===== Redis Cluster Status Completed ====="
    date
  } | tee "$STATUS_OUTPUT"
}
