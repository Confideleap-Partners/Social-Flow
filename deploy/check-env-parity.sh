#!/usr/bin/env bash
# During the first cutover from the hand-started `postiz` container to the CI-built app: make sure nothing the old container was
# configured with is missing from the new env file, so no provider, storage or webhook setting is silently dropped.
#
#   check-env-parity.sh <env-file> <deploy-env>
#
# Prints only setting NAMES (never values), except the four public URLs, which are not secret.
# Exits 1 when a setting that has a value in the old container is missing or empty in the env file.
# Does nothing unless the old `postiz` container exists and no compose app container does yet (that is the cutover run).
# Settings you have dropped on purpose: set ENV_PARITY_IGNORE="NAME1 NAME2" in the env file (Infisical).
set -euo pipefail

ENV_FILE=${1:?usage: check-env-parity.sh <env-file> <deploy-env>}
DEPLOY_ENV=${2:?usage: check-env-parity.sh <env-file> <deploy-env>}

docker container inspect postiz >/dev/null 2>&1 || exit 0
[ -z "$(docker ps -aq --filter "label=com.docker.compose.project=social-flow-${DEPLOY_ENV}" --filter "label=com.docker.compose.service=app")" ] || exit 0

# A missing key is not an error: it yields an empty string (grep finding nothing must not trip `set -e` through pipefail).
get_value() { { grep -E "^$1=" "$ENV_FILE" || true; } | tail -1 | cut -d= -f2-; }
# Names of the old container's settings that have a value. Docker hands over one entry per setting, so a multi-line value (a private
# key) stays one entry and cannot produce bogus names. Values are never printed.
old_keys() { docker inspect -f '{{range .Config.Env}}{{$k := index (split . "=") 0}}{{if ne . (printf "%s=" $k)}}{{$k}}{{println}}{{end}}{{end}}' postiz | grep -E '^[A-Za-z_][A-Za-z0-9_]*$' | sort -u; }
# One setting's value (only used for the four public URLs, which are single-line and not secret).
old_value() { docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' postiz | { grep -E "^$1=" || true; } | head -1 | cut -d= -f2-; }

# Set by the compose file itself, so they never come from the env file.
set_by_compose=" NODE_ENV DATABASE_URL REDIS_URL TEMPORAL_ADDRESS UPLOAD_DIRECTORY NEXT_PUBLIC_UPLOAD_DIRECTORY MAIN_URL FRONTEND_URL NEXT_PUBLIC_BACKEND_URL BACKEND_INTERNAL_URL IS_GENERAL DISABLE_REGISTRATION API_LIMIT FEE_AMOUNT NX_ADD_PLUGINS "
ignored=" $(get_value ENV_PARITY_IGNORE) "
# Whatever the old container's image defines on its own (PATH, NODE_VERSION, ...) is not configuration and comes with any build.
image_defined=" $(docker image inspect -f '{{range .Config.Env}}{{index (split . "=") 0}}{{" "}}{{end}}' "$(docker inspect -f '{{.Image}}' postiz)") "

missing=""
while IFS= read -r key; do
  case "$set_by_compose$ignored$image_defined" in *" $key "*) continue ;; esac
  grep -qE "^${key}=.+" "$ENV_FILE" || missing="$missing $key"
done < <(old_keys)

# The public URLs: not secret, and the one place a change breaks OAuth callbacks, so show old and new.
domain=$(get_value APP_DOMAIN)
new_url() {
  case "$1" in
    MAIN_URL | FRONTEND_URL) echo "https://${domain}" ;;
    NEXT_PUBLIC_BACKEND_URL) echo "https://${domain}/api" ;;
    BACKEND_INTERNAL_URL) echo "$(get_value BACKEND_INTERNAL_URL)" | sed 's/^$/http:\/\/127.0.0.1:3000/' ;;
  esac
}
for key in MAIN_URL FRONTEND_URL NEXT_PUBLIC_BACKEND_URL BACKEND_INTERNAL_URL; do
  old=$(old_value "$key")
  new=$(new_url "$key")
  [ -z "$old" ] || [ "$old" = "$new" ] || echo "NOTICE: $key changes from $old to $new"
done

if [ -n "$missing" ]; then
  echo "ERROR: these settings have a value in the running postiz container but are missing or empty in the new env file:" >&2
  for key in $missing; do echo "  - $key" >&2; done
  echo "Add them to Infisical ($DEPLOY_ENV) with the same values, or list intentionally dropped ones in ENV_PARITY_IGNORE." >&2
  exit 1
fi
echo "Settings check passed: nothing the running postiz container has is missing."
