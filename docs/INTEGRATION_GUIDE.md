# Integration Guide

This guide adds the AI & Developer Security + Deployment Playbook to another
repository while keeping ownership of that project clear. Generated reports
credit the playbook tooling and its maintainer; they do not identify the
maintainer as a developer, auditor, owner, or approver of the consuming project.

**Playbook source:** <https://github.com/alouatiq/ai-dev-security-playbook>

**Maintainer:** [Dr. AL OUATIQ H.](https://www.alouatiq.com)

## 1. Add the audit tooling

Keep `audit/` and `templates/` together because the BIA/ACP scaffold resolves
its template relative to those directories.

```powershell
git clone https://github.com/alouatiq/ai-dev-security-playbook.git $env:TEMP\ai-dev-security-playbook
Copy-Item $env:TEMP\ai-dev-security-playbook\audit .\audit -Recurse
Copy-Item $env:TEMP\ai-dev-security-playbook\templates .\templates -Recurse
Remove-Item $env:TEMP\ai-dev-security-playbook -Recurse -Force
```

```bash
git clone https://github.com/alouatiq/ai-dev-security-playbook.git /tmp/ai-dev-security-playbook
cp -R /tmp/ai-dev-security-playbook/audit ./audit
cp -R /tmp/ai-dev-security-playbook/templates ./templates
rm -rf /tmp/ai-dev-security-playbook
```

Commit the copied files in the consuming repository so CI can run the same
version reviewed by the team. Generated files under `audit/reports/` should
normally be ignored unless the project's governance process requires them in Git.

## 2. Run it

```powershell
powershell -ExecutionPolicy Bypass -File audit\run-audit.ps1 -RepoPath .
```

```bash
bash audit/run-audit.sh .
```

Each run prints the playbook source and maintainer, then writes:

- `audit/reports/audit-report-<timestamp>.md`
- `audit/reports/CYB_report_<timestamp>.md`

To scaffold a governance addendum after an audit:

```powershell
powershell -ExecutionPolicy Bypass -File audit\scaffold-bia-acp.ps1 -RepoPath . -AppName "My App" -AssetId "APP-001"
```

```bash
bash audit/scaffold-bia-acp.sh . "My App" "APP-001"
```

## 3. Add CI/CD templates

For GitHub, copy the selected files into their active locations:

```text
pipelines/github/ci.yml          -> .github/workflows/ci.yml
pipelines/github/cd.yml          -> .github/workflows/cd.yml
pipelines/github/release.yml     -> .github/workflows/release.yml
pipelines/github/dependabot.yml  -> .github/dependabot.yml
```

For GitLab, copy `pipelines/gitlab/.gitlab-ci.yml` to the repository root and
add the optional Renovate and release files described in
[`pipelines/gitlab/README.md`](../pipelines/gitlab/README.md).

Adjust directory, runtime, registry, and coverage variables before enabling
the workflows. Never copy both platform configurations into the same project.

## 4. Preserve project authorship

Keep the generated tooling-attribution lines in reports. Fill project-owned
fields such as `Auditor`, `Author`, `Proposed by`, and `Approved by` with the
people responsible for the consuming project. The attribution means only:

> This project used the AI & Developer Security + Deployment Playbook to run
> or scaffold this assessment.

It does not mean that Dr. AL OUATIQ H. developed, audited, approved, or
endorsed the consuming project.

## 5. Update the vendored copy

Review upstream changes before replacing local files:

```powershell
git clone --depth 1 https://github.com/alouatiq/ai-dev-security-playbook.git $env:TEMP\ai-dev-security-playbook
git diff --no-index .\audit $env:TEMP\ai-dev-security-playbook\audit
```

After review, replace the vendored `audit/` and `templates/` directories,
run the audit locally, and commit the update with the upstream commit hash in
the commit body for traceability.
