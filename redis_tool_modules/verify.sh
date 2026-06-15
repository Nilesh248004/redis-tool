#!/bin/bash

# Verification script for the Redis Cluster Tool.
#
# When sourced by redis-tool, this file provides the `verify --full` command.
# When executed directly, it checks the repository files, required tools,
# shell syntax, Docker Compose configuration, and Ansible playbook syntax.
verify_command() {
  local option="${1:-}"

  if [ "$option" != "--full" ] || [ "$#" -ne 1 ]; then
    echo "Usage:"
    echo "  ./redis-tool verify --full"
    exit 1
  fi

  require_healthy_cluster "Full verification"

  echo "Running full Redis Cluster verification..."
  {
    echo "===== Redis Full Verification Started ====="
    date
    ansible-playbook -i "$INVENTORY" ansible/playbooks/verify_full.yml
    echo "===== Redis Full Verification Completed ====="
    date
  } | tee "$FULL_VERIFY_OUTPUT"
}

verify_repository() {
set -o pipefail

# verify.sh is inside redis_tool_modules, so the project root is one level up.
MODULES_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd -- "$MODULES_DIR/.." && pwd)
VERIFY_TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/redis-tool-verify.XXXXXX")
export ANSIBLE_LOCAL_TEMP="$VERIFY_TEMP_DIR/ansible"
mkdir -p "$ANSIBLE_LOCAL_TEMP"
trap 'rm -rf "$VERIFY_TEMP_DIR"' EXIT

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

passed=0
failed=0

print_pass() {
  printf "${GREEN}[OK]${NC} %s\n" "$1"
  passed=$((passed + 1))
}

print_fail() {
  printf "${RED}[FAIL]${NC} %s\n" "$1"
  failed=$((failed + 1))
}

print_warning() {
  printf "${YELLOW}[WARN]${NC} %s\n" "$1"
  failed=$((failed + 1))
}

check_file() {
  local file="$1"
  local description="$2"

  if [ -f "$file" ]; then
    print_pass "$description"
  else
    print_fail "$description (missing: $file)"
  fi
}

check_directory() {
  local directory="$1"
  local description="$2"

  if [ -d "$directory" ]; then
    print_pass "$description"
  else
    print_fail "$description (missing: $directory)"
  fi
}

check_executable() {
  local file="$1"
  local description="$2"

  if [ -x "$file" ]; then
    print_pass "$description"
  else
    print_fail "$description (not executable: $file)"
  fi
}

check_command() {
  local command_name="$1"
  local description="$2"
  shift 2

  if command -v "$command_name" >/dev/null 2>&1; then
    local version=""

    if [ "$#" -gt 0 ]; then
      local version_output

      if ! version_output=$("$command_name" "$@" 2>&1); then
        print_fail "$description (${version_output%%$'\n'*})"
        return
      fi

      version=${version_output%%$'\n'*}
    fi

    if [ -n "$version" ]; then
      print_pass "$description ($version)"
    else
      print_pass "$description"
    fi
  else
    print_warning "$description (not installed)"
  fi
}

check_container_runtime() {
  if command -v podman >/dev/null 2>&1; then
    check_command podman "Podman" --version

    if podman compose version >/dev/null 2>&1; then
      print_pass "Podman Compose"
    else
      print_fail "Podman Compose (not available)"
    fi
  elif command -v docker >/dev/null 2>&1; then
    check_command docker "Docker" --version

    if docker compose version >/dev/null 2>&1; then
      print_pass "Docker Compose plugin"
    else
      print_fail "Docker Compose plugin (not available)"
    fi
  else
    print_fail "Container runtime (Docker or Podman is required)"
  fi
}

check_bash_syntax() {
  local file="$1"
  local relative_file="${file#"$PROJECT_ROOT"/}"

  if bash -n "$file"; then
    print_pass "Bash syntax: $relative_file"
  else
    print_fail "Bash syntax: $relative_file"
  fi
}

check_configuration_load() {
  if (
    set -u
    source "$PROJECT_ROOT/redis_tool_modules/prerequisite.sh"
    : "$INVENTORY" "$OUTPUT_DIR" "$LOG_DIR" "$SSH_KEY" "$SSH_PUBLIC_KEY" "$INFRA_PUBLIC_KEY_COPY"
  ); then
    print_pass "Configuration module loads without runtime errors"
  else
    print_fail "Configuration module loads without runtime errors"
  fi
}

check_compose_configuration() {
  if command -v podman >/dev/null 2>&1; then
    if podman compose -f "$PROJECT_ROOT/infra/compose.yml" config >/dev/null 2>&1; then
      print_pass "Compose configuration is valid"
    else
      print_fail "Compose configuration is valid"
    fi
  elif command -v docker >/dev/null 2>&1; then
    if docker compose -f "$PROJECT_ROOT/infra/compose.yml" config --quiet; then
      print_pass "Compose configuration is valid"
    else
      print_fail "Compose configuration is valid"
    fi
  else
    print_fail "Compose configuration validation (no container runtime found)"
  fi
}

check_ansible_syntax() {
  local playbook="$1"
  local relative_playbook="${playbook#"$PROJECT_ROOT"/}"
  local syntax_output

  if syntax_output=$(
    cd "$PROJECT_ROOT/ansible" &&
      ANSIBLE_CONFIG="$PROJECT_ROOT/ansible/ansible.cfg" \
        ansible-playbook --syntax-check "${playbook#"$PROJECT_ROOT/ansible/"}" 2>&1
  ); then
    print_pass "Ansible syntax: $relative_playbook"
  else
    print_fail "Ansible syntax: $relative_playbook"
    printf '%s\n' "$syntax_output"
  fi
}

check_module_layout() {
  local expected
  local actual

  expected=$(
    printf '%s\n' \
      provision.sh \
      status_check.sh \
      logs.sh \
      upgrade.sh \
      verify.sh \
      health.sh \
      rollback.sh \
      inventory.sh \
      scale_out.sh |
      sort
  )
  actual=$(find "$MODULES_DIR" -maxdepth 1 -type f -name '*.sh' -exec basename {} \; | sort)

  if [ "$actual" = "$expected" ]; then
    print_pass "Module folder contains exactly the required ten Bash files"
  else
    print_fail "Module folder must contain only the required ten Bash files"
    printf 'Expected:\n%s\nActual:\n%s\n' "$expected" "$actual"
  fi
}

echo "Redis Cluster Tool - Verification"
echo "================================="
echo

echo "Checking project directories..."
check_directory "$PROJECT_ROOT/ansible" "Ansible directory"
check_directory "$PROJECT_ROOT/ansible/inventory" "Ansible inventory directory"
check_directory "$PROJECT_ROOT/ansible/playbooks" "Ansible playbooks directory"
check_directory "$PROJECT_ROOT/infra" "Infrastructure directory"
check_directory "$PROJECT_ROOT/redis_tool_modules" "Redis tool modules directory"
check_directory "$PROJECT_ROOT/output" "Command output directory"
check_directory "$PROJECT_ROOT/logs" "Operation logs directory"

echo
echo "Checking core project files..."
check_file "$PROJECT_ROOT/redis-tool" "redis-tool CLI"
check_executable "$PROJECT_ROOT/redis-tool" "redis-tool executable permission"
check_file "$MODULES_DIR/verify.sh" "Verification module"
check_executable "$MODULES_DIR/verify.sh" "Verification module executable permission"
check_file "$PROJECT_ROOT/README.md" "README documentation"
check_file "$PROJECT_ROOT/.gitignore" "Git ignore configuration"
check_file "$PROJECT_ROOT/infra/compose.yml" "Docker Compose configuration"
check_file "$PROJECT_ROOT/infra/Dockerfile" "Container image definition"
check_file "$PROJECT_ROOT/ansible/ansible.cfg" "Ansible configuration"
check_file "$PROJECT_ROOT/ansible/inventory/hosts.ini" "Ansible inventory"
check_module_layout

echo
echo "Checking required output evidence..."
check_file "$PROJECT_ROOT/output/provision_output.txt" "Provision output"
check_file "$PROJECT_ROOT/output/data_seed_output.txt" "Data seed output"
check_file "$PROJECT_ROOT/output/status_output.txt" "Status output"
check_file "$PROJECT_ROOT/output/upgrade_output.txt" "Upgrade output"
check_file "$PROJECT_ROOT/output/verify_output.txt" "Data verification output"
check_file "$PROJECT_ROOT/output/full_verify_output.txt" "Full verification output"
check_file "$PROJECT_ROOT/output/scale_out_output.txt" "Scale-out output"
check_file "$PROJECT_ROOT/output/rollback_output.txt" "Rollback output"
check_file "$PROJECT_ROOT/logs/.gitkeep" "Logs directory placeholder"

echo
echo "Checking redis-tool modules..."
check_file "$PROJECT_ROOT/redis_tool_modules/provision.sh" "Provision command"
check_file "$PROJECT_ROOT/redis_tool_modules/status_check.sh" "Status command"
check_file "$PROJECT_ROOT/redis_tool_modules/logs.sh" "Operation logging module"
check_file "$PROJECT_ROOT/redis_tool_modules/upgrade.sh" "Upgrade command"
check_file "$PROJECT_ROOT/redis_tool_modules/verify.sh" "Verification module"
check_file "$PROJECT_ROOT/redis_tool_modules/health.sh" "Cluster health module"
check_file "$PROJECT_ROOT/redis_tool_modules/rollback.sh" "Rollback command"
check_file "$PROJECT_ROOT/redis_tool_modules/inventory.sh" "Ansible inventory module"
check_file "$PROJECT_ROOT/redis_tool_modules/scale_out.sh" "Scale-out command"

echo
echo "Checking Ansible playbooks..."
check_file "$PROJECT_ROOT/ansible/playbooks/provision.yml" "Provision playbook"
check_file "$PROJECT_ROOT/ansible/playbooks/install_redis.yml" "Redis installation playbook"
check_file "$PROJECT_ROOT/ansible/playbooks/configure_redis.yml" "Redis configuration playbook"
check_file "$PROJECT_ROOT/ansible/playbooks/create_cluster.yml" "Cluster creation playbook"
check_file "$PROJECT_ROOT/ansible/playbooks/data_seed.yml" "Data seed playbook"
check_file "$PROJECT_ROOT/ansible/playbooks/data_verify.yml" "Data verification playbook"
check_file "$PROJECT_ROOT/ansible/playbooks/status.yml" "Status playbook"
check_file "$PROJECT_ROOT/ansible/playbooks/upgrade.yml" "Rolling upgrade playbook"
check_file "$PROJECT_ROOT/ansible/playbooks/verify_full.yml" "Full verification playbook"
check_file "$PROJECT_ROOT/ansible/playbooks/scale_out.yml" "Scale-out playbook"
check_file "$PROJECT_ROOT/ansible/playbooks/rollback.yml" "Rollback playbook"
check_file "$PROJECT_ROOT/ansible/playbooks/tasks/rollback_node.yml" "Rollback node task file"

echo
echo "Checking required local tools..."
check_container_runtime
check_command ansible-playbook "Ansible Playbook" --version
check_command ansible "Ansible CLI" --version
check_command nc "Netcat"
check_command ssh "SSH client" -V
check_command ssh-keygen "SSH key generator"
check_command awk "awk"
check_command grep "grep"
check_command sort "sort"
check_command tee "tee"
check_command mktemp "mktemp"

echo
echo "Checking Bash syntax..."
check_bash_syntax "$PROJECT_ROOT/redis-tool"

while IFS= read -r module; do
  check_bash_syntax "$module"
done < <(find "$PROJECT_ROOT/redis_tool_modules" -type f -name '*.sh' | sort)

check_configuration_load

echo
echo "Checking configuration syntax..."
check_compose_configuration

if command -v ansible-playbook >/dev/null 2>&1; then
  while IFS= read -r playbook; do
    check_ansible_syntax "$playbook"
  done < <(find "$PROJECT_ROOT/ansible/playbooks" -maxdepth 1 -type f -name '*.yml' | sort)
else
  print_fail "Ansible playbook syntax checks (ansible-playbook is not installed)"
fi

echo
echo "================================="
printf "Summary: ${GREEN}%d passed${NC}, ${RED}%d failed/warnings${NC}\n" "$passed" "$failed"
echo

if [ "$failed" -eq 0 ]; then
  printf "${GREEN}All checks passed. The project is ready to use.${NC}\n"
  echo
  echo "Next command:"
  echo "  ./redis-tool provision --version 7.0.15 --masters 3 --replicas-per-master 1"
  exit 0
fi

printf "${YELLOW}Some checks failed. Review the messages above before running redis-tool.${NC}\n"
echo
echo "Common installation commands:"
echo "  macOS:          brew install ansible netcat"
echo "  Ubuntu/Debian:  sudo apt-get install ansible netcat-openbsd openssh-client"
echo "  Docker:         https://docs.docker.com/engine/install/"
echo "  Podman:         https://podman.io/docs/installation"
exit 1
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  verify_repository
fi
