# `pipelines/gitlab/` — GitLab CI

## Files

| File | Purpose |
|---|---|
| `.gitlab-ci.yml` | Full pipeline: lint → build → test → security → quality → deploy, plus GitLab's built-in SAST/Dependency-Scanning/Secret-Detection/Container-Scanning templates. Copy to the repo root as `.gitlab-ci.yml`. |
| `renovate.json` | Weekly dependency update MRs (GitLab has no native Dependabot equivalent; Renovate is the standard substitute). Copy to the repo root and enable the Renovate GitLab integration/bot for the project. |
| `release-job.example.yml` | `release` job running `semantic-release`; merge into `.gitlab-ci.yml` and add `release` to the `stages:` list. See `../../RELEASE_GUIDE.md`. |
| `.releaserc.example.json` | Copy to repo root as `.releaserc.json`; configures the semantic-release plugin chain (changelog + GitLab release + git commit-back). |

## Setup checklist

1. Copy `.gitlab-ci.yml` to the repository root.
2. Edit the `variables:` block at the top: `BACKEND_DIR`, `FRONTEND_DIR`,
   `PYTHON_VERSION`, `NODE_VERSION`, `COVERAGE_THRESHOLD`, `TRIVY_SEVERITY`.
   Set `BACKEND_DIR` or `FRONTEND_DIR` to `""` if that part of the project
   doesn't exist — the `rules:` on each job check for a non-empty value.
3. **Protected branch:** under **Settings → Repository → Protected branches**,
   protect the default branch so only merges via reviewed MR can reach it —
   the pipeline's `deploy` stage alone does not enforce this.
4. **Registry:** the `deploy` stage pushes to
   `$CI_REGISTRY_IMAGE/backend` / `.../frontend`, which resolve automatically
   to the project's built-in GitLab Container Registry using the predefined
   `$CI_REGISTRY_USER` / `$CI_REGISTRY_PASSWORD` variables — no extra secrets
   needed unless you're pushing to an external registry (update the
   `docker login` step and `$CI_REGISTRY_IMAGE` references if so).
5. **Built-in scanners:** the `include:` block pulls in GitLab's managed
   `SAST`, `Dependency-Scanning`, `Secret-Detection`, and
   `Container-Scanning` templates. These require GitLab Ultimate/Premium for
   full result triage in the **Security & Compliance** UI; on GitLab Free
   they still run and fail the pipeline on findings, just without the
   dashboard. If you're on GitLab Free and don't want the extra runner time,
   remove the `include:` entries you don't need — the custom `pip-audit`,
   `npm-audit`, and `bandit` jobs in the `security` stage still run
   regardless and cover the same ground as the GitHub Actions template.
6. Requires a Docker-capable runner (`docker:24-dind` service) for the
   `deploy` stage — confirm your GitLab Runner supports Docker-in-Docker, or
   swap to `kaniko`/`buildah` if privileged DinD isn't allowed on your
   runners.
7. Run `../../audit/run-audit.ps1` (or `.sh`) locally at least once before the
   first MR to establish a baseline verdict.
8. **Release automation:** add `release` to the `stages:` list, merge the
   `release:` job from `release-job.example.yml` into `.gitlab-ci.yml`, copy
   `.releaserc.example.json` to the repo root as `.releaserc.json`, and add a
   `GITLAB_TOKEN` CI/CD variable (API scope) — see `../../RELEASE_GUIDE.md`.

## Notes

- `workflow: rules:` at the top ensures merge requests always run the full
  pipeline, while direct pushes to the default branch skip straight to the
  `deploy` stage (build/scan/push) since lint/test already happened during
  the MR.
- The Trivy invocation in the `deploy` stage uses the `aquasec/trivy` image
  directly (via `docker run`) rather than a marketplace action, since GitLab
  CI doesn't have an Actions-style marketplace — this keeps the job portable
  across any GitLab instance (SaaS or self-managed).
