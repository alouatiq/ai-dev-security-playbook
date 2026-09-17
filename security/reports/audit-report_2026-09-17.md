# Security Audit Report

**Repo:** /e/Projects/ai-dev-security-playbook
**Date:** 2026-09-17 17:37:25
**Verdict:** 🟡 ACCEPTED RISK — review warnings before deploying
**Audit tooling:** [AI & Developer Security + Deployment Playbook](https://github.com/alouatiq/ai-dev-security-playbook)
**Tooling maintainer:** Dr. AL OUATIQ H.
**Maintainer website:** [https://www.alouatiq.com](https://www.alouatiq.com)
**Attribution scope:** This identifies the audit tooling only; the audited project remains the work and responsibility of its own contributors.

| ID | Status | Severity | Message |
| --- | --- | --- | --- |
| F-03 | PASS | Medium | CORS is not a catch-all wildcard |
| F-01 | WARN | Critical | No backend source found — skipped |
| G-03 | PASS | Critical | No .env / key / token-cache files tracked by git |
| G-01 | PASS | Critical | No obvious f-string-interpolated SQL found |
| G-02 | WARN | High | No frontend source found — skipped |
| F-09 | WARN | Medium | No Dockerfile found — skipped |
| F-07 | WARN | Low | No requirements*.txt found — skipped |
| G-05 | WARN | High | No package.json found — skipped |
| F-07b | WARN | High | pip-audit not installed (pip install pip-audit) — skipped |
| F-02 | PASS | Low | No hardcoded http:// found in frontend API client(s) |

**Summary:** 4 PASS, 6 WARN, 0 FAIL
