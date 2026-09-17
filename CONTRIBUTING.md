# Contributing

This repo is a portable playbook, not an application — changes here affect
every project that has vendored `audit/`, `templates/`, or `pipelines/`.
Treat it like a library: backwards-incompatible changes need a clear reason
and a note in `CHANGELOG.md` (generated automatically — see below).

## Before you change anything

1. Read `README.md` (the checklist and verdict tiers), and whichever of
   `audit/README.md`, `pipelines/README.md`, `templates/README.md`,
   `docs/RELEASE_GUIDE.md`, `docs/TECH_STACK.md` covers the area you're touching.
2. If you're changing a check in `audit/run-audit.sh`, make the **same**
   change in `audit/run-audit.ps1` (and vice versa) — the two must stay in
   parity. Run both locally against a real repo (or this one) before
   committing.
3. Keep `run-audit.ps1` **ASCII-only** — no em-dashes, no literal emoji.
   Windows PowerShell 5.1 reads unmarked `.ps1` files with the system ANSI
   codepage; multi-byte characters silently corrupt parsing. `run-audit.sh`
   may use UTF-8/emoji freely.

## Commit messages

[Conventional Commits](https://www.conventionalcommits.org/) — see
`docs/RELEASE_GUIDE.md`. `fix:`/`feat:`/`feat!:` drive the automated version bump;
`docs:`/`chore:`/`ci:`/`test:`/`refactor:` do not bump the version but still
appear in the changelog.

## Before opening a PR

- Run `bash audit/run-audit.sh .` from the repo root — CI runs the same
  self-audit and will fail the build on a `CRITICAL` verdict.
- If you touched YAML under `.github/` or `pipelines/`, `actionlint`/
  `yamllint` run in CI — check them locally if you can
  (`actionlint .github/workflows/*.yml`).
- If you touched a `.sh` file, run `shellcheck` on it; for `.ps1`, run
  `Invoke-ScriptAnalyzer`.

## What not to do

- Don't silence a real finding by weakening a check's regex or its severity
  mapping — fix the underlying false positive/negative instead, and explain
  the reasoning in the PR description.
- Don't add secrets, tokens, or real customer/project data to `templates/`
  or example reports — these get copied into other people's repos.
