# Release Guide — Versioning, Changelogs, and Tagging

How releases are cut in this playbook's model: **Conventional Commits in →
automated version bump, changelog, and tag out.** No manual version editing,
no manual changelog writing, no guessing whether a change is a patch or a
feature.

---

## 1. The convention: Conventional Commits

Every commit message on the default branch (or squashed PR/MR title) follows:

```text
<type>[optional scope]: <description>

[optional body]

[optional footer(s)]
```

| Type | Triggers | Example |
| --- | --- | --- |
| `fix:` | PATCH bump (x.y.**Z**) | `fix(auth): reject expired tokens` |
| `feat:` | MINOR bump (x.**Y**.0) | `feat(api): add /export endpoint` |
| `perf:` | PATCH bump | `perf(query): add index on blade_id` |
| `feat!:` or a footer `BREAKING CHANGE: ...` | MAJOR bump (**X**.0.0) | `feat!: remove deprecated v1 endpoints` |
| `docs:`, `chore:`, `test:`, `refactor:`, `style:`, `build:`, `ci:` | No version bump, but still shown in the changelog under their own heading | `chore(deps): bump PyJWT to 2.13.0` |

Add a scope in parentheses (`fix(security): ...`) to group related changes —
release-please/semantic-release both use it to organize the changelog.

**Why this matters:** the release tool parses these prefixes to decide the
next version number and to write the changelog automatically. Get the type
right and you never have to think about "is this a 3.20.1 or a 3.21.0?"
again.

---

## 2. Pick your automation: GitHub vs GitLab

Both approaches produce the same outcome (SemVer tag + generated
`CHANGELOG.md` + release entry) from the same Conventional Commits — pick the
one matching your Git host.

### GitHub → `release-please`

Files (see `pipelines/github/`):

| File | Copy to |
| --- | --- |
| `release.yml` | `.github/workflows/release.yml` |
| `release-please-config.example.json` | repo root, as `release-please-config.json` |
| `release-please-manifest.example.json` | repo root, as `.release-please-manifest.json` |

How it works: every push to `main` runs `release-please-action`, which
maintains a standing **"release PR"** that accumulates the changelog entries
for all unreleased commits. Merging that PR is the actual release: it updates
`CHANGELOG.md`, bumps the version, and tags `vX.Y.Z`.

Edit `release-please-config.json`:

- `package-name` → your project's name.
- `release-type` → `"simple"` (version tracked only in the manifest — works
  for any project) or `"node"`/`"python"` if you want the version mirrored
  into `package.json`/`pyproject.toml` automatically (see
  [release-please's supported types](https://github.com/googleapis/release-please/blob/main/docs/customizing.md)).

### GitLab → `semantic-release`

Files (see `pipelines/gitlab/`):

| File | Copy to |
| --- | --- |
| `release-job.example.yml` | merge the `release:` job into your `.gitlab-ci.yml`; add `release` to the `stages:` list |
| `.releaserc.example.json` | repo root, as `.releaserc.json` |

How it works: on every pipeline run on the default branch, the `release` job
installs `semantic-release` and runs it. It computes the next version from
commits since the last tag, updates `CHANGELOG.md`, creates the git tag, and
publishes a **GitLab Release** via the `@semantic-release/gitlab` plugin —
all in the same pipeline run (no separate PR step, unlike release-please).

Requires a CI/CD variable `GITLAB_TOKEN` (Settings → CI/CD → Variables) with
API scope, so semantic-release can push the changelog commit and create the
release/tag.

> Why different tools per platform? `release-please` is GitHub-native (it
> manages the release PR via the GitHub API). `semantic-release` is
> platform-agnostic and has an official GitLab plugin, making it the more
> natural fit there. Both read the same Conventional Commits convention, so
> switching platforms later doesn't change how anyone writes commit messages.

---

## 3. Release checklist

Before merging the release PR (GitHub) or letting the `release` job run
(GitLab), confirm:

- [ ] `audit/run-audit.ps1` (or `.sh`) verdict is **LOW RISK** or **ACCEPTED
      RISK** — never release on a **CRITICAL** verdict (see `PLAYBOOK.md` §3).
- [ ] CI is green: lint, build, test, security-scan, quality-gate all passed
      on the commit being released.
- [ ] The CD/deploy stage's Trivy image scan passed (no unpushed image should
      ever reach a tag).
- [ ] If this release touches a security finding, update the project's own
      `security/CYB_report_*.md` / `security/BIA_ACP_*.md` (see
      `../templates/README.md`) — don't rely solely on the commit message.

## 4. What "release" produces

| Artifact | Where it comes from |
| --- | --- |
| Git tag `vX.Y.Z` | release-please / semantic-release, from the commit history |
| `CHANGELOG.md` | Auto-generated, grouped by type (Features / Bug Fixes / Performance / …) |
| GitHub Release / GitLab Release entry | Same tools, optional but recommended — gives a browsable release history |
| Version string in the running app (optional) | Wire your app's "About" page or footer to read the tag/package version at build time, so users can see what they're running — see `frontend/src/appInfo.ts`-style pattern if applicable to your stack |

## 5. Common pitfalls

- **Mixing commit styles.** If some commits don't follow the convention, the
  tool can't classify them — they'll be silently omitted from the changelog
  (or, worse, misclassified). Enforce this with a `commitlint` check in CI if
  the team needs it (not included here — add a `lint-commits` job calling
  `commitlint` against `@commitlint/config-conventional` if desired).
- **Squash-merging PRs/MRs with a generic title** ("Merge branch...") loses
  the convention. Configure your squash-merge commit message to reuse the
  PR/MR title, and make *that* title follow Conventional Commits.
- **Releasing with open CRITICAL findings.** The audit verdict is a gate, not
  a suggestion — a CRITICAL verdict means the release step should be blocked
  in CI (wire `run-audit`'s exit code into a required check) until fixed.
