# Security Policy

This repository is a portable security/CI-CD **playbook** (documentation,
audit scripts, and pipeline templates) maintained by
[Dr. AL OUATIQ H.](https://www.alouatiq.com). It ships no runtime service of
its own — the audit scripts (`audit/run-audit.sh`, `audit/run-audit.ps1`) run
locally or in a consuming project's CI, and never transmit data anywhere.

## Reporting a vulnerability

If you find a security issue in the audit scripts, pipeline templates, or a
check that produces a false PASS on a real vulnerability class (a false
negative in the audit logic is itself a security issue for anyone relying on
it), please report it privately:

- Open a private [GitHub Security Advisory](../../security/advisories/new)
  on this repository, **or**
- Contact the maintainer via [alouatiq.com](https://www.alouatiq.com).

Please do not open a public issue for a security finding until a fix has
been released.

## Scope

In scope:
- Logic errors in `audit/run-audit.sh` / `audit/run-audit.ps1` that cause a
  real, exploitable condition (e.g. hardcoded secrets, SQL injection, XSS
  sinks, unauthenticated routes) to be reported as `PASS`.
- Injection or command-execution issues in the audit/scaffold scripts
  themselves when run against untrusted repository content.
- Secrets or credentials accidentally committed to this repository.

Out of scope:
- Findings in a project that merely *used* this playbook — report those to
  that project's own maintainers, not here.
- The generic CI/CD pipeline templates under `pipelines/` are intentionally
  parameterized starting points; a missing project-specific setting (e.g. an
  unset `BACKEND_DIR` repo variable) is a configuration step documented in
  `pipelines/github/README.md` / `pipelines/gitlab/README.md`, not a
  vulnerability.

## Response

This is a personal, single-maintainer project. There is no SLA, but reports
are read and triaged as soon as possible, and a fix or mitigation is
prioritized over new feature work.
