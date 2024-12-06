#!/usr/bin/env bash
# Scaffolds a dated BIA/ACP addendum from the template, pre-filling the
# "Known open items" table from the most recent audit report.
#
# This does NOT auto-generate the ACP ratings (Confidentiality/Integrity/
# Availability) — those require a human business judgment call. It only
# saves the boilerplate.
#
# Usage: bash scaffold-bia-acp.sh [RepoPath] ["App Name"] ["Asset ID"]

set -uo pipefail

REPO_PATH="${1:-$(pwd)}"
APP_NAME="${2:-<app name>}"
ASSET_ID="${3:-<asset ID>}"

REPO_PATH="$(cd "$REPO_PATH" && pwd)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLAYBOOK_ROOT="$(dirname "$SCRIPT_DIR")"
TEMPLATE_PATH="$PLAYBOOK_ROOT/templates/BIA_ACP_TEMPLATE.md"

if [[ ! -f "$TEMPLATE_PATH" ]]; then
  echo "Template not found: $TEMPLATE_PATH" >&2
  exit 1
fi

TODAY="$(date +%Y-%m-%d)"
SECURITY_DIR="$REPO_PATH/security"
mkdir -p "$SECURITY_DIR"
OUT_PATH="$SECURITY_DIR/BIA_ACP_$TODAY.md"

if [[ -f "$OUT_PATH" ]]; then
  echo "Refusing to overwrite existing file: $OUT_PATH" >&2
  exit 1
fi

REPORTS_DIR="$REPO_PATH/audit/reports"
LATEST_CYB="$(ls -t "$REPORTS_DIR"/CYB_report_*.md 2>/dev/null | head -1 || true)"

OPEN_ITEMS="| ID | Item | Status |\n|---|---|---|\n"
if [[ -n "$LATEST_CYB" ]]; then
  count=0
  while IFS= read -r line; do
    if [[ "$line" =~ ^###\ \[([^]]+)\]\ ([^ ]+)\ -\ (.+)$ ]]; then
      sev="${BASH_REMATCH[1]}"; id="${BASH_REMATCH[2]}"; msg="${BASH_REMATCH[3]}"
      marker="[REVIEW]"
      [[ "$sev" == "Critical" || "$sev" == "High" ]] && marker="[CRITICAL/HIGH]"
      OPEN_ITEMS+="| $id | $msg | $marker Open |\n"
      count=$((count+1))
    fi
  done < "$LATEST_CYB"
  if [[ $count -eq 0 ]]; then
    OPEN_ITEMS+="| - | No open findings in latest audit run | - |\n"
  fi
  echo "Pulled $count open item(s) from: $LATEST_CYB"
else
  OPEN_ITEMS+="| - | No audit report found - run audit/run-audit.sh first | - |\n"
  echo "No CYB_report_*.md found under $REPORTS_DIR - run run-audit.sh first for auto-filled findings."
fi

sed -e "s/<app name>/$APP_NAME/g" \
    -e "s/<YYYY-MM-DD>/$TODAY/g" \
    -e "s/<org asset ID, e.g. APP-2026-001>/$ASSET_ID/g" \
    "$TEMPLATE_PATH" > "$OUT_PATH.tmp"

awk -v repl="$OPEN_ITEMS" '
  /\| <ID> \| <finding> \|.*\|/ { printf "%s", repl; next }
  { print }
' "$OUT_PATH.tmp" > "$OUT_PATH"
rm -f "$OUT_PATH.tmp"

echo "BIA/ACP addendum scaffolded at: $OUT_PATH"
echo "Now fill in the Confidentiality/Integrity/Availability ratings by hand and route for CYB validation."
