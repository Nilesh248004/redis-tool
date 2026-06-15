# Purpose: confirm Redis data remains readable while a rolling upgrade runs.

monitor_cluster_availability() {
  local stop_file="$1"
  local summary_file="$2"
  local log_file="$3"
  local probes=0
  local outages=0

  while [ ! -f "$stop_file" ]; do
    probes=$((probes + 1))
    local available=0

    for node in "${REQUIRED_PROVISION_NODES[@]}"; do
      local value
      value=$(container_exec_root "$node" redis-cli -c -h 127.0.0.1 -p 6379 GET user:1 2>/dev/null || true)

      if [ "$value" = "value-1" ]; then
        available=1
        break
      fi
    done

    if [ "$available" -eq 0 ]; then
      outages=$((outages + 1))
      printf '%s Cluster read failed across all six nodes\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" >> "$log_file"
    fi

    sleep 0.5
  done

  printf '%s %s\n' "$probes" "$outages" > "$summary_file"
}

start_availability_monitor() {
  AVAILABILITY_SUMMARY_FILE=$(mktemp /tmp/redis-upgrade-availability.XXXXXX)
  AVAILABILITY_STOP_FILE="${AVAILABILITY_SUMMARY_FILE}.stop"
  AVAILABILITY_LOG_FILE="${AVAILABILITY_SUMMARY_FILE}.log"

  monitor_cluster_availability \
    "$AVAILABILITY_STOP_FILE" \
    "$AVAILABILITY_SUMMARY_FILE" \
    "$AVAILABILITY_LOG_FILE" &
  AVAILABILITY_MONITOR_PID=$!
}

stop_availability_monitor() {
  touch "$AVAILABILITY_STOP_FILE"
  wait "$AVAILABILITY_MONITOR_PID"

  local probes
  local outages
  read -r probes outages < "$AVAILABILITY_SUMMARY_FILE"

  echo "Availability probes: $probes"
  echo "Client-visible read outages: $outages"

  if [ -s "$AVAILABILITY_LOG_FILE" ]; then
    cat "$AVAILABILITY_LOG_FILE"
  fi

  rm -f \
    "$AVAILABILITY_STOP_FILE" \
    "$AVAILABILITY_SUMMARY_FILE" \
    "$AVAILABILITY_LOG_FILE"

  [ "$outages" -eq 0 ]
}
