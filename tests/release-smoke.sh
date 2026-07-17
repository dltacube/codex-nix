#!/usr/bin/env bash

set -euo pipefail

usage() {
  echo "usage: $0 OUTPUT_PATH EXPECTED_TARGET" >&2
  exit 2
}

[[ $# -eq 2 ]] || usage

output=$(realpath "$1")
expected_target=$2
max_closure_bytes=$((1024 * 1024 * 1024))

case "$expected_target" in
  x86_64-unknown-linux-musl | aarch64-unknown-linux-musl)
    is_linux=true
    ;;
  x86_64-apple-darwin | aarch64-apple-darwin)
    is_linux=false
    ;;
  *)
    echo "unsupported expected target: $expected_target" >&2
    exit 2
    ;;
esac

for command in basename cat diff find grep jq mkdir mktemp nix realpath rm sed sort; do
  command -v "$command" >/dev/null || {
    echo "required command is unavailable: $command" >&2
    exit 1
  }
done

tmp=$(mktemp -d "${TMPDIR:-/tmp}/codex-release-smoke.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

cat >"$tmp/expected-top-level" <<'EOF'
bin
codex-package.json
codex-path
codex-resources
EOF

find "$output" -mindepth 1 -maxdepth 1 -exec basename {} \; | sort >"$tmp/actual-top-level"
if ! diff -u "$tmp/expected-top-level" "$tmp/actual-top-level"; then
  echo "package has an unexpected top-level layout" >&2
  exit 1
fi

cat >"$tmp/expected-files" <<'EOF'
bin/codex
bin/codex-code-mode-host
codex-package.json
codex-path/rg
codex-resources/zsh/bin/zsh
EOF
if [[ "$is_linux" == true ]]; then
  echo "codex-resources/bwrap" >>"$tmp/expected-files"
fi
sort -o "$tmp/expected-files" "$tmp/expected-files"

find "$output" -type f -print | sed "s#^$output/##" | sort >"$tmp/actual-files"
if ! diff -u "$tmp/expected-files" "$tmp/actual-files"; then
  echo "package files do not match the upstream Codex package contract" >&2
  exit 1
fi

metadata="$output/codex-package.json"
version=$(jq -er '.version | select(type == "string" and length > 0)' "$metadata")
jq -e \
  --arg target "$expected_target" \
  --arg version "$version" \
  '. == {
    layoutVersion: 1,
    version: $version,
    target: $target,
    variant: "codex",
    entrypoint: "bin/codex",
    resourcesDir: "codex-resources",
    pathDir: "codex-path"
  }' "$metadata" >/dev/null

codex="$output/bin/codex"
host="$output/bin/codex-code-mode-host"
rg="$output/codex-path/rg"
zsh="$output/codex-resources/zsh/bin/zsh"

for executable in "$codex" "$host" "$rg" "$zsh"; do
  [[ -x "$executable" ]] || {
    echo "package executable is missing or not executable: $executable" >&2
    exit 1
  }
done

if [[ "$is_linux" == true ]]; then
  [[ -x "$output/codex-resources/bwrap" ]] || {
    echo "Linux package is missing executable bwrap" >&2
    exit 1
  }
fi

actual_version=$($codex --version)
[[ "$actual_version" == "codex-cli $version" ]] || {
  echo "version mismatch: expected 'codex-cli $version', got '$actual_version'" >&2
  exit 1
}

$codex --help >"$tmp/help"
grep -Fq "Codex CLI" "$tmp/help"

$codex completion zsh >"$tmp/completion.zsh"
grep -Fq "compdef" "$tmp/completion.zsh"

printf 'bundled-search-ok\n' >"$tmp/search.txt"
$rg -q '^bundled-search-ok$' "$tmp/search.txt"

zsh_result=$($zsh -fc 'print -r -- bundled-zsh-ok')
[[ "$zsh_result" == "bundled-zsh-ok" ]]

$host </dev/null

if [[ "$is_linux" == true ]]; then
  "$output/codex-resources/bwrap" --version
fi

mkdir -p "$tmp/home/.codex" "$tmp/home/.cache"
doctor_status=0
HOME="$tmp/home" \
  CODEX_HOME="$tmp/home/.codex" \
  XDG_CACHE_HOME="$tmp/home/.cache" \
  $codex doctor --json >"$tmp/doctor.json" 2>"$tmp/doctor.stderr" || doctor_status=$?

jq -e '
  .checks.installation.status == "ok" and
  .checks["runtime.provenance"].status == "ok" and
  .checks["runtime.search"].status == "ok" and
  .checks["runtime.search"].details["search provider"] == "bundled"
' "$tmp/doctor.json" >/dev/null || {
  cat "$tmp/doctor.stderr" >&2
  jq . "$tmp/doctor.json" >&2
  echo "Codex doctor did not recognize a complete package with bundled search (exit $doctor_status)" >&2
  exit 1
}

closure_size=$(
  nix path-info --json --closure-size "$output" |
    jq -er '
      if type == "array" then
        .[0].closureSize
      elif type == "object" then
        to_entries[0].value.closureSize
      else
        error("unexpected nix path-info JSON shape")
      end
    '
)
if (( closure_size >= max_closure_bytes )); then
  echo "closure size $closure_size exceeds the $max_closure_bytes byte limit" >&2
  exit 1
fi

printf 'validated codex %s for %s (closure: %s bytes)\n' \
  "$version" "$expected_target" "$closure_size"
