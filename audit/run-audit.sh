#!/usr/bin/env bash
# Portable, project-agnostic security audit for any repo (Python backend,
# Node frontend, monorepo, or either alone).
#
# Usage: bash run-audit.sh [RepoPath]
# Default RepoPath: current directory.
#
# Prints PASS/WARN/FAIL per control, an overall verdict (LOW RISK /
# ACCEPTED RISK / CRITICAL), and writes a markdown report to
# <RepoPath>/audit/reports/. Exits non-zero only on a CRITICAL verdict.

set -uo pipefail

REPO_PATH="${1:-$(pwd)}"
REPO_PATH="$(cd "$REPO_PATH" && pwd)"
PLAYBOOK_NAME="AI & Developer Security + Deployment Playbook"
PLAYBOOK_REPOSITORY="https://github.com/alouatiq/ai-dev-security-playbook"
PLAYBOOK_MAINTAINER="Dr. AL OUATIQ H."
PLAYBOOK_WEBSITE="https://www.alouatiq.com"

EXCLUDE_REGEX='/(node_modules|\.git|dist|build|venv|\.venv|__pycache__|coverage|\.next|out)(/|$)'

PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0
CRIT_HIGH_FAIL=0
declare -a REPORT_ROWS=()
declare -a ROW_ID=() ROW_STATUS=() ROW_SEVERITY=() ROW_MSG=()

result() {
  local id="$1" status="$2" severity="$3" msg="$4"
  case "$status" in
    PASS) PASS_COUNT=$((PASS_COUNT+1)); color="\033[32m" ;;
    WARN) WARN_COUNT=$((WARN_COUNT+1)); color="\033[33m" ;;
    FAIL) FAIL_COUNT=$((FAIL_COUNT+1)); color="\033[31m"
          if [[ "$severity" == "Critical" || "$severity" == "High" ]]; then CRIT_HIGH_FAIL=$((CRIT_HIGH_FAIL+1)); fi ;;
  esac
  printf "  ${color}[%s] %-6s %s\033[0m\n" "$status" "$id" "$msg"
  REPORT_ROWS+=("| $id | $status | $severity | $msg |")
  ROW_ID+=("$id"); ROW_STATUS+=("$status"); ROW_SEVERITY+=("$severity"); ROW_MSG+=("$msg")
}

find_files() {
  # find_files <name-pattern>
  find "$REPO_PATH" -type f -name "$1" 2>/dev/null | grep -Ev "$EXCLUDE_REGEX" || true
}

echo ""
echo "==== Security audit: $REPO_PATH ===="
echo "Tooling: $PLAYBOOK_NAME by $PLAYBOOK_MAINTAINER"
echo "Source: $PLAYBOOK_REPOSITORY | Website: $PLAYBOOK_WEBSITE"
echo ""

PY_FILES="$(find_files '*.py')"
JS_TS_FILES="$( { find_files '*.ts'; find_files '*.tsx'; find_files '*.js'; } )"

# --- F-03  CORS not wildcard (Medium) ---
if [[ -n "$PY_FILES" ]] && echo "$PY_FILES" | xargs grep -lE 'allow_origin_regex\s*=\s*r?"\.\*"|Access-Control-Allow-Origin.*\*' 2>/dev/null | grep -q .; then
  result 'F-03' 'FAIL' 'Medium' 'CORS allows any origin (wildcard) in application code'
else
  result 'F-03' 'PASS' 'Medium' 'CORS is not a catch-all wildcard'
fi

# --- F-01  Auth dependency present on API routes (Critical) ---
AUTH_HIT=0
if [[ -n "$PY_FILES" ]] && echo "$PY_FILES" | xargs grep -lE 'Depends\(|Security\(|HTTPBearer|OAuth2|require_auth|jwt_required' 2>/dev/null | grep -q .; then AUTH_HIT=1; fi
if [[ -n "$JS_TS_FILES" ]] && echo "$JS_TS_FILES" | xargs grep -lE 'passport\.|verifyToken|authMiddleware|requireAuth|jwt\.verify' 2>/dev/null | grep -q .; then AUTH_HIT=1; fi
if [[ $AUTH_HIT -eq 1 ]]; then
  result 'F-01' 'PASS' 'Critical' 'API routes declare an auth/security dependency'
elif [[ -n "$PY_FILES$JS_TS_FILES" ]]; then
  result 'F-01' 'FAIL' 'Critical' 'No auth dependency found on any route — endpoints may be unauthenticated'
else
  result 'F-01' 'WARN' 'Critical' 'No backend source found — skipped'
fi

# --- G-03  No secret files tracked by git (Critical) ---
if git -C "$REPO_PATH" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  TRACKED="$(git -C "$REPO_PATH" ls-files 2>/dev/null | grep -E '(^|/)\.env$|\.env\.(local|prod|production)$|\.pem$|\.key$|_msal_cache|id_rsa$' || true)"
  if [[ -n "$TRACKED" ]]; then
    result 'G-03' 'FAIL' 'Critical' "Secret-like files tracked by git: $(echo "$TRACKED" | tr '\n' ' ')"
  else
    result 'G-03' 'PASS' 'Critical' 'No .env / key / token-cache files tracked by git'
  fi
else
  result 'G-03' 'WARN' 'Critical' 'Not a git repository — skipped'
fi

# --- G-01  SQL parameterization spot check (Critical) ---
if [[ -n "$PY_FILES" ]] && echo "$PY_FILES" | xargs grep -lE 'f"[^"]*\{[^}]+\}[^"]*"|f'"'"'[^'"'"']*\{[^}]+\}[^'"'"']*'"'"'' 2>/dev/null \
    | xargs grep -lE 'execute|cursor|SELECT|INSERT|UPDATE|DELETE|FROM|WHERE' 2>/dev/null | grep -q .; then
  result 'G-01' 'FAIL' 'Critical' 'Possible user input interpolated into SQL (f-string) — review query construction'
else
  result 'G-01' 'PASS' 'Critical' 'No obvious f-string-interpolated SQL found'
fi

# --- G-02  No XSS sinks in frontend (High) ---
if [[ -z "$JS_TS_FILES" ]]; then
  result 'G-02' 'WARN' 'High' 'No frontend source found — skipped'
elif echo "$JS_TS_FILES" | xargs grep -lE 'dangerouslySetInnerHTML|\.innerHTML\s*=|eval\(' 2>/dev/null | grep -q .; then
  result 'G-02' 'FAIL' 'High' 'XSS sink found (dangerouslySetInnerHTML / innerHTML / eval)'
else
  result 'G-02' 'PASS' 'High' 'No XSS sinks found in frontend source'
fi

# --- F-09  Dockerfiles set a non-root USER (Medium) ---
DOCKERFILES="$(find "$REPO_PATH" -type f -name 'Dockerfile*' 2>/dev/null | grep -Ev "$EXCLUDE_REGEX" || true)"
if [[ -z "$DOCKERFILES" ]]; then
  result 'F-09' 'WARN' 'Medium' 'No Dockerfile found — skipped'
else
  while IFS= read -r df; do
    rel="${df#$REPO_PATH/}"
    if grep -qE '^\s*USER\s+\S' "$df" 2>/dev/null; then
      result 'F-09' 'PASS' 'Medium' "$rel sets a non-root USER"
    else
      result 'F-09' 'FAIL' 'Medium' "$rel has no USER directive — container runs as root"
    fi
  done <<< "$DOCKERFILES"
fi

# --- F-07  Python deps pinned (Low) ---
REQ_FILES="$(find_files 'requirements*.txt')"
if [[ -z "$REQ_FILES" ]]; then
  result 'F-07' 'WARN' 'Low' 'No requirements*.txt found — skipped'
else
  while IFS= read -r rf; do
    rel="${rf#$REPO_PATH/}"
    if grep -q -- '--hash=' "$rf" 2>/dev/null || ! grep -qE '>=|~=' "$rf" 2>/dev/null; then
      result 'F-07' 'PASS' 'Low' "$rel is pinned"
    else
      result 'F-07' 'WARN' 'Low' "$rel uses unpinned ranges (>=, ~=) — no hashed lock file"
    fi
  done <<< "$REQ_FILES"
fi

# --- G-05  npm audit (High) ---
PKG_JSONS="$(find_files 'package.json')"
if [[ -z "$PKG_JSONS" ]]; then
  result 'G-05' 'WARN' 'High' 'No package.json found — skipped'
else
  while IFS= read -r pj; do
    dir="$(dirname "$pj")"
    rel="${dir#$REPO_PATH/}"
    if [[ ! -d "$dir/node_modules" ]]; then
      result 'G-05' 'WARN' 'High' "$rel — node_modules not installed, npm audit skipped (run npm ci first)"
      continue
    fi
    audit_json="$(cd "$dir" && npm audit --json 2>/dev/null)"
    high=$(echo "$audit_json" | grep -o '"high":[0-9]*' | head -1 | grep -o '[0-9]*$')
    crit=$(echo "$audit_json" | grep -o '"critical":[0-9]*' | head -1 | grep -o '[0-9]*$')
    high=${high:-0}; crit=${crit:-0}
    if [[ $((high+crit)) -gt 0 ]]; then
      result 'G-05' 'FAIL' 'High' "$rel npm audit: $crit critical, $high high"
    else
      result 'G-05' 'PASS' 'High' "$rel npm audit: 0 high/critical vulnerabilities"
    fi
  done <<< "$PKG_JSONS"
fi

# --- F-07b  pip-audit (High) ---
if ! command -v pip-audit >/dev/null 2>&1; then
  result 'F-07b' 'WARN' 'High' 'pip-audit not installed (pip install pip-audit) — skipped'
elif [[ -z "$REQ_FILES" ]]; then
  result 'F-07b' 'WARN' 'High' 'No requirements*.txt found — skipped'
else
  while IFS= read -r rf; do
    rel="${rf#$REPO_PATH/}"
    if pip-audit -r "$rf" >/dev/null 2>&1; then
      result 'F-07b' 'PASS' 'High' "$rel — pip-audit: no known vulnerabilities"
    else
      result 'F-07b' 'FAIL' 'High' "$rel — pip-audit reported vulnerabilities"
    fi
  done <<< "$REQ_FILES"
fi

# --- F-02  Hardcoded http:// in frontend API client (Low, informational) ---
API_CLIENTS="$(echo "$JS_TS_FILES" | grep -E 'api\.(ts|js|tsx|jsx)$' || true)"
if [[ -n "$API_CLIENTS" ]] && echo "$API_CLIENTS" | xargs grep -l 'http://' 2>/dev/null | grep -q .; then
  result 'F-02' 'WARN' 'Low' 'Frontend API client contains http:// — confirm production uses HTTPS/same-origin'
else
  result 'F-02' 'PASS' 'Low' 'No hardcoded http:// found in frontend API client(s)'
fi

# ==== Verdict ====
if [[ $CRIT_HIGH_FAIL -gt 0 ]]; then
  VERDICT="CRITICAL"; VERDICT_LINE="🔴 CRITICAL — DO NOT DEPLOY"
elif [[ $((FAIL_COUNT+WARN_COUNT)) -gt 0 ]]; then
  VERDICT="ACCEPTED RISK"; VERDICT_LINE="🟡 ACCEPTED RISK — review warnings before deploying"
else
  VERDICT="LOW RISK"; VERDICT_LINE="🟢 LOW RISK — safe to deploy to dev"
fi

echo ""
echo "==== Result: $PASS_COUNT PASS, $WARN_COUNT WARN, $FAIL_COUNT FAIL ===="
echo "==== Verdict: $VERDICT_LINE ===="
echo ""

# ==== Report ====
REPORT_DIR="$REPO_PATH/audit/reports"
mkdir -p "$REPORT_DIR"
STAMP="$(date +%Y-%m-%d_%H%M%S)"
REPORT_PATH="$REPORT_DIR/audit-report-$STAMP.md"

{
  echo "# Security Audit Report"
  echo ""
  echo "**Repo:** $REPO_PATH"
  echo "**Date:** $(date '+%Y-%m-%d %H:%M:%S')"
  echo "**Verdict:** $VERDICT_LINE"
  echo "**Audit tooling:** [$PLAYBOOK_NAME]($PLAYBOOK_REPOSITORY)"
  echo "**Tooling maintainer:** $PLAYBOOK_MAINTAINER"
  echo "**Maintainer website:** [$PLAYBOOK_WEBSITE]($PLAYBOOK_WEBSITE)"
  echo "**Attribution scope:** This identifies the audit tooling only; the audited project remains the work and responsibility of its own contributors."
  echo ""
  echo "| ID | Status | Severity | Message |"
  echo "|---|---|---|---|"
  for row in "${REPORT_ROWS[@]}"; do echo "$row"; done
  echo ""
  echo "**Summary:** $PASS_COUNT PASS, $WARN_COUNT WARN, $FAIL_COUNT FAIL"
} > "$REPORT_PATH"

echo "Report written to: $REPORT_PATH"

# ==== CYB-style report (standards-mapped) ====
declare -A STD_MAP=(
  ["F-01"]="OWASP API2:2023 (Broken Authentication), A01:2021|Require a validated auth dependency (JWT/OAuth2/API key) on every route."
  ["F-02"]="OWASP A02:2021 (Cryptographic Failures)|Serve over HTTPS only; confirm no hardcoded http:// remains in production config."
  ["F-03"]="OWASP A05:2021 (Security Misconfiguration)|Replace wildcard CORS with an explicit origin allow-list."
  ["F-07"]="OWASP A06:2021 (Vulnerable Components)|Pin dependencies (==) or add a hashed lock file."
  ["F-07b"]="OWASP A06:2021 (Vulnerable Components)|Patch or replace packages with known CVEs (pip-audit)."
  ["F-09"]="CIS Docker Benchmark 4.1|Add a non-root USER directive to the Dockerfile."
  ["G-01"]="OWASP A03:2021 (Injection)|Use parameterized queries; never f-string user input into SQL."
  ["G-02"]="OWASP A03:2021 (Injection / XSS)|Remove dangerouslySetInnerHTML/innerHTML/eval or sanitize input first."
  ["G-03"]="OWASP A02:2021 (Cryptographic Failures), CWE-798|Remove secret from git history; rotate the credential; use a secret manager."
  ["G-05"]="OWASP A06:2021 (Vulnerable Components)|Patch or replace npm packages with known CVEs (npm audit)."
)

CRIT_COUNT=0; HIGH_COUNT=0; MED_COUNT=0
for i in "${!ROW_ID[@]}"; do
  if [[ "${ROW_STATUS[$i]}" == "FAIL" ]]; then
    case "${ROW_SEVERITY[$i]}" in
      Critical) CRIT_COUNT=$((CRIT_COUNT+1)) ;;
      High) HIGH_COUNT=$((HIGH_COUNT+1)) ;;
      Medium) MED_COUNT=$((MED_COUNT+1)) ;;
    esac
  fi
done

CYB_PATH="$REPORT_DIR/CYB_report_$STAMP.md"
{
  echo "# Security Audit (CYB-style report)"
  echo ""
  echo "**Scope:** $REPO_PATH"
  echo "**Audit date:** $(date '+%Y-%m-%d')"
  echo "**Method:** automated scan via \`audit/run-audit.sh\` (see \`../README.md\` for the full checklist; manual controls are not covered here)"
  echo "**Audit tooling:** [$PLAYBOOK_NAME]($PLAYBOOK_REPOSITORY)"
  echo "**Tooling maintainer:** $PLAYBOOK_MAINTAINER"
  echo "**Maintainer website:** [$PLAYBOOK_WEBSITE]($PLAYBOOK_WEBSITE)"
  echo "**Attribution scope:** This identifies the audit tooling only; the audited project remains the work and responsibility of its own contributors."
  echo ""
  echo "## 1. Standards this audit maps to"
  echo ""
  echo "| Standard | Why it applies |"
  echo "|---|---|"
  echo "| OWASP Top 10 (2021) | General web app risk baseline |"
  echo "| OWASP API Security Top 10 (2023) | Applies to any API-first backend |"
  echo "| OWASP ASVS 4.0 | Verification-level controls (auth, transport, config) |"
  echo "| CIS Docker Benchmark | Container hardening for any shipped image |"
  echo ""
  echo "## 2. Executive summary"
  echo ""
  echo "**Verdict: $VERDICT_LINE**"
  echo ""
  echo "| Severity | FAIL count |"
  echo "|---|---|"
  echo "| Critical | $CRIT_COUNT |"
  echo "| High | $HIGH_COUNT |"
  echo "| Medium | $MED_COUNT |"
  echo "| Warnings (any severity) | $WARN_COUNT |"
  echo ""
  echo "## 3. Findings"
  echo ""
  for i in "${!ROW_ID[@]}"; do
    [[ "${ROW_STATUS[$i]}" == "PASS" ]] && continue
    id="${ROW_ID[$i]}"; status="${ROW_STATUS[$i]}"; sev="${ROW_SEVERITY[$i]}"; msg="${ROW_MSG[$i]}"
    entry="${STD_MAP[$id]:-n/a|See ../README.md checklist for this control.}"
    std="${entry%%|*}"; rem="${entry#*|}"
    tag="[Informational]"
    [[ "$status" == "FAIL" ]] && tag="[$sev]"
    echo "### $tag $id - $msg"
    echo "**Standard:** $std  "
    echo "**Remediation:** $rem"
    echo ""
  done
  echo "## 4. Verified-good controls"
  echo ""
  for i in "${!ROW_ID[@]}"; do
    [[ "${ROW_STATUS[$i]}" == "PASS" ]] && echo "- [${ROW_ID[$i]}] ${ROW_MSG[$i]}"
  done
  echo ""
  echo "**Summary:** $PASS_COUNT PASS, $WARN_COUNT WARN, $FAIL_COUNT FAIL - Verdict: $VERDICT_LINE"
} > "$CYB_PATH"

echo "CYB-style report written to: $CYB_PATH"
echo "Manual controls (TLS, real auth behaviour, network segmentation, CI wiring): see ../README.md"
echo ""

if [[ "$VERDICT" == "CRITICAL" ]]; then exit 1; else exit 0; fi
