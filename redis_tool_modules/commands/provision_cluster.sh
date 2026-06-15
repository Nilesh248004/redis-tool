# Purpose: implement Phase 1, which provisions the base six-node Redis Cluster.
provision() {
  VERSION="7.0.15"
  MASTERS="3"
  REPLICAS_PER_MASTER="1"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --version)
        VERSION="$2"
        shift 2
        ;;
      --masters)
        MASTERS="$2"
        shift 2
        ;;
      --replicas-per-master)
        REPLICAS_PER_MASTER="$2"
        shift 2
        ;;
      *)
        echo "[ERROR] Unknown option: $1"
        exit 1
        ;;
    esac
  done

  if [ "$MASTERS" != "3" ] || [ "$REPLICAS_PER_MASTER" != "1" ]; then
    echo "[ERROR] This six-node topology requires --masters 3 --replicas-per-master 1."
    exit 1
  fi

  if healthy_existing_cluster; then
    collect_required_node_versions

    {
      echo "===== Redis Cluster Provision Started ====="
      date
      echo "Redis version requested: $VERSION"
      echo "Masters: $MASTERS"
      echo "Replicas per master: $REPLICAS_PER_MASTER"
      echo ""
      echo "Redis Cluster is already provisioned and healthy."
      echo "Provision is a no-op to preserve the existing cluster and data."
      echo ""
      printf '%s' "$REQUIRED_NODE_VERSION_REPORT"
      echo ""
      echo "Use './redis-tool upgrade --target-version $VERSION --strategy rolling' to change versions safely."
      echo "PROVISION NO-OP - existing healthy cluster was left unchanged"
      echo "===== Redis Cluster Provision Completed ====="
      date
    } | tee "$PROVISION_NOOP_OUTPUT"

    structured_log "INFO" "all" "provision" "skipped" \
      "healthy cluster already exists; requested_version=$VERSION; data_preserved=true"
    return 0
  fi

  if partial_existing_cluster; then
    structured_log "ERROR" "all" "provision" "blocked" \
      "existing cluster is not healthy; destructive reprovision refused"
    echo "[ERROR] Existing Redis Cluster state was detected, but it is not healthy."
    echo "Provisioning was stopped to avoid data loss. Repair or remove the existing cluster explicitly."
    return 1
  fi

  echo "Provisioning Redis Cluster..."
  echo "Version: $VERSION"
  echo "Masters: $MASTERS"
  echo "Replicas per master: $REPLICAS_PER_MASTER"

  {
    echo "===== Redis Cluster Provision Started ====="
    date
    echo "Redis version: $VERSION"
    echo "Masters: $MASTERS"
    echo "Replicas per master: $REPLICAS_PER_MASTER"
    echo ""
    echo "===== Running Provision Playbook ====="
    ansible-playbook -i "$INVENTORY" ansible/playbooks/provision.yml -e redis_version="$VERSION"
    echo ""
    echo "===== Final Cluster Info ====="
    ansible -i "$INVENTORY" redis-node-1 -m shell -a "redis-cli -h 10.10.0.11 -p 6379 cluster info"
    echo ""
    echo "===== Final Cluster Nodes ====="
    ansible -i "$INVENTORY" redis-node-1 -m shell -a "redis-cli -h 10.10.0.11 -p 6379 cluster nodes"
    echo ""
    echo "===== Redis Cluster Provision Completed ====="
    date
  } | tee "$PROVISION_OUTPUT"
}
