#!/usr/bin/env bash
# Finds the Docker networks and volumes the running Postiz infrastructure uses and writes them to an env file for deploy/docker-compose.yml.
#
#   discover-infra.sh <env-file> <deploy-env>
#
# It only reads containers; it never starts, stops or changes anything. A value already in the env file wins over discovery, but is still
# checked. If any name cannot be found, or a named network or volume does not exist, it prints why and exits 1, so a deploy stops before
# the app can start against an empty volume or the wrong network.
#
# Where each name comes from:
#   POSTIZ_NETWORK        the network of the postiz-postgres container
#   TEMPORAL_NETWORK      the network of the temporal container
#   POSTIZ_CONFIG_VOLUME  what is mounted at /config  } on the running compose app container if there is one,
#   POSTIZ_UPLOADS_VOLUME what is mounted at /uploads } otherwise on the older hand-started `postiz` container
#   TRAEFIK_NETWORK       the first of POSTIZ_NETWORK / TEMPORAL_NETWORK that the `traefik` container is also attached to, so Traefik
#                         reaches the app over a network the app is already on (nothing new to join, nothing on Traefik to change).
#                         Skipped when there is no `traefik` container. Fails when Traefik shares neither network.
set -euo pipefail

ENV_FILE=${1:?usage: discover-infra.sh <env-file> <deploy-env>}
DEPLOY_ENV=${2:?usage: discover-infra.sh <env-file> <deploy-env>}
touch "$ENV_FILE"
errors=0

fail() { echo "ERROR: $*" >&2; errors=1; }
has_value() { grep -qE "^$1=.+" "$ENV_FILE"; }
get_value() { grep -E "^$1=" "$ENV_FILE" | tail -1 | cut -d= -f2-; }
exists() { docker container inspect "$1" >/dev/null 2>&1; }

# The one non-default network a container is on. Zero or several means we cannot tell which one is meant.
network_of() {
  exists "$1" || return 0
  local nets
  nets=$(docker inspect -f '{{range $k,$v := .NetworkSettings.Networks}}{{println $k}}{{end}}' "$1" | grep -vx -e bridge -e host -e none -e '' || true)
  if [ "$(printf '%s\n' "$nets" | grep -c .)" -eq 1 ]; then printf '%s\n' "$nets"; fi
}

# The named volume mounted at a path inside a container (empty for a bind mount or an unnamed volume).
volume_at() {
  exists "$1" || return 0
  docker inspect -f "{{range .Mounts}}{{if eq .Destination \"$2\"}}{{.Name}}{{end}}{{end}}" "$1"
}

app_container=$(docker ps -aq --filter "label=com.docker.compose.project=social-flow-${DEPLOY_ENV}" --filter "label=com.docker.compose.service=app" | head -1)
volume_source=${app_container:-postiz}

resolve() { # <KEY> <found-value> <what it was found from>
  local key=$1 found=$2 from=$3
  if has_value "$key"; then
    echo "$key=$(get_value "$key") (already set, kept)"
  elif [ -n "$found" ]; then
    printf '%s=%s\n' "$key" "$found" >> "$ENV_FILE"
    echo "$key=$found (found on $from)"
  else
    fail "$key is not set and could not be found on $from. Set $key explicitly, or start the existing infrastructure first."
  fi
}

resolve POSTIZ_NETWORK "$(network_of postiz-postgres)" "container postiz-postgres"
resolve TEMPORAL_NETWORK "$(network_of temporal)" "container temporal"
resolve POSTIZ_CONFIG_VOLUME "$(volume_at "$volume_source" /config)" "container $volume_source at /config"
resolve POSTIZ_UPLOADS_VOLUME "$(volume_at "$volume_source" /uploads)" "container $volume_source at /uploads"

# The network Traefik reaches the app over.
traefik_network() {
  local nets key
  nets=$(docker inspect -f '{{range $k,$v := .NetworkSettings.Networks}}{{println $k}}{{end}}' traefik)
  for key in POSTIZ_NETWORK TEMPORAL_NETWORK; do
    has_value "$key" || continue
    if printf '%s\n' "$nets" | grep -qx "$(get_value "$key")"; then get_value "$key"; return 0; fi
  done
  return 0
}
if has_value TRAEFIK_NETWORK; then
  echo "TRAEFIK_NETWORK=$(get_value TRAEFIK_NETWORK) (already set, kept)"
elif exists traefik; then
  found=$(traefik_network || true)
  if [ -n "$found" ]; then
    printf 'TRAEFIK_NETWORK=%s\n' "$found" >> "$ENV_FILE"
    echo "TRAEFIK_NETWORK=$found (container traefik is attached to it)"
  else
    fail "container traefik is attached to neither $(get_value POSTIZ_NETWORK) nor $(get_value TEMPORAL_NETWORK), so it cannot reach the app. Attach it (docker network connect <network> traefik) or set TRAEFIK_NETWORK to a network both can use."
  fi
else
  echo "No container named traefik here; TRAEFIK_NETWORK not needed"
fi

# Whatever the names came from, the things they name must exist: compose treats them as external and must never create empty ones.
for key in POSTIZ_NETWORK TEMPORAL_NETWORK TRAEFIK_NETWORK; do
  has_value "$key" && { docker network inspect "$(get_value "$key")" >/dev/null 2>&1 || fail "network $(get_value "$key") ($key) does not exist"; }
done
for key in POSTIZ_CONFIG_VOLUME POSTIZ_UPLOADS_VOLUME; do
  has_value "$key" && { docker volume inspect "$(get_value "$key")" >/dev/null 2>&1 || fail "volume $(get_value "$key") ($key) does not exist"; }
done

exit "$errors"
