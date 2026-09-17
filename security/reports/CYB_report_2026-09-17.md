# Security Audit (CYB-style report)

**Scope:** /e/Projects/ai-dev-security-playbook
**Audit date:** 2026-09-17
**Method:** automated scan via `audit/run-audit.sh` (see `../README.md` for the full checklist; manual controls are not covered here)
**Audit tooling:** [AI & Developer Security + Deployment Playbook](https://github.com/alouatiq/ai-dev-security-playbook)
**Tooling maintainer:** Dr. AL OUATIQ H.
**Maintainer website:** [https://www.alouatiq.com](https://www.alouatiq.com)
**Attribution scope:** This identifies the audit tooling only; the audited project remains the work and responsibility of its own contributors.

## 1. Standards this audit maps to

| Standard | Why it applies |
|---|---|
| OWASP Top 10 (2021) | General web app risk baseline |
| OWASP API Security Top 10 (2023) | Applies to any API-first backend |
| OWASP ASVS 4.0 | Verification-level controls (auth, transport, config) |
| CIS Docker Benchmark | Container hardening for any shipped image |

## 2. Executive summary

**Verdict: 🟡 ACCEPTED RISK — review warnings before deploying**

| Severity | FAIL count |
|---|---|
| Critical | 0 |
| High | 0 |
| Medium | 0 |
| Warnings (any severity) | 6 |

## 3. Findings

### [Informational] F-01 - No backend source found — skipped
**Standard:** OWASP API2:2023 (Broken Authentication), A01:2021  
**Remediation:** Require a validated auth dependency (JWT/OAuth2/API key) on every route.

### [Informational] G-02 - No frontend source found — skipped
**Standard:** OWASP A03:2021 (Injection / XSS)  
**Remediation:** Remove dangerouslySetInnerHTML/innerHTML/eval or sanitize input first.

### [Informational] F-09 - No Dockerfile found — skipped
**Standard:** CIS Docker Benchmark 4.1  
**Remediation:** Add a non-root USER directive to the Dockerfile.

### [Informational] F-07 - No requirements*.txt found — skipped
**Standard:** OWASP A06:2021 (Vulnerable Components)  
**Remediation:** Pin dependencies (==) or add a hashed lock file.

### [Informational] G-05 - No package.json found — skipped
**Standard:** OWASP A06:2021 (Vulnerable Components)  
**Remediation:** Patch or replace npm packages with known CVEs (npm audit).

### [Informational] F-07b - pip-audit not installed (pip install pip-audit) — skipped
**Standard:** OWASP A06:2021 (Vulnerable Components)  
**Remediation:** Patch or replace packages with known CVEs (pip-audit).

## 4. Verified-good controls

- [F-03] CORS is not a catch-all wildcard
- [G-03] No .env / key / token-cache files tracked by git
- [G-01] No obvious f-string-interpolated SQL found
- [F-02] No hardcoded http:// found in frontend API client(s)

**Summary:** 4 PASS, 6 WARN, 0 FAIL - Verdict: 🟡 ACCEPTED RISK — review warnings before deploying
