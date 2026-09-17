# Tech Stack Guide — Base Stack & Adapting to Others

This playbook's audit and pipeline templates are **tuned** for a specific
default stack, but built to be adaptable. This guide states the recommended
default, and how to retarget the same guarantees (audit checklist, CI/CD
stages, release automation) onto a different stack.

---

## 1. Recommended base stack

| Layer | Choice | Why |
| --- | --- | --- |
| Backend | **Python — FastAPI** (default) or **Django** (if you need an admin panel, ORM-heavy CRUD, or built-in auth/user management out of the box) | FastAPI: async-first, typed (Pydantic), minimal, best for APIs consumed by a separate frontend. Django: batteries-included, better when the backend also needs server-rendered views, an admin UI, or a mature migrations/ORM story. |
| Frontend | **React** (with **Vite** for the dev server/bundler, **TypeScript**) | Widest ecosystem, easiest to hire for, pairs well with either backend choice via a REST/JSON API. |
| Database | PostgreSQL (or the managed equivalent — Azure SQL/RDS) | Parameterized-query support, mature tooling, works identically with FastAPI (SQLAlchemy/asyncpg) or Django (built-in ORM). |
| Containerization | Docker, one `Dockerfile` per service (`backend/Dockerfile`, `frontend/Dockerfile`), non-root `USER` | Matches every check in `audit/run-audit.ps1` (F-09) and both CI/CD templates as-is. |
| CI/CD | `pipelines/github/` or `pipelines/gitlab/` (see `pipelines/README.md`) | Already parameterized for `backend/` + `frontend/` directory layout. |
| Release automation | `release-please` (GitHub) / `semantic-release` (GitLab) | See `RELEASE_GUIDE.md`. |

This is the stack the audit script and both pipeline templates are
pre-tuned for: `BACKEND_DIR=backend` (Python, `requirements*.txt`,
`Depends(...)` auth checks) and `FRONTEND_DIR=frontend` (Node,
`package.json`, JSX/TSX XSS-sink checks). Use this stack when starting a new
project and you get the whole playbook working with **zero changes**.

### FastAPI vs Django — quick decision guide

| Need | Pick |
| --- | --- |
| Pure JSON API, async I/O, OpenAPI docs auto-generated | FastAPI |
| Server-rendered admin/back-office screens, built-in user model & permissions | Django (+ Django REST Framework if it also needs an API) |
| Small team, want the least boilerplate | FastAPI |
| Heavy relational data model with many CRUD screens | Django |

---

## 2. Adapting the playbook to a different stack

The **audit checklist and CI/CD stage structure stay the same** regardless of
language/framework (lint → build → test → security scan → quality gate →
image scan → push). What changes is *which tool* implements each stage.
Swap the row for your stack:

| Concern | Python (FastAPI/Django) | Node/Express | Java/Spring Boot | Go |
| --- | --- | --- | --- | --- |
| Lint | `ruff` | `eslint` | `checkstyle`/`spotbugs` | `golangci-lint` |
| Dependency file | `requirements*.txt` / `pyproject.toml` | `package.json` | `pom.xml`/`build.gradle` | `go.mod` |
| Dependency CVE scan | `pip-audit` | `npm audit` | `mvn dependency-check` / OWASP Dependency-Check | `govulncheck` |
| SAST | `bandit` + `semgrep` | `semgrep` (JS/TS ruleset) | `spotbugs` + `semgrep` | `gosec` |
| Test runner | `pytest` (+ `pytest-cov`) | `jest`/`vitest` | `mvn test` (JaCoCo for coverage) | `go test -cover` |
| Auth pattern the audit looks for | `Depends(...)`, `Security(...)`, `HTTPBearer`, `OAuth2` | `passport.*`, `verifyToken`, middleware | Spring Security annotations (`@PreAuthorize`, filters) | middleware func wrapping `http.Handler` |
| Container base image | `python:3.12-slim` | `node:22-alpine` | `eclipse-temurin:21-jre` | `golang:1.23-alpine` (builder) → `scratch`/`distroless` (runtime) |

### What you need to change per file

- **`audit/run-audit.ps1` / `.sh`:** the F-01 (auth dependency) and G-02 (XSS
  sink) checks use language-specific regex patterns. For a non-Python,
  non-JS backend, add an equivalent pattern block (copy the Python block,
  swap the file filter and the `Depends(...)`-style keywords for your
  framework's auth decorator/middleware convention).
- **`pipelines/github/ci.yml` / `pipelines/gitlab/.gitlab-ci.yml`:** replace
  the `lint-backend`/`build-backend`/`test-backend` steps' toolchain setup
  (`setup-python` → `setup-java`/`setup-go`) and commands (`pip install` →
  `mvn install`/`go build`) — the job names, stage order, and `needs:`/
  dependency graph don't need to change.
  the ecosystem for `dependabot.yml` (`pip`/`npm` → `maven`/`gomod`) or
  Renovate presets for `renovate.json`.
- **`RELEASE_GUIDE.md` workflow:** unaffected — Conventional Commits +
  release-please/semantic-release work identically regardless of language.

### What never changes

- The **verdict tiers** (LOW RISK / ACCEPTED RISK / CRITICAL) and their
  severity mapping philosophy (auth bypass and injection are always
  Critical; unpinned deps are always Low).
- The **stage order**: lint → build → test → security → quality gate →
  image scan → push (see `pipelines/README.md`'s diagram).
- The **CYB report / BIA-ACP template structure** (`templates/`) — these are
  organizational documents, not code-specific.

---

## 3. Minimal file layout the tooling expects

Whatever stack you pick, keep this shape so the audit script and pipelines
work without extra configuration:

```text
your-repo/
├── backend/            (or set BACKEND_DIR="" if there is none)
│   ├── Dockerfile
│   ├── requirements.txt / pom.xml / go.mod / ...
│   └── <source>
├── frontend/            (or set FRONTEND_DIR="" if there is none)
│   ├── Dockerfile
│   ├── package.json
│   └── src/
├── .github/workflows/     (if GitHub)  — see pipelines/github/
├── .gitlab-ci.yml           (if GitLab) — see pipelines/gitlab/
├── security/                 — CYB/BIA reports for this project (see templates/)
└── CHANGELOG.md                — generated by release automation, don't hand-edit
```
