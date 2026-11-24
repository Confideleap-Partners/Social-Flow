#!/usr/bin/env bash
# Checks that Traefik, on this server, routes the app's public host to a live app. The container health check cannot see this:
# a rejected router (wrong entry point, wrong network) leaves the app healthy but the host answering Traefik's own 404.
#
#   verify-route.sh <domain> [port=443] [address=127.0.0.1] [tries=24] [seconds-between=5]
#
# Requests https://<domain>/ with the right host name and TLS name but straight to this server, so DNS and any CDN in front are out
# of the picture. Success is any answer other than "no route" (404) or "no healthy backend" (502/503/504): a login redirect is fine.
# Exits 1 after the last try. It never changes anything, and a failure here does not roll the deploy back (the app is healthy).
set -uo pipefail

DOMAIN=${1:?usage: verify-route.sh <domain> [port] [address] [tries] [seconds-between]}
PORT=${2:-443}
ADDRESS=${3:-127.0.0.1}
TRIES=${4:-24}
PAUSE=${5:-5}

code=000
for i in $(seq 1 "$TRIES"); do
  code=$(curl -sk -o /dev/null -w '%{http_code}' --max-time 5 --resolve "${DOMAIN}:${PORT}:${ADDRESS}" "https://${DOMAIN}:${PORT}/" || true)
  case "$code" in
    000 | 404 | 502 | 503 | 504) echo "Attempt $i/$TRIES: https://$DOMAIN answered HTTP $code" ;;
    *) echo "Public route OK: https://$DOMAIN -> HTTP $code (through Traefik on this server)"; exit 0 ;;
  esac
  [ "$i" -lt "$TRIES" ] && sleep "$PAUSE"
done

echo "ERROR: Traefik does not route https://$DOMAIN to the app (last answer HTTP $code). The app itself is healthy." >&2
echo "Usual causes: the router's entry point does not exist in Traefik's config (set TRAEFIK_ENTRYPOINT), or Traefik is not on the" >&2
echo "network the app is attached to for routing (set TRAEFIK_NETWORK)." >&2
exit 1
