# Purpose: set up project-wide configuration variables and paths.

# Resolve the project root relative to this module's location.
MODULES_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
BASE_DIR=$(cd -- "$MODULES_DIR/.." && pwd)

# Core configuration paths
export INVENTORY="$BASE_DIR/ansible/inventory/hosts.ini"
export OUTPUT_DIR="$BASE_DIR/output"
export LOG_DIR="$BASE_DIR/logs"

# SSH key paths for Ansible authentication
export SSH_KEY="${HOME}/.ssh/redis_cluster_key"
export SSH_PUBLIC_KEY="${SSH_KEY}.pub"
export INFRA_PUBLIC_KEY_COPY="$BASE_DIR/infra/redis_cluster_key.pub"

# Output file paths for command operations
export PROVISION_OUTPUT="$OUTPUT_DIR/provision_output.txt"
export DATA_SEED_OUTPUT="$OUTPUT_DIR/data_seed_output.txt"
export STATUS_OUTPUT="$OUTPUT_DIR/status_output.txt"
export UPGRADE_OUTPUT="$OUTPUT_DIR/upgrade_output.txt"
export VERIFY_OUTPUT="$OUTPUT_DIR/verify_output.txt"
export FULL_VERIFY_OUTPUT="$OUTPUT_DIR/full_verify_output.txt"
export SCALE_OUT_OUTPUT="$OUTPUT_DIR/scale_out_output.txt"
export ROLLBACK_OUTPUT="$OUTPUT_DIR/rollback_output.txt"

# Temporary files tracking (cleared at end of each operation)
TEMP_FILES=()

# Infrastructure configuration
export COMPOSE_FILE="$BASE_DIR/infra/compose.yml"
export REQUIRED_PROVISION_NODES=(redis-node-1 redis-node-2 redis-node-3 redis-node-4 redis-node-5 redis-node-6)
export REQUIRED_SSH_PORTS=(2211 2212 2213 2214 2215 2216)
export SCALE_OUT_NODES=(redis-node-7 redis-node-8)
export SCALE_OUT_SSH_PORTS=(2217 2218)

# Helper functions for container and infrastructure interactions
require_healthy_cluster() {
  local context="${1:-command}"
  
  if ! healthy_existing_cluster; then
    echo "[ERROR] $context requires a healthy Redis Cluster. Provision a cluster first."
    exit 1
  fi
}

is_container_running() {
  local container="$1"
  
  if command -v podman >/dev/null 2>&1; then
    podman ps --format "{{.Names}}" | grep -q "^${container}$"
  elif command -v docker >/dev/null 2>&1; then
    docker ps --format "{{.Names}}" | grep -q "^${container}$"
  else
    return 1
  fi
}

runtime_exec() {
  local container="$1"
  shift
  
  if ! is_container_running "$container"; then
    return 1
  fi
  
  if command -v podman >/dev/null 2>&1; then
    podman exec "$container" "$@"
  elif command -v docker >/dev/null 2>&1; then
    docker exec "$container" "$@"
  else
    return 1
  fi
}

ensure_infra_running() {
  if is_container_running redis-node-1; then
    return 0
  fi
  
  echo "Starting Redis Cluster infrastructure..."
  
  if command -v podman >/dev/null 2>&1; then
    podman compose -f "$BASE_DIR/infra/compose.yml" up -d
  elif command -v docker >/dev/null 2>&1; then
    docker compose -f "$BASE_DIR/infra/compose.yml" up -d
  else
    echo "[ERROR] No container runtime (Docker or Podman) found."
    exit 1
  fi
  
  sleep 3
}

validate_redis_version() {
  local version="$1"
  
  if ! [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "[ERROR] Invalid Redis version format: $version (expected: X.Y.Z)"
    exit 1
  fi
}

require_option_value() {
  local option="$1"
  local value="$2"
  
  if [ -z "$value" ]; then
    echo "[ERROR] Option $option requires a value"
    exit 1
  fi
}

compose_cmd() {
  if command -v podman >/dev/null 2>&1; then
    podman compose -f "$COMPOSE_FILE" "$@"
  elif command -v docker >/dev/null 2>&1; then
    docker compose -f "$COMPOSE_FILE" "$@"
  else
    echo "[ERROR] No container runtime (Docker or Podman) found."
    return 1
  fi
}

container_exec_root() {
  local container="$1"
  shift
  
  if ! is_container_running "$container"; then
    echo "[ERROR] Container $container is not running."
    return 1
  fi
  
  if command -v podman >/dev/null 2>&1; then
    podman exec -u root "$container" "$@"
  elif command -v docker >/dev/null 2>&1; then
    docker exec -u root "$container" "$@"
  else
    return 1
  fi
}

check_prerequisites() {
  # Check for container runtime (Docker or Podman)
  if command -v podman >/dev/null 2>&1; then
    RUNTIME_VERSION=$(podman --version 2>/dev/null | head -1)
  elif command -v docker >/dev/null 2>&1; then
    RUNTIME_VERSION=$(docker --version 2>/dev/null | head -1)
  else
    echo "[ERROR] Neither Docker nor Podman is installed. Install one to continue."
    exit 1
  fi
  
  # Check for Ansible
  if ! command -v ansible-playbook >/dev/null 2>&1; then
    echo "[ERROR] Ansible is not installed. Install it to continue."
    exit 1
  fi
  
  ANSIBLE_VERSION=$(ansible-playbook --version 2>/dev/null | head -1)
  
  # Export the version variables for logging
  export RUNTIME_VERSION
  export ANSIBLE_VERSION
}

inspect_container_image() {
  local container="$1"
  
  if command -v podman >/dev/null 2>&1; then
    podman inspect "$container" --format='{{.Config.Image}}' 2>/dev/null || true
  elif command -v docker >/dev/null 2>&1; then
    docker inspect "$container" --format='{{.Config.Image}}' 2>/dev/null || true
  fi
}

inspect_container_network() {
  local container="$1"
  
  if command -v podman >/dev/null 2>&1; then
    podman inspect "$container" --format='{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{end}}' 2>/dev/null || true
  elif command -v docker >/dev/null 2>&1; then
    docker inspect "$container" --format='{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{end}}' 2>/dev/null || true
  fi
}

container_exists() {
  local container="$1"
  
  if command -v podman >/dev/null 2>&1; then
    podman ps -a --format "{{.Names}}" | grep -q "^${container}$"
  elif command -v docker >/dev/null 2>&1; then
    docker ps -a --format "{{.Names}}" | grep -q "^${container}$"
  else
    return 1
  fi
}

remove_container() {
  local container="$1"
  
  if ! container_exists "$container"; then
    return 0
  fi
  
  if command -v podman >/dev/null 2>&1; then
    podman rm -f "$container" >/dev/null 2>&1 || true
  elif command -v docker >/dev/null 2>&1; then
    docker rm -f "$container" >/dev/null 2>&1 || true
  fi
}

tag_scale_out_image() {
  local source_image="$1"
  local node_name="$2"
  
  # Return the base image without additional tagging
  # All scale-out nodes use the same base image
  echo "$source_image"
}

run_scale_out_container() {
  local container="$1"
  local ssh_port="$2"
  local internal_ip="$3"
  local image="$4"
  local network="$5"
  
  if command -v podman >/dev/null 2>&1; then
    podman run -d \
      --name "$container" \
      --network "$network" \
      --ip "$internal_ip" \
      -p "${ssh_port}:22" \
      -e TERM=xterm \
      "$image"
  elif command -v docker >/dev/null 2>&1; then
    docker run -d \
      --name "$container" \
      --network "$network" \
      --ip "$internal_ip" \
      -p "${ssh_port}:22" \
      -e TERM=xterm \
      "$image"
  fi
}
