# Purpose: implement Phase 2, which seeds and verifies deterministic Redis data.

data_command() {
  ACTION="$1"
  shift || true
  KEYS="1000"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --keys)
        KEYS="$2"
        shift 2
        ;;
      *)
        echo "[ERROR] Unknown option: $1"
        exit 1
        ;;
    esac
  done

  case "$ACTION" in
    seed)
      echo "Seeding $KEYS keys into Redis Cluster..."
      {
        echo "===== Redis Data Seed Started ====="
        date
        echo "Keys: $KEYS"
        ansible-playbook -i "$INVENTORY" ansible/playbooks/data_seed.yml -e keys="$KEYS"
        echo "===== Redis Data Seed Completed ====="
        date
      } | tee "$DATA_SEED_OUTPUT"
      ;;
    verify)
      echo "Verifying Redis Cluster data..."
      {
        echo "===== Redis Data Verify Started ====="
        date
        echo "Keys: $KEYS"
        ansible-playbook -i "$INVENTORY" ansible/playbooks/data_verify.yml -e keys="$KEYS"
        echo "===== Redis Data Verify Completed ====="
        date
      } | tee "$VERIFY_OUTPUT"
      ;;
    *)
      echo "Usage:"
      echo "  ./redis-tool data seed --keys 1000"
      echo "  ./redis-tool data verify"
      exit 1
      ;;
  esac
}
