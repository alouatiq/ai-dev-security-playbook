# `pipelines/github/` — GitHub Actions

## Files

| File | Purpose |
|---|---|
| `ci.yml` | Runs on every push to a non-`main` branch. Stages: lint → build → test → security-scan → quality-gate. Copy to `.github/workflows/ci.yml`. |
| `cd.yml` | Runs on push to `main` (i.e. after a PR merge). Builds the backend/frontend Docker images, scans them with Trivy, and pushes only if the scan passes. Copy to `.github/workflows/cd.yml`. |
| `dependabot.yml` | Weekly dependency update PRs for Docker, pip, npm, and GitHub Actions themselves. Copy to `.github/dependabot.yml`. |
| `release.yml` | Runs `release-please` on every push to `main` to maintain the standing release PR. Copy to `.github/workflows/release.yml`. See `../../RELEASE_GUIDE.md`. |
| `release-please-config.example.json` | Copy to repo root as `release-please-config.json`; set `package-name`. |
| `release-please-manifest.example.json` | Copy to repo root as `.release-please-manifest.json`; tracks the current version. |

## Setup checklist

1. Copy the workflow files into `.github/workflows/` (`ci.yml`, `cd.yml`,
   `release.yml`), `dependabot.yml` directly under `.github/`, and the two
   `release-please-*.example.json` files into the repo root (renamed without
   `.example`).
2. Edit the `env:` block at the top of `ci.yml` and `cd.yml`:
   `BACKEND_DIR`, `FRONTEND_DIR`, `PYTHON_VERSION`, `NODE_VERSION`,
   `COVERAGE_THRESHOLD`, `REGISTRY`, `IMAGE_NAME_BACKEND`/`IMAGE_NAME_FRONTEND`.
3. If a repo variable `BACKEND_DIR`/`FRONTEND_DIR` doesn't exist as an Actions
   **variable** (`vars.BACKEND_DIR`), the `if:` conditions on jobs default to
   false and those jobs are skipped — either define matching repo/organization
   variables under **Settings → Secrets and variables → Actions → Variables**,
   or simplify the `if:` conditions to always run if your repo always has
   both backend and frontend.
4. **Branch protection:** under **Settings → Branches**, protect `main` and
   require the `ci.yml` status checks to pass before merging. This is what
   "pushes straight to main are blocked" depends on — the workflow alone does
   not enforce it.
5. **Registry auth:** `cd.yml` defaults to GHCR (`ghcr.io`) using the built-in
   `GITHUB_TOKEN`, which needs `packages: write` permission (already set in
   the template's job `permissions:` block). For a different registry, add
   the registry credentials as repository secrets and update the
   `docker/login-action` step.
6. Run `../../audit/run-audit.ps1` (or `.sh`) locally at least once before the
   first PR to establish a baseline verdict.
7. Edit `release-please-config.json`'s `package-name` and (optionally)
   `release-type` — see `../../RELEASE_GUIDE.md` for the Conventional Commits
   convention this depends on.

## Notes

- `security-scan` includes `pip-audit`, `npm audit --audit-level=high`,
  `bandit`, `semgrep` (OWASP Top Ten ruleset), and `gitleaks` — this mirrors
  the automated checks in `../../audit/run-audit.ps1` but runs them in CI on
  every push instead of on demand.
- `cd.yml`'s Trivy step has `exit-code: "1"`, so a `CRITICAL`/`HIGH` image
  finding **fails the job and blocks the push** — the registry never receives
  an image that failed the scan.
