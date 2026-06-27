#!/usr/bin/env bash
# Install a NetBird client from the official GitHub release.
set -euo pipefail

REPO="netbirdio/netbird"
VERSION="${NB_VERSION:-latest}"

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
  386)                     ARCH="386" ;;
  armv7l|armv6l|armhf|arm) ARCH="arm" ;;
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
tar -xzf "$TMP/nb.tar.gz" -C "$TMP" netbird
"${SUDO[@]}" install -m 0755 "$TMP/netbird" /usr/local/bin/netbird

INSTALLED="$(netbird version)"
case "$INSTALLED" in
  *"$VERSION"*) echo "Version check passed (${VERSION})" ;;
  *) echo "::warning::Installed version '${INSTALLED}' does not contain '${VERSION}'" ;;
esac
