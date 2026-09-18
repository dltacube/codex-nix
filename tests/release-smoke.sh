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
codex-resources/voice/NOTICE.md
codex-resources/voice/bin/codex-voice-host
codex-resources/voice/licenses/LGPL-2.1.txt
codex-resources/voice/licenses/Opus.txt
codex-resources/voice/licenses/PCRE2.md
codex-resources/voice/licenses/libffi.txt
codex-resources/voice/licenses/proxy-libintl.txt
codex-resources/voice/licenses/sljit.txt
codex-resources/voice/licenses/zlib.txt
codex-resources/voice/manifest.json
codex-resources/voice/runtime.json
codex-resources/voice/sources.json
codex-resources/zsh/bin/zsh
EOF
# Exact Codex 0.155.0 voice inventories; keep additions and removals reviewable.
if [[ "$is_linux" == true ]]; then
  cat >>"$tmp/expected-files" <<'EOF'
codex-resources/bwrap
codex-resources/voice/lib/gstreamer-1.0/libgstapp.so
codex-resources/voice/lib/gstreamer-1.0/libgstaudioconvert.so
codex-resources/voice/lib/gstreamer-1.0/libgstaudioresample.so
codex-resources/voice/lib/gstreamer-1.0/libgstcoreelements.so
codex-resources/voice/lib/gstreamer-1.0/libgstopus.so
codex-resources/voice/lib/gstreamer-1.0/libgstrtp.so
codex-resources/voice/lib/gstreamer-1.0/libgstrtpmanager.so
codex-resources/voice/lib/libffi.so.8
codex-resources/voice/lib/libgio-2.0.so.0
codex-resources/voice/lib/libglib-2.0.so.0
codex-resources/voice/lib/libgmodule-2.0.so.0
codex-resources/voice/lib/libgobject-2.0.so.0
codex-resources/voice/lib/libgstallocators-1.0.so.0
codex-resources/voice/lib/libgstapp-1.0.so.0
codex-resources/voice/lib/libgstaudio-1.0.so.0
codex-resources/voice/lib/libgstbase-1.0.so.0
codex-resources/voice/lib/libgstnet-1.0.so.0
codex-resources/voice/lib/libgstpbutils-1.0.so.0
codex-resources/voice/lib/libgstreamer-1.0.so.0
codex-resources/voice/lib/libgstrtp-1.0.so.0
codex-resources/voice/lib/libgsttag-1.0.so.0
codex-resources/voice/lib/libgstvideo-1.0.so.0
codex-resources/voice/lib/libintl.so.8
codex-resources/voice/lib/libopus.so.0
codex-resources/voice/lib/libpcre2-8.so.0
codex-resources/voice/lib/libz.so.1
EOF
else
  cat >>"$tmp/expected-files" <<'EOF'
codex-resources/voice/lib/libffi.8.dylib
codex-resources/voice/lib/libgio-2.0.0.dylib
codex-resources/voice/lib/libglib-2.0.0.dylib
codex-resources/voice/lib/libgmodule-2.0.0.dylib
codex-resources/voice/lib/libgobject-2.0.0.dylib
codex-resources/voice/lib/libgstapp-1.0.0.dylib
codex-resources/voice/lib/libgstaudio-1.0.0.dylib
codex-resources/voice/lib/libgstbase-1.0.0.dylib
codex-resources/voice/lib/libgstnet-1.0.0.dylib
codex-resources/voice/lib/libgstpbutils-1.0.0.dylib
codex-resources/voice/lib/libgstreamer-1.0.0.dylib
codex-resources/voice/lib/libgstrtp-1.0.0.dylib
codex-resources/voice/lib/libgsttag-1.0.0.dylib
codex-resources/voice/lib/libgstvideo-1.0.0.dylib
codex-resources/voice/lib/libintl.8.dylib
codex-resources/voice/lib/libopus.0.dylib
codex-resources/voice/lib/libpcre2-8.0.dylib
codex-resources/voice/lib/libz.1.dylib
codex-resources/voice/plugins/libgstapp.dylib
codex-resources/voice/plugins/libgstaudioconvert.dylib
codex-resources/voice/plugins/libgstaudioresample.dylib
codex-resources/voice/plugins/libgstcoreelements.dylib
codex-resources/voice/plugins/libgstopus.dylib
codex-resources/voice/plugins/libgstrtp.dylib
codex-resources/voice/plugins/libgstrtpmanager.dylib
EOF
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
voice_host="$output/codex-resources/voice/bin/codex-voice-host"
rg="$output/codex-path/rg"
zsh="$output/codex-resources/zsh/bin/zsh"

for executable in "$codex" "$host" "$voice_host" "$rg" "$zsh"; do
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

# Exercise the voice helper loader without opening audio devices or a session.
voice_build_commit=$("$voice_host" --build-commit)
expected_voice_build_commit=$(jq -er \
  '.buildCommit | select(type == "string" and test("^[0-9a-f]{40}$"))' \
  "$output/codex-resources/voice/manifest.json")
[[ "$voice_build_commit" == "$expected_voice_build_commit" ]] || {
  echo "voice helper build commit does not match its manifest" >&2
  exit 1
}

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
