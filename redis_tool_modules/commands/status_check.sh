# Purpose: implement Phase 3, which displays Redis Cluster health and topology.

status_command() {
  echo "Checking Redis Cluster status..."
  {
    echo "===== Redis Cluster Status Started ====="
    date
    ansible-playbook -i "$INVENTORY" ansible/playbooks/status.yml
    echo "===== Redis Cluster Status Completed ====="
    date
  } | tee "$STATUS_OUTPUT"
}
