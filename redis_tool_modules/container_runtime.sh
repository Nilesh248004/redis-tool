# Purpose: provide reusable Docker/Podman commands used by the other modules.

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
