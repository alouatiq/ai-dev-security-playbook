# `audit/` — Automated Security Audit + Report Generators

Portable, project-agnostic security scanning. Point it at any repo and get a
PASS/WARN/FAIL breakdown plus a deploy-readiness verdict.

## Files

| File | Purpose |
|---|---|
| `run-audit.ps1` | Windows/PowerShell audit script. Runs all automated checks from `../README.md` §2, prints a verdict, and writes two reports. |
| `run-audit.sh` | Same checks/output for Linux/macOS/Git-Bash. |
| `scaffold-bia-acp.ps1` | Scaffolds a dated BIA/ACP addendum (`../templates/BIA_ACP_TEMPLATE.md`) into the target repo's `security/` folder, pre-filling open findings from the latest audit run. Windows/PowerShell. |
| `scaffold-bia-acp.sh` | Same, for Linux/macOS/Git-Bash. |
| `reports/` | **Generated at runtime** — not checked in. Created the first time you run `run-audit`. |

## How to run the audit

```powershell
# Windows
powershell -ExecutionPolicy Bypass -File run-audit.ps1 -RepoPath C:\path\to\your\repo
```

```bash
# Linux / macOS / Git-Bash
bash run-audit.sh /path/to/your/repo
```

If `-RepoPath` / the path argument is omitted, it audits the current
directory. The script:

1. Auto-discovers backend (`*.py`, `requirements*.txt`), frontend
   (`*.ts`/`*.tsx`/`*.js`, `package.json`), and `Dockerfile*` anywhere in the
   repo (skipping `node_modules`, `.git`, `dist`, `build`, `venv`, etc.).
2. Runs each control, printing `[PASS]` / `[WARN]` / `[FAIL]` with an ID.
3. Prints an overall verdict: `LOW RISK`, `ACCEPTED RISK`, or `CRITICAL`.
4. Writes **two** files to `<RepoPath>/audit/reports/`:
   - `audit-report-<timestamp>.md` — flat PASS/WARN/FAIL table.
   - `CYB_report-<timestamp>.md` — a standards-mapped, executive-summary
     style report matching the format used in a real CYB security review
     (see `../templates/CYB_REPORT_TEMPLATE.md`), auto-populated from the
     scan results. Use this one to paste into a PR/MR or hand to Cyber
     Security as a first-pass point-in-time report.
5. Exits non-zero **only** on a CRITICAL verdict, so it can gate CI
   (`security-scan` / `security` stage in `../pipelines/`).

Every console run and generated report identifies the
[AI & Developer Security + Deployment Playbook](https://github.com/alouatiq/ai-dev-security-playbook)
and its maintainer, [Dr. AL OUATIQ H.](https://www.alouatiq.com). The wording
explicitly attributes only the audit tooling; it does not claim authorship,
ownership, or endorsement of the project being audited.

See `../README.md` §2–3 for the full checklist and how the verdict is
computed (severity mapping per control ID).

## How to scaffold a BIA/ACP addendum

The BIA/ACP (Business Impact Analysis — Access/Confidentiality/Integrity/
Availability rating) is a **governance document**, not something a script can
fully generate: the ratings require a human business judgment call about data
sensitivity, tolerable outage, and regulatory context. What the scaffold
script *can* do is remove the boilerplate and auto-list current findings:

```powershell
powershell -ExecutionPolicy Bypass -File scaffold-bia-acp.ps1 -RepoPath C:\path\to\repo -AppName "My App" -AssetId "APP-2026-001"
```

```bash
bash scaffold-bia-acp.sh /path/to/repo "My App" "APP-2026-001"
```

Run `run-audit` **first** so a `CYB_report_*.md` exists — the scaffold script
reads the most recent one and fills in §4 ("Known open items") automatically.
It then writes `<repo>/security/BIA_ACP_<date>.md`; fill in the
Confidentiality/Integrity/Availability ratings and impact-analysis sections
by hand, then route it for Cyber Security validation.

## Notes for anyone editing these scripts

- Keep `run-audit.ps1` **ASCII-only** (no em-dashes, no emoji as literal
  characters). Windows PowerShell 5.1 reads unmarked `.ps1` files using the
  system ANSI codepage, not UTF-8 — multi-byte characters silently corrupt
  parsing (not just display) and cause sections of the script to behave
  incorrectly. Use `-`, `[TAG]`-style text instead of `—`/emoji.
- `run-audit.sh` is fine with UTF-8/emoji since bash on Linux/macOS/Git-Bash
  defaults to a UTF-8 locale.
