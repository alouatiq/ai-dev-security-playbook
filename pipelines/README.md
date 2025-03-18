# `pipelines/` — CI/CD Templates (GitHub Actions & GitLab CI)

Two parallel pipeline implementations of the **same** stages, so the
deploy-readiness guarantee is identical no matter which platform hosts the
repo. Copy the folder matching your Git host — don't add both.

```
pipelines/
├── github/   ← copy into .github/ if the repo is on GitHub
└── gitlab/   ← copy into repo root if the repo is on GitLab
```

## Stage-by-stage equivalence

| Stage | GitHub Actions | GitLab CI |
|---|---|---|
| Lint | `lint-backend`, `lint-frontend` jobs in `ci.yml` | `lint-backend`, `lint-frontend` jobs, `lint` stage |
| Build | `build-backend`, `build-frontend` jobs in `ci.yml` | `build-backend`, `build-frontend` jobs, `build` stage |
| Test | `test-backend`, `test-frontend` jobs in `ci.yml` | `test-backend`, `test-frontend` jobs, `test` stage |
| Security scan | `security-scan` job (pip-audit, npm audit, Bandit, Semgrep, gitleaks) in `ci.yml` | `pip-audit`, `npm-audit`, `bandit` jobs, `security` stage, **plus** GitLab's built-in SAST/Dependency-Scanning/Secret-Detection/Container-Scanning templates via `include:` |
| Quality gate | `quality-gate` job (coverage threshold) in `ci.yml` | `quality-gate` job, `quality` stage |
| Build image + Trivy gate + push | `cd.yml`, triggered on push to `main` | `build-and-push-*` jobs, `deploy` stage, gated to `$CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH` |
| Dependency bumps | `dependabot.yml` (docker/pip/npm/github-actions, weekly) | `renovate.json` (GitLab has no native Dependabot) |
| Release automation (SemVer + changelog) | `release.yml` (release-please) | `release-job.example.yml` (semantic-release) |

Docker is part of **both** pipelines: each build stage builds the
backend/frontend image from its `Dockerfile`, runs a Trivy vulnerability scan
gated on `CRITICAL,HIGH`, and only pushes to the registry if the scan passes.

## Required adjustments before use

Both templates are parameterized at the top of the file — edit these instead
of rewriting pipeline logic:

| Variable | Meaning | Where |
|---|---|---|
| `BACKEND_DIR` / `FRONTEND_DIR` | Path to each part of the project. Set to `""` if that part doesn't exist. | `env:` (GitHub) / `variables:` (GitLab) block |
| `PYTHON_VERSION`, `NODE_VERSION` | Toolchain versions | same |
| `COVERAGE_THRESHOLD` | Minimum test coverage % enforced by the quality gate | same |
| `TRIVY_SEVERITY` | Severities that block an image push | `cd.yml` / `.gitlab-ci.yml` |
| Registry name / image names | Where images get pushed | `cd.yml` (`REGISTRY`, `IMAGE_NAME_*`) / `.gitlab-ci.yml` (uses `$CI_REGISTRY_IMAGE` automatically) |

You will also need to set up, per platform:
- **GitHub:** branch protection on `main` requiring the CI checks to pass
  before merge; `GITHUB_TOKEN`/registry credentials (already available by
  default for GHCR).
- **GitLab:** protected branch rules on the default branch; CI/CD variables
  `CI_REGISTRY_USER` / `CI_REGISTRY_PASSWORD` (or use the built-in
  `$CI_REGISTRY_*` predefined variables with the GitLab Container Registry).

See `github/README.md` and `gitlab/README.md` for platform-specific setup
notes, and `../README.md` §4 for the stage diagram and rationale.
