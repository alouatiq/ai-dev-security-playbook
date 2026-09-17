# Security Audit (CYB-style report) — TEMPLATE

> Copy this file, fill in the sections, and drop it in your project's
> `security/` folder as `CYB_report_<YYYY-MM-DD>.md`. If you just want an
> auto-generated version from the current codebase, run
> `audit/run-audit.ps1` (or `.sh`) — it writes a populated copy of this
> structure to `<repo>/audit/reports/CYB_report_<timestamp>.md` automatically.
> Use this template for the deeper, human-reviewed point-in-time report
> (manual controls, business context, sign-off) that the automated version
> cannot produce on its own.

**Scope:** <what's covered — backend/frontend/infra components, repo name>
**Audit date:** <YYYY-MM-DD>
**Auditor:** <name / "Internal security review">
**Commit reviewed:** `<short-sha>` (branch `<branch>`)
**Audit tooling:** [AI & Developer Security + Deployment Playbook](https://github.com/alouatiq/ai-dev-security-playbook)
**Tooling maintainer:** Dr. AL OUATIQ H.
**Maintainer website:** [https://www.alouatiq.com](https://www.alouatiq.com)
**Attribution scope:** This identifies the audit tooling only; the audited
project remains the work and responsibility of its own contributors.

This is a **point-in-time** report. The reusable, re-runnable version of these
checks lives in [`../README.md`](../README.md) (the checklist) and
[`../audit/run-audit.ps1`](../audit/run-audit.ps1) / [`../audit/run-audit.sh`](../audit/run-audit.sh)
(the automated scanner). Re-run those after every significant change.

---

## 1. Standards this audit maps to

| Standard | Why it applies |
| ---------- | ---------------- |
| OWASP Top 10 (2021) | General web app risk baseline |
| OWASP API Security Top 10 (2023) | Applies to any API-first backend |
| OWASP ASVS 4.0 | Verification-level controls (auth, transport, config) |
| CIS Docker Benchmark | Container hardening for any shipped image |
| *(project-specific, e.g. IEC 62443-4-1/-4-2)* | *(add if this is an OT/industrial system)* |

---

## 2. Executive summary

<1–2 paragraph narrative: what's solid, what's the dominant risk, what to fix first.>

| Severity | Count | IDs |
| ---------- | ------- | ----- |
| 🔴 Critical/High | | |
| 🟠 Medium | | |
| 🟡 Low / Info | | |
| ✅ Verified-good | | |

**Verdict:** 🟢 LOW RISK / 🟡 ACCEPTED RISK / 🔴 CRITICAL — DO NOT DEPLOY

---

## 3. Findings

> One subsection per finding that isn't a clean pass. Copy this block per finding.

### 🔴 <ID> — <short title>

**Standards:** <OWASP/ASVS/CWE reference(s)>
**Where:** `<file:line>` — link into the repo.
**Detail:** <what's wrong and why it matters>
**Impact:** <concrete consequence>
**Remediation:** <specific steps, cheapest-first if there are options>

---

## 4. Verified-good controls

- <ID> — <what was checked and confirmed passing>

---

## 5. Carried-over items (deployment-dependent, unchanged from prior report)

| ID | Severity | Status | Action needed |
|----|----------|--------|---------------|
| | | | |

---

## 6. Verdict

<Final statement — safe to release / release with accepted risk / blocked, and why.>
