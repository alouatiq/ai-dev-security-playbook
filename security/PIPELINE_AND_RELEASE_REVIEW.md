# Pipeline, Release & Security Review — `ai-dev-security-playbook`

**Date:** 2026-09-17
**Reviewer:** Claude (Anthropic), at the request of the repo owner
**Scope:** this repository's own CI/CD, release automation, and security
posture — as distinct from `audit/run-audit.*`, which audits *other*
repositories' application code, not this one.

This document is the manual review this playbook itself calls for in
`docs/RELEASE_GUIDE.md` §3 ("CI is green... audit verdict is LOW/ACCEPTED RISK")
and `README.md` §5 ("run the audit, act on the verdict") — applied to the
playbook's own repo before treating it as production-ready to hand to other
projects.

---

## 1. Starting state (before this review)

| Area | Finding |
| --- | --- |
| **CI/CD** | `.github/` did not exist. `pipelines/github/*` and `pipelines/gitlab/*` are templates for *consumers* — nothing was validating this repo's own scripts, YAML, or docs on every change. |
| **Release** | No git tags, no GitHub Releases, despite `docs/RELEASE_GUIDE.md` and `pipelines/github/release.yml` documenting release-please as the intended mechanism. `.release-please-manifest.json` / `release-please-config.json` did not exist at the repo root. |
| **Governance files** | No `LICENSE`, `SECURITY.md`, or `CONTRIBUTING.md` — three of the items `README.md` §2.G requires *of consuming projects* were absent from the playbook's own repo. |
| **Audit scripts** | Two real bugs found (below) in `audit/run-audit.sh` and (one of them) `audit/run-audit.ps1`. |
| **`.gitignore`** | Did not exist. `audit/README.md` documents `audit/reports/` as "generated at runtime, not checked in" but nothing enforced that. |

None of this is a **security vulnerability** in the traditional sense — it's
a **process gap**: the playbook that teaches "run CI/CD, cut releases,
audit before you ship" was not doing any of that for itself.

---

## 2. Bugs found and fixed in `audit/run-audit.sh` / `.ps1`

### 2.1 F-07 (dependency pinning) — false PASS on completely unpinned deps

**Before:** `PASS` was granted whenever a `requirements*.txt` had no `>=` or
`~=` range operator. A bare, versionless line (`requests`, with **no**
operator at all — the least-pinned case possible) satisfied that condition
and was reported as `"is pinned"`.

**Impact:** a project with zero version pinning could get a clean PASS on
this control, defeating its purpose (OWASP A06:2021, supply-chain pinning).

**Fix:** now requires every real dependency line (skipping comments, blanks,
`-r`/`-e`/`--` option lines) to contain `==`, or the file to carry
`--hash=` entries. Applied identically to both `run-audit.sh` and
`run-audit.ps1` (they must stay in parity — see `CONTRIBUTING.md`).

### 2.2 G-05 (npm audit) — bash/PowerShell parity gap

**Before:** `run-audit.ps1` parsed `npm audit --json` properly
(`ConvertFrom-Json`) and reported `moderate`/`low` counts as `WARN`.
`run-audit.sh` grepped the raw JSON text for a `"high":N` substring, only
ever checked `high`/`critical`, and silently ignored `moderate`/`low`
entirely — a materially weaker check on the platform most CI runners
actually use (GitHub-hosted Linux runners).

**Fix:** `run-audit.sh` now parses the JSON with `python3 -c "import
json..."` (matching the robustness of the PowerShell path) when Python 3 is
available, with the old grep as a fallback, and reports `moderate`/`low` as
`WARN` like the PowerShell script always did.

### 2.3 Path-with-spaces correctness bug (bash only)

**Before:** several checks piped a newline-separated file list through
`echo "$FILES" | xargs grep ...`. `xargs` word-splits on **all** whitespace,
not just newlines — a file path containing a space (e.g. `My Project/api.py`)
would be silently split into bogus arguments, and `grep` would look for
nonexistent files. Since stderr was redirected to `/dev/null`, this failed
**silently**: the check could simply never see the affected file's content,
producing a false PASS with no visible error.

**Fix:** added an `any_file_matches()` helper that loops over the file list
line-by-line (`while IFS= read -r f`) instead of shell-splitting it, and
replaced every `xargs`-based content check (F-01, F-02, F-03, G-01, G-02)
with it. `run-audit.ps1` was never affected — `Get-ChildItem`/`Select-String`
operate on `FileInfo` objects, not re-split path strings.

None of these were **regressions** — they look like they were present since
the checks were first written. Severity: **Medium** for 2.1 (a false PASS on
a real, if low-severity, control) and 2.2 (weaker-than-intended scan on the
common platform), **Low** for 2.3 (requires an unusual path naming
convention to trigger).

---

## 3. What was added to close the process gap

| Added | Purpose |
| --- | --- |
| `.github/workflows/ci.yml` | **New**, written for *this* repo (not copied from `pipelines/github/ci.yml`, which assumes a backend/frontend app that doesn't exist here). Lints every Markdown, YAML (incl. GitHub Actions schema via `actionlint`), and JSON file; runs ShellCheck on `audit/*.sh` and PSScriptAnalyzer on `audit/*.ps1`; then self-audits by running `audit/run-audit.sh .` against the repo as a smoke test. |
| `.github/workflows/release.yml` | release-please, wired exactly as `docs/RELEASE_GUIDE.md` describes. |
| `.github/dependabot.yml` | `github-actions` ecosystem, weekly — keeps the *active* workflow's pinned actions current. See §4 for a coverage gap this doesn't close. |
| `release-please-config.json` / `.release-please-manifest.json` | `package-name: ai-dev-security-playbook`, `release-type: simple`, starting version `0.1.0` (the same convention the playbook documents for consumers — bump to `1.0.0` by hand whenever the maintainer considers the API/checklist stable and committed). |
| `.gitignore` | Enforces the documented "`audit/reports/` is generated, not committed" rule (nothing did before). |
| `SECURITY.md` | Disclosure contact + scope (in-scope: audit-logic false negatives; out-of-scope: consumer projects' own findings). |
| `CONTRIBUTING.md` | Parity rule (`.sh`/`.ps1` must change together), ASCII-only rule for `.ps1`, pre-PR checklist. |
| `security/` (this directory) | This review, plus the dated self-audit reports (§5). |

**Deliberately not copied:** `pipelines/github/cd.yml`. It builds and
Trivy-scans backend/frontend Docker images — this repo ships no application
and has no `Dockerfile`, so there is nothing for it to build. Adding it here
would be pure noise (every run would no-op or error). Consumers of the
playbook should still copy `cd.yml` into their own project once it has a
backend/frontend to containerize.

---

## 4. Known limitation: Dependabot doesn't see the template copies

`pipelines/github/{ci,cd,release}.yml` and `pipelines/gitlab/.gitlab-ci.yml`
pin action/image versions (`actions/checkout@v4`, `aquasecurity/trivy-action@master`,
etc.) for consumers to copy. GitHub Dependabot only scans **active** workflow
files under `.github/workflows/`, so it cannot see or bump these template
copies — they can drift out of date silently. Mitigation: `CONTRIBUTING.md`
calls this out, and it's listed here so it isn't forgotten; the practical fix
is a periodic manual diff against upstream action releases (there is no fully
automated fix without either activating those templates as real workflows —
which would defeat their purpose as copy-paste starting points — or a custom
script, which was judged not worth the added complexity for a low-frequency,
low-risk drift).

---

## 5. Self-audit result (after the fixes above)

Ran `bash audit/run-audit.sh .` against this repo (Git Bash, 2026-09-17):

```text
==== Result: 4 PASS, 6 WARN, 0 FAIL ====
==== Verdict: ACCEPTED RISK — review warnings before deploying ====
```

Full reports: [`reports/CYB_report_2026-09-17.md`](reports/CYB_report_2026-09-17.md) ·
[`reports/audit-report_2026-09-17.md`](reports/audit-report_2026-09-17.md).

**Read this verdict correctly:** all 6 `WARN`s are *"no backend/frontend/
Dockerfile/requirements found — skipped"* — expected and correct for a
docs-and-scripts repo with no application code. `ACCEPTED RISK` here means
*"most controls are not applicable"*, not *"real risk was found and
accepted."* Zero `FAIL`s. The 4 `PASS`es that did run (no wildcard CORS
pattern in tracked `.py`, no `.env`/key/token-cache files tracked by git, no
f-string-interpolated SQL pattern, no hardcoded `http://` in an `api.*`
file) are genuinely meaningful for this repo (there's no reason any of that
content should exist here) and all passed.

---

## 6. Open item for the maintainer (not fixed here — a real decision)

**No `LICENSE` file.** This is a business/legal decision (how the playbook
may be reused, whether it's open-source and under what terms, or
proprietary), not something to default silently. Recommendation: pick a
license (MIT/Apache-2.0 are the common choices for reusable tooling like
this) and add it, since `docs/INTEGRATION_GUIDE.md` already invites other
repos/teams to copy and vendor this content — right now that's happening
with no stated terms.

---

## 7. Verdict

**CI, release automation, and the audit tooling are now active, correct, and
self-consistent (`.sh`/`.ps1` parity restored).** No Critical/High findings
against this repo. The one open item (§6) needs the maintainer's decision,
not an automated fix.

**Update (2026-09-17, end of day):** the loop was closed end-to-end —
release-please's first PR was merged, cutting
[`v0.2.0`](https://github.com/alouatiq/ai-dev-security-playbook/releases/tag/v0.2.0);
all four Dependabot PRs it triggered (bumping `actions/checkout`,
`actions/upload-artifact`, `googleapis/release-please-action`, and
`DavidAnson/markdownlint-cli2-action` to their current major versions) were
merged; `ci.yml`'s 6 jobs (markdown/yaml/json lint, ShellCheck,
PSScriptAnalyzer, self-audit) are green on `main` post-merge. The pipeline
and release mechanisms this document reviews are no longer just configured —
they've each fired for real, successfully, at least once.
