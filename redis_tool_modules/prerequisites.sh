# Purpose: check that Docker/Podman, Ansible, netcat, and SSH tools are available.
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
