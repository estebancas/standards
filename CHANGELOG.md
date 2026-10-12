# Changelog

## Unreleased

- `standards` now checks itself: `ci.yml` runs actionlint, zizmor, shellcheck and gitleaks on every pull request, and `main` is protected with those four as required checks (`docs/contract.md`, "Checks on this repo").
- `apply-repo-settings.sh` uses plain if/else where shellcheck flagged `A && B || C` (no behaviour change).
- `docs/new-project.md` and the `new-project` skill mention the extra checks and CodeQL ruleset, and say what to do with a finding.

## v1.1.0

- `lint.yml` runs zizmor, actionlint and gitleaks (new optional inputs `workflow-checks` and `secret-scan`, both on by default). No required check name changes. The job now checks out the full history for gitleaks and every checkout sets `persist-credentials: false`.
- The settings script manages CodeQL default setup and a `CodeQL alerts` ruleset that blocks merges on open high or critical alerts (`--no-codeql` skips both).
- Stale action pins refreshed (`setup-node`, `upload-artifact`, `download-artifact`) and Dependabot cooldown raised to 7 days.
- Docs: `contract.md` Extra checks table and `gotchas.md` section on fixing and suppressing findings.
- `scripts/apply-repo-settings.sh` (apply, verify, `--checks`, `--replace-checks`).
- `docs/new-project.md`, `docs/gotchas.md` and the `new-project` skill.
- The settings script also manages merge settings: squash only, auto-merge off, delete branch on merge on.
- `docs/contract.md` has a Releases section: tag naming, additive changes within a major, and the release steps.
- Docs and the `new-project` skill now point at `template-pwa` (the renamed `template-web-frontend`, now a PWA with a guarded Cloudflare deploy).
- `docs/contract.md` records the drift-detection design (central weekly `verify` over `repos.txt`), the adopted extra checks, and the deferred Python and Electron targets.

## v1

- Reusable workflows extracted from weekly-routine: lint, test-build, mutation, size, audit, e2e.
- `docs/contract.md`, with the required contexts in `<caller name> / <job id>` form.
- Callers pin by commit SHA; the `v1` tag is a convenience for finding it, not a ref to call.
