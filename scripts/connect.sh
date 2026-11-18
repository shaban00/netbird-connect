#!/usr/bin/env bash
# Start the NetBird daemon and register this runner as an ephemeral peer.
set -euo pipefail

: "${NB_SETUP_KEY:?setup-key is required}"
MGMT_URL="${NB_MANAGEMENT_URL:-https://api.netbird.io:443}"
HOSTNAME_ARG="${NB_HOSTNAME:-}"
PSK="${NB_PRESHARED_KEY:-}"
ALLOW_SSH="${ALLOW_SSH:-false}"
WAIT_TIMEOUT="${NB_WAIT_TIMEOUT:-60}"
WAIT_FOR_PEER="${NB_WAIT_FOR_PEER:-}"
WAIT_FOR_HOST="${NB_WAIT_FOR_HOST:-}"
EXTRA_ARGS="${NB_EXTRA_ARGS:-}"

if ! [[ "$WAIT_TIMEOUT" =~ ^[0-9]+$ ]]; then
  echo "::error::wait-timeout must be a number of seconds (got '${WAIT_TIMEOUT}')" >&2
  exit 1
fi
if [ -n "${WAIT_FOR_PEER}${WAIT_FOR_HOST}" ] && [ "$WAIT_TIMEOUT" -eq 0 ]; then
  echo "::error::wait-for-peer and wait-for-host need wait-timeout above 0" >&2
  exit 1
fi

# wait-for-host: host:port entries, separated by commas or spaces.
HOSTS=()
read -ra HOSTS <<< "${WAIT_FOR_HOST//,/ }"
for hp in "${HOSTS[@]}"; do
  if ! [[ "$hp" =~ ^(\[[0-9A-Fa-f:.]+\]|[^:[:space:]]+):[0-9]{1,5}$ ]]; then
    echo "::error::wait-for-host entries must look like host:port or [ipv6]:port (got '${hp}')" >&2
    exit 1
  fi
done
if [ -n "$WAIT_FOR_PEER" ] && ! command -v jq >/dev/null 2>&1; then
  echo "::error::wait-for-peer needs jq on the runner" >&2
  exit 1
fi


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

# --- optionally enable the NetBird SSH server on the runner ---
if [ "$ALLOW_SSH" = "true" ]; then
  args+=(--allow-server-ssh --enable-ssh-local-port-forwarding \
    --enable-ssh-remote-port-forwarding --enable-ssh-sftp --enable-ssh-root \
    --network-monitor=true --disable-ssh-auth)
fi

# --- extra flags for 'netbird up', split on whitespace (no shell evaluation) ---
# Added last, so a flag here overrides the same flag set by the inputs above.
EXTRA=()
read -ra EXTRA <<< "${EXTRA_ARGS//$'\n'/ }"
for a in "${EXTRA[@]}"; do
  case "$a" in
    --setup-key|--setup-key=*|-k)
      echo "::error::Pass the setup key with the setup-key input, not extra-args" >&2
      exit 1 ;;
  esac
done
args+=("${EXTRA[@]}")

"${SUDO[@]}" netbird up "${args[@]}"

# --- wait until the runner is really on the network ---
# 'netbird up' can return before management, signal and the peer tunnels are
# up, so a step right after this one could fail to reach a private host.
status_line() {
  { "${SUDO[@]}" netbird status 2>/dev/null || true; } | sed -n "s/^${1}:[[:space:]]*//p" | head -n1
}

peer_connected() {
  "${SUDO[@]}" netbird status --json 2>/dev/null | jq -e --arg p "$WAIT_FOR_PEER" '
    [.peers.details[]?
      | select(.status == "Connected")
      | select(.fqdn == $p or (.fqdn | startswith($p + ".")) or (.netbirdIp | split("/")[0]) == $p)
    ] | length > 0' >/dev/null
}

if [ "$WAIT_TIMEOUT" -gt 0 ]; then
  deadline=$(( SECONDS + WAIT_TIMEOUT ))
  until [ "$(status_line Management)" = "Connected" ] && [ "$(status_line Signal)" = "Connected" ]; do
    if (( SECONDS >= deadline )); then
      echo "::error::Not connected to NetBird after ${WAIT_TIMEOUT}s" >&2
      "${SUDO[@]}" netbird status >&2 || true
      exit 1
    fi
    sleep 2
  done
  echo "Connected to management and signal"

  if [ -n "$WAIT_FOR_PEER" ]; then
    until peer_connected; do
      if (( SECONDS >= deadline )); then
        echo "::error::Peer '${WAIT_FOR_PEER}' not connected after ${WAIT_TIMEOUT}s (check that a policy lets this runner reach it)" >&2
        "${SUDO[@]}" netbird status -d >&2 || true
        exit 1
      fi
      sleep 2
    done
    echo "Connected to peer ${WAIT_FOR_PEER}"
  fi

  # A TCP connection proves the whole path: tunnel, route or network resource,
  # DNS name, and the access policy for that port.
  for hp in "${HOSTS[@]}"; do
    host="${hp%:*}"; host="${host#[}"; host="${host%]}"
    port="${hp##*:}"
    
    until timeout 5 bash -c 'exec 3<>"/dev/tcp/$1/$2"' _ "$host" "$port" 2>/dev/null; do
      if (( SECONDS >= deadline )); then
        echo "::error::Could not connect to ${hp} after ${WAIT_TIMEOUT}s (check the route or network resource, DNS, and that a policy allows this port)" >&2
        exit 1
      fi
      sleep 2
    done
    echo "Reached ${hp}"
  done
fi

# --- outputs for later steps ---
NB_IP="$(status_line 'NetBird IP')"
NB_FQDN="$(status_line FQDN)"
if [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    echo "ip=${NB_IP%%/*}"
    echo "fqdn=${NB_FQDN}"
  } >> "$GITHUB_OUTPUT"
fi
echo "Runner is ${NB_FQDN:-unknown} (${NB_IP%%/*})"
