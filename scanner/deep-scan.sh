#!/usr/bin/env bash
# Deep scan for Linux/macOS. Run from the project folder, or pass its path.
#
# Usage: bash deep-scan.sh [ProjectPath]
#
# Downloads pinned scanners into a per-user cache (nothing is installed),
# verifies each SHA-256 against tools.lock, runs them read-only, and writes
# raw results to <project>/.devsec/ for index.html to pick up. .devsec holds a
# self-ignoring .gitignore, so `git status` stays clean.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="$(cd "${1:-$PWD}" && pwd)"
LOCK="$SCRIPT_DIR/tools.lock"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/ai-dev-security-playbook"
OUT="$PROJECT/.devsec"
STATE_LINES=()

case "$(uname -s)" in
  Linux) OS=linux ;;
  Darwin) OS=macos ;;
  *) echo "Unsupported OS: $(uname -s). On Windows use deep-scan.ps1." >&2; exit 2 ;;
esac
case "$(uname -m)" in
  x86_64|amd64) ARCH=x64 ;;
  arm64|aarch64) ARCH=arm64 ;;
  *) echo "Unsupported CPU: $(uname -m)" >&2; exit 2 ;;
esac
PLATFORM="$OS-$ARCH"

mkdir -p "$OUT" "$CACHE" || exit 2
printf '*\n' > "$OUT/.gitignore"
rm -f "$OUT"/*.json
STARTED="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

json_escape() {
  local s="${1//\\/\\\\}"; s="${s//\"/\\\"}"; printf '%s' "${s//$'\n'/ }"
}

write_status() {
  # write_status <running|done>. Written to a temp name first so the page
  # never reads a half-written file.
  local phase="$1" body="" line
  for line in "${STATE_LINES[@]+"${STATE_LINES[@]}"}"; do
    [[ -n "$body" ]] && body+=","
    body+="$line"
  done
  printf '{"schema":1,"phase":"%s","platform":"%s","root":"%s","started":"%s","tools":[%s]}\n' \
    "$phase" "$PLATFORM" "$(json_escape "$PROJECT")" "$STARTED" "$body" > "$OUT/status.json.tmp"
  mv "$OUT/status.json.tmp" "$OUT/status.json"
}

record() {
  # record <tool> <ok|skipped|failed> <version> <note>
  STATE_LINES+=("{\"tool\":\"$1\",\"state\":\"$2\",\"version\":\"$3\",\"note\":\"$(json_escape "$4")\"}")
  printf '  [%s] %s %s\n' "$2" "$1" "$4"
  write_status running
}

lookup() {
  # lookup <tool> -> "version sha256 asset" for this platform
  awk -v t="$1" -v p="$PLATFORM" '$1==t && ($3==p || $3=="any") {print $2, $4, $5; exit}' "$LOCK"
}

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

fetch() {
  # fetch <url> <dest> <sha256>; the partial file is removed on any mismatch
  if command -v curl >/dev/null 2>&1; then curl -fsSL --retry 2 -o "$2" "$1" || return 1
  else wget -q -O "$2" "$1" || return 1; fi
  if [[ "$(sha256_of "$2")" != "$3" ]]; then
    rm -f "$2"
    echo "  HASH MISMATCH for $1 - refusing to run it" >&2
    return 1
  fi
}

base_url() {
  case "$1" in
    gitleaks) echo "https://github.com/gitleaks/gitleaks/releases/download/v$2" ;;
    osv-scanner) echo "https://github.com/google/osv-scanner/releases/download/v$2" ;;
    trivy) echo "https://github.com/aquasecurity/trivy/releases/download/v$2" ;;
    zizmor) echo "https://github.com/zizmorcore/zizmor/releases/download/v$2" ;;
    opengrep) echo "https://github.com/opengrep/opengrep/releases/download/v$2" ;;
  esac
}

get_tool() {
  # get_tool <tool>; sets TOOL_BIN and TOOL_VERSION
  local tool="$1" version sha asset dir
  TOOL_BIN=""; TOOL_VERSION=""
  read -r version sha asset <<< "$(lookup "$tool")"
  [[ -n "${sha:-}" ]] || return 1
  TOOL_VERSION="$version"
  dir="$CACHE/$tool-$version-$PLATFORM"
  TOOL_BIN="$dir/$tool"
  [[ -x "$TOOL_BIN" ]] && return 0
  mkdir -p "$dir"
  fetch "$(base_url "$tool" "$version")/$asset" "$dir/$asset" "$sha" || return 1
  case "$asset" in
    *.tar.gz) tar -xzf "$dir/$asset" -C "$dir" || return 1
      [[ -x "$TOOL_BIN" ]] || TOOL_BIN="$(find "$dir" -type f -name "$tool" | head -1)" ;;
    *) mv "$dir/$asset" "$TOOL_BIN" ;;
  esac
  chmod +x "$TOOL_BIN"
}

get_rules() {
  # Rules stay a download, never vendored: opengrep-rules carries the Commons
  # Clause, so this repo must not redistribute them.
  local version sha asset dir
  read -r version sha asset <<< "$(lookup opengrep-rules)"
  dir="$CACHE/opengrep-rules-$version"
  RULES_DIR="$dir/opengrep-rules-$version"
  [[ -d "$RULES_DIR" ]] && return 0
  mkdir -p "$dir"
  fetch "https://github.com/opengrep/opengrep-rules/archive/$asset" "$dir/$asset" "$sha" || return 1
  tar -xzf "$dir/$asset" -C "$dir"
}

echo ""
echo "==== Deep scan: $PROJECT ($PLATFORM) ===="
echo "Results: $OUT"
echo ""
write_status running

# --- gitleaks: secrets in files and full Git history ---
if get_tool gitleaks; then
  if git -C "$PROJECT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    MODE=git
    [[ "$(git -C "$PROJECT" rev-parse --is-shallow-repository)" == "true" ]] && SHALLOW=" (shallow clone: history incomplete)" || SHALLOW=""
  else MODE=dir; SHALLOW=" (not a Git repository: history skipped)"; fi
  # --redact=100 keeps secret values out of the report on disk.
  "$TOOL_BIN" "$MODE" "$PROJECT" --redact=100 --no-banner --log-level error \
    --report-format json --report-path "$OUT/gitleaks.json" --exit-code 0
  if [[ $? -eq 0 ]]; then record gitleaks ok "$TOOL_VERSION" "scanned $MODE$SHALLOW"
  else record gitleaks failed "$TOOL_VERSION" "scanner error"; fi
else record gitleaks failed "" "download or verification failed"; fi

# --- osv-scanner: dependency vulnerabilities (lockfiles and manifests) ---
if get_tool osv-scanner; then
  "$TOOL_BIN" scan source -r --format json --output-file "$OUT/osv-scanner.json" "$PROJECT" >/dev/null 2>&1
  code=$?
  # 0 = clean, 1 = vulnerabilities found, 128 = nothing to scan.
  case "$code" in
    0|1) record osv-scanner ok "$TOOL_VERSION" "scan complete" ;;
    128) record osv-scanner ok "$TOOL_VERSION" "no lockfiles found" ;;
    *) record osv-scanner failed "$TOOL_VERSION" "exit code $code" ;;
  esac
else record osv-scanner failed "" "download or verification failed"; fi

# --- trivy: vulnerabilities and IaC / Dockerfile misconfiguration ---
if get_tool trivy; then
  TRIVY_CACHE_DIR="$CACHE/trivy-db" "$TOOL_BIN" fs --quiet --scanners vuln,misconfig \
    --format json --output "$OUT/trivy.json" "$PROJECT" >/dev/null 2>&1
  code=$?
  if [[ $code -eq 0 ]]; then record trivy ok "$TOOL_VERSION" "scan complete"
  else record trivy failed "$TOOL_VERSION" "exit code $code"; fi
else record trivy failed "" "download or verification failed"; fi

# --- zizmor: GitHub Actions workflow security ---
if [[ ! -d "$PROJECT/.github/workflows" ]]; then
  record zizmor skipped "" "no GitHub Actions workflows"
elif get_tool zizmor; then
  "$TOOL_BIN" --format=json --no-progress --offline "$PROJECT" > "$OUT/zizmor.json" 2>/dev/null
  code=$?
  # zizmor exits 10-14 when it has findings.
  if [[ $code -eq 0 || $code -ge 10 ]]; then record zizmor ok "$TOOL_VERSION" "scan complete"
  else rm -f "$OUT/zizmor.json"; record zizmor failed "$TOOL_VERSION" "exit code $code"; fi
else record zizmor failed "" "download or verification failed"; fi

# --- opengrep: SAST. Open-source engine, compatible with Semgrep rules ---
LANGS=""
for pair in py:python js:javascript jsx:javascript ts:typescript tsx:typescript java:java go:go rb:ruby php:php cs:csharp; do
  ext="${pair%%:*}"; lang="${pair##*:}"
  [[ " $LANGS " == *" $lang "* ]] && continue
  if [[ -n "$(find "$PROJECT" -type f -name "*.$ext" -not -path '*/node_modules/*' -not -path '*/.git/*' -print -quit 2>/dev/null)" ]]; then
    LANGS="$LANGS $lang"
  fi
done
if [[ -z "$LANGS" ]]; then
  record opengrep skipped "" "no supported source language found"
elif get_tool opengrep && get_rules; then
  CONFIGS=()
  for lang in $LANGS; do CONFIGS+=(--config "$RULES_DIR/$lang"); done
  "$TOOL_BIN" scan --json --quiet --output "$OUT/opengrep.json" "${CONFIGS[@]}" "$PROJECT" >/dev/null 2>&1
  code=$?
  if [[ $code -eq 0 || $code -eq 1 ]]; then record opengrep ok "$TOOL_VERSION" "languages:$LANGS"
  else record opengrep failed "$TOOL_VERSION" "exit code $code"; fi
else record opengrep failed "" "download or verification failed"; fi

write_status done
echo ""
echo "Done. Go back to the browser page: results load automatically."
echo "If they do not, drop the files from $OUT onto the page."
