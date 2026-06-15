# Purpose: implement Phase 5, which runs every cluster and data verification check.

verify_command() {
  OPTION="$1"

  if [ "$OPTION" != "--full" ]; then
    echo "Usage:"
    echo "  ./redis-tool verify --full"
    exit 1
  fi

  echo "Running full Redis Cluster verification..."
  {
    echo "===== Redis Full Verification Started ====="
    date
    ansible-playbook -i "$INVENTORY" ansible/playbooks/verify_full.yml
    echo "===== Redis Full Verification Completed ====="
    date
  } | tee "$FULL_VERIFY_OUTPUT"
}
