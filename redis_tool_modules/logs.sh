# Purpose: show command logs, save them to files, and clean temporary files.
structured_log() {
  local level="$1"
  local node="$2"
  local action="$3"
  local outcome="$4"
  local details="${5:-}"

  details=${details//$'\n'/ }
  details=${details//\"/\\\"}

  printf 'timestamp=%s level=%s command=%s node=%s action=%s outcome=%s details="%s"\n' \
    "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
    "$level" \
    "$OPERATION_COMMAND" \
    "$node" \
    "$action" \
    "$outcome" \
    "$details"
}

finish_operation_log() {
  local exit_code=$?
  local outcome="success"
  local level="INFO"
  local details="exit_code=$exit_code"
  local temp_file

  trap - EXIT

  if [ "$exit_code" -eq 130 ]; then
    outcome="interrupted"
    level="WARN"
    details="exit_code=130 signal=SIGINT reason=user_pressed_ctrl_c"
  elif [ "$exit_code" -eq 143 ]; then
    outcome="terminated"
    level="WARN"
    details="exit_code=143 signal=SIGTERM"
  elif [ "$exit_code" -ne 0 ]; then
    outcome="failed"
    level="ERROR"
  fi

  structured_log "$level" "all" "operation" "$outcome" "$details"

  if [ "$exit_code" -eq 130 ]; then
    echo "[WARN] Operation interrupted by Ctrl+C. Run the same command again to resume safely."
  fi

  echo "Structured operation log: $OPERATION_LOG"

  for temp_file in "${TEMP_FILES[@]}"; do
    rm -f "$temp_file"
  done

  exit "$exit_code"
}

initialize_operation_log() {
  local timestamp
  local command_slug

  timestamp=$(date -u '+%Y%m%dT%H%M%SZ')
  OPERATION_COMMAND="${1:-help}"
  mkdir -p "$OUTPUT_DIR" "$LOG_DIR"

  if [ "$OPERATION_COMMAND" = "data" ] && [ -n "${2:-}" ]; then
    OPERATION_COMMAND="data-$2"
  fi

  command_slug=$(printf '%s' "$OPERATION_COMMAND" | tr -cs 'A-Za-z0-9._-' '_')
  OPERATION_LOG="$LOG_DIR/${timestamp}_${command_slug}_$$.log"

  exec > >(tee -a "$OPERATION_LOG") 2>&1
  trap finish_operation_log EXIT

  structured_log "INFO" "all" "operation" "started" "arguments=$*"
  echo "Operation log: $OPERATION_LOG"

  while read -r node; do
    [ -n "$node" ] &&
      structured_log "INFO" "$node" "command_target" "included" "inventory=$INVENTORY"
  done < <(awk '/^redis-node-[0-9]+[[:space:]]/ {print $1}' "$INVENTORY" | sort -u)
}
