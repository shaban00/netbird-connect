#!/usr/bin/env bash
# Start the NetBird daemon and register this runner as an ephemeral peer.
set -euo pipefail

: "${NB_SETUP_KEY:?setup-key is required}"
MGMT_URL="${NB_MANAGEMENT_URL:-https://api.netbird.io:443}"
HOSTNAME_ARG="${NB_HOSTNAME:-}"
PSK="${NB_PRESHARED_KEY:-}"
TIMEOUT="${NB_TIMEOUT:-60}"

SUDO=()
if [ "$(id -u)" -ne 0 ]; then
  SUDO=(sudo)
fi

"${SUDO[@]}" netbird service install 2>/dev/null || true
"${SUDO[@]}" netbird service start
sleep 2

# Fall back if the event payload had no repository name.
if [ -z "$HOSTNAME_ARG" ]; then
  HOSTNAME_ARG="gh-runner-${GITHUB_REPOSITORY##*/}"
fi

args=(--setup-key "$NB_SETUP_KEY" --management-url "$MGMT_URL")
[ -n "$HOSTNAME_ARG" ] && args+=(--hostname "$HOSTNAME_ARG")
[ -n "$PSK" ] && args+=(--preshared-key "$PSK")

"${SUDO[@]}" netbird up "${args[@]}"

deadline=$(( $(date +%s) + TIMEOUT ))
while [ "$(date +%s)" -lt "$deadline" ]; do
  if "${SUDO[@]}" netbird status 2>/dev/null | grep -q "Management: Connected"; then
    exit 0
  fi
done

echo "NetBird failed to connect within ${TIMEOUT}s" >&2
"${SUDO[@]}" netbird status -d || true
exit 1
