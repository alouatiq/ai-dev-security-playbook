# Secret Handling Guide for Developers and AI Agents

Use this guide for API keys, passwords, private keys, access tokens, database
URLs, signing material, certificates, and any value that grants access to data
or infrastructure.

## Non-negotiable rules

1. Never hardcode a real credential in source, tests, fixtures, notebooks,
   Dockerfiles, CI files, documentation, examples, or generated output.
2. Never paste a real credential into an AI prompt, chat, issue, pull request,
   screenshot, terminal transcript, or log. Use placeholders such as
   `EXAMPLE_API_KEY` or `<redacted>`.
3. Load local secrets from ignored environment files or the operating system.
   Load deployed secrets from the platform's secret store or a managed secret
   manager. Prefer workload identity or short-lived credentials when available.
4. Commit `.env.example` files only with safe placeholder values. Ignore real
   `.env` variants, key files, token caches, and local credential directories.
5. Treat frontend and mobile application code as public. A value shipped to a
   browser or client application cannot be kept secret; privileged calls must
   be made by an authenticated backend.
6. Do not log credentials, authorization headers, session cookies, connection
   strings, personal data, or complete upstream response bodies. Redact values
   before structured logging.
7. Never weaken or bypass a secret scan to make a commit pass. Investigate the
   finding and use a narrowly scoped, documented allowlist only for verified
   test data or false positives.

## Required setup for every clone

Install [gitleaks](https://github.com/gitleaks/gitleaks), then enable the
repository's staged-change protection:

```bash
git config core.hooksPath .githooks
git config --get core.hooksPath
```

The second command must print `.githooks`. Run the full playbook audit before
opening a pull or merge request:

```powershell
powershell -ExecutionPolicy Bypass -File audit\run-audit.ps1 -RepoPath .
```

```bash
bash audit/run-audit.sh .
```

Protection is layered:

- `.gitignore` prevents common local secret files from being added accidentally.
- `.githooks/pre-commit` scans staged content before it enters Git history.
- Audit controls `G-03` and `G-04` check risky filenames in the current tree
  and history.
- Audit control `G-07` uses gitleaks to inspect content and Git history.
- The CI templates scan every pushed change independently of local setup.

## Safe implementation patterns

Read secrets at runtime and fail clearly when a required value is absent. Keep
configuration names in source, but keep values outside source control.

```python
import os

api_key = os.environ["SERVICE_API_KEY"]
```

```typescript
const apiKey = process.env.SERVICE_API_KEY;
if (!apiKey) throw new Error("SERVICE_API_KEY is required");
```

Use CI secret variables, Kubernetes Secrets backed by an external provider,
cloud secret managers, or equivalent protected stores for deployment. Restrict
each identity to the minimum permissions and environment it needs.

## If a secret is exposed

Deleting the line or file is not enough because the value remains in Git
history, caches, logs, and existing clones.

1. Revoke or rotate the credential immediately. Do this before rewriting Git
   history.
2. Record the affected system, exposure window, repository visibility, and
   access logs without copying the secret into the incident record.
3. Remove the value from the current code and replace it with runtime secret
   loading.
4. Purge it from history with `git filter-repo` or BFG when required, then
   coordinate the forced update and fresh clones with all contributors.
5. Re-run gitleaks and the playbook audit, review provider access logs, and
   notify the project's security or incident-response owner.

Assume a committed or shared credential is compromised even when the repository
is private or the commit was quickly deleted.
