# Purpose: store shared settings and provide prerequisite/container runtime functions.
INVENTORY="ansible/inventory/hosts.ini"
OUTPUT_DIR="output"
LOG_DIR="logs"
PROVISION_OUTPUT="$OUTPUT_DIR/provision_output.txt"
DATA_SEED_OUTPUT="$OUTPUT_DIR/data_seed_output.txt"
STATUS_OUTPUT="$OUTPUT_DIR/status_output.txt"
VERIFY_OUTPUT="$OUTPUT_DIR/verify_output.txt"
UPGRADE_OUTPUT="$OUTPUT_DIR/upgrade_output.txt"
FULL_VERIFY_OUTPUT="$OUTPUT_DIR/full_verify_output.txt"
SCALE_OUT_OUTPUT="$OUTPUT_DIR/scale_out_output.txt"
ROLLBACK_OUTPUT="$OUTPUT_DIR/rollback_output.txt"
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

require_option_value() {
  local option="$1"
  local value="$2"

  if [ -z "$value" ] || [[ "$value" == --* ]]; then
    echo "[ERROR] $option requires a value."
    exit 1
  fi
}

validate_redis_version() {
  local version="$1"

  if ! [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "[ERROR] Redis version must use MAJOR.MINOR.PATCH format, for example 7.0.15."
    exit 1
  fi
}

check_prerequisites() {
  echo "Checking prerequisites..."
  MISSING=0

  if command -v podman >/dev/null 2>&1; then
    RUNTIME="podman"
    RUNTIME_VERSION=$(podman --version)
    echo "[OK] $RUNTIME_VERSION found"

    if ! podman compose version >/dev/null 2>&1; then
      echo "[ERROR] Podman Compose is not available."
      echo "Install: pip install podman-compose"
      MISSING=1
    fi
  elif command -v docker >/dev/null 2>&1; then
    RUNTIME="docker"
    RUNTIME_VERSION=$(docker --version)
    echo "[OK] $RUNTIME_VERSION found"

    if ! docker compose version >/dev/null 2>&1; then
      echo "[ERROR] Docker Compose is not available."
      echo "Install the Docker Compose plugin: https://docs.docker.com/compose/install/"
      MISSING=1
    fi
  else
    echo "[ERROR] Container runtime not found. Docker or Podman is required."
    echo "Install Podman: https://podman.io/docs/installation"
    echo "Install Docker: https://docs.docker.com/engine/install/"
    MISSING=1
  fi

  if command -v ansible-playbook >/dev/null 2>&1; then
    ANSIBLE_VERSION=$(ansible-playbook --version | head -n 1 | awk '{print $3}' | tr -d '[]')
    echo "[OK] Ansible $ANSIBLE_VERSION found"

    ANSIBLE_MAJOR=$(echo "$ANSIBLE_VERSION" | cut -d. -f1)
    ANSIBLE_MINOR=$(echo "$ANSIBLE_VERSION" | cut -d. -f2)

    if [ "$ANSIBLE_MAJOR" -gt 2 ] || {
      [ "$ANSIBLE_MAJOR" -eq 2 ] && [ "$ANSIBLE_MINOR" -ge 14 ]
    }; then
      :
    else
      echo "[ERROR] Ansible version must be 2.14 or higher. Found: $ANSIBLE_VERSION"
      echo "Install or upgrade: pip install --upgrade ansible"
      MISSING=1
    fi
  else
    echo "[ERROR] Ansible not found."
    echo "Install: pip install ansible"
    echo "Or use your OS package manager."
    MISSING=1
  fi

  if command -v nc >/dev/null 2>&1; then
    echo "[OK] nc found"
  else
    echo "[ERROR] nc command not found. It is required to check SSH ports."
    echo "On macOS, install using:"
    echo "  brew install netcat"
    MISSING=1
  fi

  if command -v ssh-keygen >/dev/null 2>&1; then
    echo "[OK] ssh-keygen found"
  else
    echo "[ERROR] ssh-keygen not found. Install an OpenSSH client package."
    MISSING=1
  fi

  if [ "$MISSING" -ne 0 ]; then
    echo "Please install the missing dependencies and retry."
    exit 1
  fi

  check_container_runtime_running
  echo "Proceeding..."
}

check_container_runtime_running() {
  echo "Checking container runtime status..."

  if [ "$RUNTIME" = "docker" ]; then
    if ! docker info >/dev/null 2>&1; then
      echo "[ERROR] Docker is installed but Docker Desktop / Docker daemon is not running."
      echo "Please start Docker Desktop and run the command again."
      exit 1
    fi
  elif [ "$RUNTIME" = "podman" ]; then
    if ! podman info >/dev/null 2>&1; then
      echo "[ERROR] Podman is installed but Podman machine is not running."
      echo "Start it using:"
      echo "  podman machine start"
      exit 1
    fi
  fi

  echo "[OK] Container runtime is running"
}

compose_cmd() {
  if [ "$RUNTIME" = "docker" ]; then
    docker compose -f "$COMPOSE_FILE" "$@"
  else
    podman compose -f "$COMPOSE_FILE" "$@"
  fi
}

runtime_exec() {
  local container_name="$1"
  shift

  if [ "$RUNTIME" = "docker" ]; then
    docker exec "$container_name" "$@"
  else
    podman exec "$container_name" "$@"
  fi
}

container_exec_root() {
  local container_name="$1"
  shift

  if [ "$RUNTIME" = "docker" ]; then
    docker exec -u root "$container_name" "$@"
  else
    podman exec -u root "$container_name" "$@"
  fi
}

is_container_running() {
  local container_name="$1"

  if [ "$RUNTIME" = "docker" ]; then
    docker ps --format '{{.Names}}' | grep -qx "$container_name"
  else
    podman ps --format '{{.Names}}' | grep -qx "$container_name"
  fi
}

container_exists() {
  local container_name="$1"

  if [ "$RUNTIME" = "docker" ]; then
    docker ps -a --format '{{.Names}}' | grep -qx "$container_name"
  else
    podman ps -a --format '{{.Names}}' | grep -qx "$container_name"
  fi
}

remove_container() {
  local container_name="$1"

  if [ "$RUNTIME" = "docker" ]; then
    docker rm -f "$container_name"
  else
    podman rm -f "$container_name"
  fi
}

inspect_container_image() {
  local container_name="$1"

  if [ "$RUNTIME" = "docker" ]; then
    docker inspect "$container_name" --format '{{.Config.Image}}'
  else
    podman inspect "$container_name" --format '{{.Config.Image}}'
  fi
}

inspect_container_network() {
  local container_name="$1"

  if [ "$RUNTIME" = "docker" ]; then
    docker inspect "$container_name" \
      --format '{{range $name, $_ := .NetworkSettings.Networks}}{{$name}}{{"\n"}}{{end}}' |
      head -n 1
  else
    podman inspect "$container_name" \
      --format '{{range $name, $_ := .NetworkSettings.Networks}}{{$name}}{{"\n"}}{{end}}' |
      head -n 1
  fi
}

tag_scale_out_image() {
  local source_image="$1"
  local node="$2"
  local target_image

  if [[ "$source_image" == *redis-node-1* ]]; then
    target_image="${source_image/redis-node-1/$node}"
  else
    target_image="$node:latest"
  fi

  if [ "$RUNTIME" = "docker" ]; then
    docker tag "$source_image" "$target_image"
  else
    podman tag "$source_image" "$target_image"
  fi

  printf '%s\n' "$target_image"
}

run_scale_out_container() {
  local node="$1"
  local ssh_port="$2"
  local internal_ip="$3"
  local image="$4"
  local network="$5"

  if [ "$RUNTIME" = "docker" ]; then
    docker run -d \
      --name "$node" \
      --hostname "$node" \
      --label "com.docker.compose.service=$node" \
      --publish "$ssh_port:22" \
      --network "$network" \
      --ip "$internal_ip" \
      "$image"
  else
    podman run -d \
      --name "$node" \
      --hostname "$node" \
      --label "com.docker.compose.service=$node" \
      --publish "$ssh_port:22" \
      --network "$network" \
      --ip "$internal_ip" \
      "$image"
  fi
}
