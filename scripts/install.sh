#!/usr/bin/env bash
# Install a NetBird client from a GitHub release (official, or a fork via NB_REPO).
set -euo pipefail

REPO="${NB_REPO:-netbirdio/netbird}"
VERSION="${NB_VERSION:-latest}"

if ! printf '%s' "$REPO" | grep -Eq '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'; then
  echo "::error::repo must look like owner/name (got '${REPO}')." >&2
  exit 1
fi

resolve_latest() {
  local api="https://api.github.com/repos/${REPO}/releases/latest"
  local auth=()
  [ -n "${GITHUB_TOKEN:-}" ] && auth=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
  local tag
  if command -v jq >/dev/null 2>&1; then
    tag="$(curl -fsSL "${auth[@]}" -H 'Accept: application/vnd.github+json' "$api" | jq -r '.tag_name')"
  else
    tag="$(curl -fsSL "${auth[@]}" -H 'Accept: application/vnd.github+json' "$api" \
      | grep -m1 '"tag_name"' | sed -E 's/.*"tag_name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')"
  fi
  printf '%s' "${tag#v}"
}

if [ -z "$VERSION" ] || [ "$VERSION" = "latest" ]; then
  VERSION="$(resolve_latest)"
  if [ -z "$VERSION" ] || [ "$VERSION" = "null" ]; then
    echo "::error::Could not resolve the latest NetBird release from the GitHub API" >&2
    exit 1
  fi
else
  if ! printf '%s' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$'; then
    echo "::error::Version must look like 0.73.1 (got '${VERSION}')." >&2
    exit 1
  fi
fi

ARCH="$(uname -m)"
case "$ARCH" in
  x86_64|amd64)            ARCH="amd64" ;;
  aarch64|arm64)           ARCH="arm64" ;;
  i386|i486|i586|i686)     ARCH="386" ;;
  # Releases ship one 32-bit ARM build, armv6, which also runs on armv7.
  armv7l|armv6l|armhf|arm) ARCH="armv6" ;;
  *) echo "::error::Unsupported architecture: $ARCH" >&2; exit 1 ;;
esac

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

SUDO=()
if [ "$(id -u)" -ne 0 ]; then
  SUDO=(sudo)
fi

URL="https://github.com/${REPO}/releases/download/v${VERSION}/netbird_${VERSION}_linux_${ARCH}.tar.gz"
echo "Downloading NetBird ${VERSION} (${ARCH}) - ${URL}"
curl -fsSL -o "$TMP/nb.tar.gz" "$URL"

# Every release publishes netbird_<version>_checksums.txt (sha256sum format).
ASSET="netbird_${VERSION}_linux_${ARCH}.tar.gz"
SUMS_URL="https://github.com/${REPO}/releases/download/v${VERSION}/netbird_${VERSION}_checksums.txt"
if ! curl -fsSL -o "$TMP/checksums.txt" "$SUMS_URL"; then
  echo "::error::Could not download ${SUMS_URL} to verify the download" >&2
  exit 1
fi
EXPECTED="$(awk -v f="$ASSET" '$2 == f || $2 == "*" f { print $1; exit }' "$TMP/checksums.txt")"
if [ -z "$EXPECTED" ]; then
  echo "::error::${ASSET} is not listed in the release checksums" >&2
  exit 1
fi
ACTUAL="$(sha256sum "$TMP/nb.tar.gz" | awk '{ print $1 }')"
if [ "$EXPECTED" != "$ACTUAL" ]; then
  echo "::error::Checksum mismatch for ${ASSET}: expected ${EXPECTED}, got ${ACTUAL}" >&2
  exit 1
fi
echo "Checksum verified (${ASSET})"

tar -xzf "$TMP/nb.tar.gz" -C "$TMP" netbird
"${SUDO[@]}" install -m 0755 "$TMP/netbird" /usr/local/bin/netbird

INSTALLED="$(netbird version)"
case "$INSTALLED" in
  *"$VERSION"* | *"${VERSION%%-*}"*) echo "Version check passed (${VERSION} from ${REPO})" ;;
  *) echo "::warning::Installed version '${INSTALLED}' does not contain '${VERSION}'" ;;
esac
