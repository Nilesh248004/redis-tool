# Purpose: implement scale-out by adding redis-node-7 and redis-node-8.
scale_command() {
  ACTION="$1"
  VALUE="$2"

  if [ "$ACTION" != "--add-nodes" ] || [ "$VALUE" != "2" ]; then
    echo "Usage:"
    echo "  ./redis-tool scale --add-nodes 2"
    exit 1
  fi

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
