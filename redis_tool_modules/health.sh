# Purpose: discover Redis nodes and check cluster health, membership, and versions.
node_name_for_ip() {
  case "$1" in
    10.10.0.11) echo "redis-node-1" ;;
    10.10.0.12) echo "redis-node-2" ;;
    10.10.0.13) echo "redis-node-3" ;;
    10.10.0.14) echo "redis-node-4" ;;
    10.10.0.15) echo "redis-node-5" ;;
    10.10.0.16) echo "redis-node-6" ;;
    10.10.0.17) echo "redis-node-7" ;;
    10.10.0.18) echo "redis-node-8" ;;
    *) echo "$1" ;;
  esac
}

cluster_info_raw() {
  runtime_exec redis-node-1 redis-cli -h 10.10.0.11 -p 6379 cluster info 2>/dev/null
}

cluster_nodes_raw() {
  runtime_exec redis-node-1 redis-cli -h 10.10.0.11 -p 6379 cluster nodes 2>/dev/null
}

log_live_cluster_nodes() {
  local cluster_nodes
  local ip
  local node

  is_container_running redis-node-1 || return 0
  cluster_nodes=$(cluster_nodes_raw) || return 0

  while read -r ip; do
    [ -n "$ip" ] || continue
    node=$(node_name_for_ip "$ip")
    structured_log "INFO" "$node" "cluster_discovery" "reachable" "address=$ip:6379"
  done < <(
    printf '%s\n' "$cluster_nodes" |
      awk '$3 !~ /fail/ {split($2,address,"@"); split(address[1],endpoint,":"); print endpoint[1]}' |
      sort -u
  )
}

healthy_existing_cluster() {
  local cluster_info
  local cluster_nodes
  local ip

  is_container_running redis-node-1 || return 1
  cluster_info=$(cluster_info_raw) || return 1
  cluster_nodes=$(cluster_nodes_raw) || return 1

  printf '%s\n' "$cluster_info" | grep -q '^cluster_state:ok' || return 1

  for ip in 10.10.0.11 10.10.0.12 10.10.0.13 10.10.0.14 10.10.0.15 10.10.0.16; do
    printf '%s\n' "$cluster_nodes" | grep -q "[[:space:]]$ip:6379@" || return 1
    [ "$(runtime_exec redis-node-1 redis-cli -h "$ip" -p 6379 ping 2>/dev/null)" = "PONG" ] ||
      return 1
  done
}

partial_existing_cluster() {
  local cluster_info
  local known_nodes

  is_container_running redis-node-1 || return 1
  cluster_info=$(cluster_info_raw) || return 1
  known_nodes=$(printf '%s\n' "$cluster_info" | awk -F: '/^cluster_known_nodes:/ {gsub("\r", "", $2); print $2}')

  [ "${known_nodes:-0}" -gt 1 ]
}

collect_required_node_versions() {
  local ip
  local node
  local version

  REQUIRED_NODE_VERSION_REPORT=""

  for ip in 10.10.0.11 10.10.0.12 10.10.0.13 10.10.0.14 10.10.0.15 10.10.0.16; do
    node=$(node_name_for_ip "$ip")
    version=$(
      runtime_exec redis-node-1 redis-cli -h "$ip" -p 6379 info server 2>/dev/null |
        awk -F: '/^redis_version:/ {gsub("\r", "", $2); print $2}'
    )
    REQUIRED_NODE_VERSION_REPORT+="$node $ip Redis ${version:-unknown}"$'\n'
  done
}

all_cluster_nodes_at_version() {
  local target_version="$1"
  local cluster_nodes
  local ip
  local node
  local version
  local mismatches=0

  CLUSTER_VERSION_REPORT=""
  cluster_nodes=$(cluster_nodes_raw) || return 1

  while read -r ip; do
    [ -n "$ip" ] || continue
    node=$(node_name_for_ip "$ip")
    version=$(
      runtime_exec redis-node-1 redis-cli -h "$ip" -p 6379 info server 2>/dev/null |
        awk -F: '/^redis_version:/ {gsub("\r", "", $2); print $2}'
    )

    CLUSTER_VERSION_REPORT+="$node $ip Redis ${version:-unknown}"$'\n'

    if [ "$version" = "$target_version" ]; then
      structured_log "INFO" "$node" "version_check" "already_target" \
        "current=$version target=$target_version"
    else
      structured_log "INFO" "$node" "version_check" "target_change_required" \
        "current=${version:-unknown} target=$target_version"
      mismatches=$((mismatches + 1))
    fi
  done < <(
    printf '%s\n' "$cluster_nodes" |
      awk '$3 !~ /fail/ {split($2,address,"@"); split(address[1],endpoint,":"); print endpoint[1]}' |
      sort -u
  )

  [ "$mismatches" -eq 0 ]
}

cluster_has_node_ip() {
  local internal_ip="$1"

  container_exec_root redis-node-1 \
    redis-cli -h 10.10.0.11 -p 6379 cluster nodes |
    grep -q "${internal_ip}:6379"
}

require_healthy_cluster() {
  local operation="$1"

  if healthy_existing_cluster; then
    return 0
  fi

  structured_log "ERROR" "all" "cluster_health" "blocked" \
    "operation=$operation requires healthy base cluster"
  echo "[ERROR] $operation requires a healthy Redis Cluster with all six base nodes reachable."
  return 1
}
