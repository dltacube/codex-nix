#!/usr/bin/env bash
#
# Update codex to a new version.
#
# Usage:
#   ./scripts/update.sh              # update to latest
#   ./scripts/update.sh --check      # check for new version, don't update
#   ./scripts/update.sh 0.105.0      # update to specific version

set -euo pipefail

REPO="openai/codex"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PACKAGE_NIX="${SCRIPT_DIR}/../package.nix"
TMP_HASHES=""
TMP_PACKAGE=""

PLATFORMS=(
  "aarch64-apple-darwin"
  "x86_64-apple-darwin"
  "x86_64-unknown-linux-musl"
  "aarch64-unknown-linux-musl"
)

cleanup() {
  [[ -n "$TMP_HASHES" && -f "$TMP_HASHES" ]] && rm -f "$TMP_HASHES"
  [[ -n "$TMP_PACKAGE" && -f "$TMP_PACKAGE" ]] && rm -f "$TMP_PACKAGE"
  return 0
}

trap cleanup EXIT

current_version() {
  grep 'version = "' "$PACKAGE_NIX" | head -1 | sed 's/.*"\(.*\)".*/\1/'
}

latest_version() {
  if command -v gh >/dev/null 2>&1; then
    gh release view --repo "$REPO" --json tagName -q '.tagName' | sed 's/^rust-v//'
  else
    curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
      | grep '"tag_name"' \
      | sed 's/.*"rust-v\(.*\)".*/\1/'
  fi
}

# --- main ---

CURRENT=$(current_version)
echo "Current version: ${CURRENT}"

if [[ "${1:-}" == "--check" ]] || [[ $# -eq 0 ]]; then
  LATEST=$(latest_version)
  echo "Latest version:  ${LATEST}"
  if [[ "$CURRENT" == "$LATEST" ]]; then
    echo "Already up to date."
    exit 0
  fi
  echo ""
  echo "Update available! Run:"
  echo "  ./scripts/update.sh ${LATEST}"
  [[ "${1:-}" == "--check" ]] && exit 0
  # If called with no args, fall through to update
  NEW_VERSION="$LATEST"
else
  NEW_VERSION="$1"
fi

echo "Updating to:     ${NEW_VERSION}"
echo ""

echo "Fetching SHA256 hashes..."
TMP_HASHES=$(mktemp)
for platform in "${PLATFORMS[@]}"; do
  url="https://github.com/${REPO}/releases/download/rust-v${NEW_VERSION}/codex-package-${platform}.tar.gz"
  hash=$(nix-prefetch-url "$url" 2>/dev/null | tail -1)

  if [[ -z "$hash" ]]; then
    echo "Failed to fetch hash for ${platform}: ${url}" >&2
    exit 1
  fi

  echo "  ${platform}: ${hash}"
  printf '%s %s\n' "$platform" "$hash" >> "$TMP_HASHES"
done

TMP_PACKAGE=$(mktemp)
awk -v version="$NEW_VERSION" '
  NR == FNR {
    hashes[$1] = $2
    next
  }

  {
    if ($0 ~ /version = "[^"]+"/) {
      sub(/version = "[^"]+"/, "version = \"" version "\"")
    }

    if ($0 ~ /^[[:space:]]*hashes = [{]/) {
      in_hashes = 1
    }

    if (in_hashes) {
      for (platform in hashes) {
        if (index($0, "\"" platform "\"") > 0) {
          sub(/= "[^"]*"/, "= \"" hashes[platform] "\"")
        }
      }
    }

    { print }

    if (in_hashes && $0 ~ /^[[:space:]]*};/) {
      in_hashes = 0
    }
  }
' "$TMP_HASHES" "$PACKAGE_NIX" > "$TMP_PACKAGE"
mv "$TMP_PACKAGE" "$PACKAGE_NIX"
TMP_PACKAGE=""

echo ""
echo "Updated package.nix to v${NEW_VERSION}"
echo ""
echo "Next steps:"
echo "  1. nix build              # verify it builds"
echo "  2. ./result/bin/codex --version"
echo "  3. git add package.nix && git commit -m \"update codex to ${NEW_VERSION}\""
