# Purpose: store the common paths, output filenames, SSH settings, and node lists.
INVENTORY="ansible/inventory/hosts.ini"
OUTPUT_DIR="output"
LOG_DIR="logs"
PROVISION_OUTPUT="$OUTPUT_DIR/provision_output.txt"
PROVISION_NOOP_OUTPUT="$OUTPUT_DIR/provision_noop_output.txt"
DATA_SEED_OUTPUT="$OUTPUT_DIR/data_seed_output.txt"
STATUS_OUTPUT="$OUTPUT_DIR/status_output.txt"
VERIFY_OUTPUT="$OUTPUT_DIR/verify_output.txt"
UPGRADE_OUTPUT="$OUTPUT_DIR/upgrade_output.txt"
UPGRADE_NOOP_OUTPUT="$OUTPUT_DIR/upgrade_noop_output.txt"
FULL_VERIFY_OUTPUT="$OUTPUT_DIR/full_verify_output.txt"
SCALE_OUT_OUTPUT="$OUTPUT_DIR/scale_out_output.txt"
ROLLBACK_OUTPUT="$OUTPUT_DIR/rollback_output.txt"
ROLLBACK_NOOP_OUTPUT="$OUTPUT_DIR/rollback_noop_output.txt"
COMPOSE_FILE="infra/compose.yml"
SSH_KEY="$HOME/.ssh/redis_cluster_key"
SSH_PUBLIC_KEY="$HOME/.ssh/redis_cluster_key.pub"

REQUIRED_PROVISION_NODES=(
  "redis-node-1"
  "redis-node-2"
  "redis-node-3"
  "redis-node-4"
  "redis-node-5"
  "redis-node-6"
)
REQUIRED_SSH_PORTS=("2211" "2212" "2213" "2214" "2215" "2216")
SCALE_OUT_NODES=("redis-node-7" "redis-node-8")
SCALE_OUT_SSH_PORTS=("2217" "2218")
TEMP_FILES=()
