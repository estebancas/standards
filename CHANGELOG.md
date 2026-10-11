# Changelog

## Unreleased

- `scripts/apply-repo-settings.sh` (apply, verify, `--checks`, `--replace-checks`).
- `docs/new-project.md`, `docs/gotchas.md` and the `new-project` skill.
- The settings script also manages merge settings: squash only, auto-merge off, delete branch on merge on.
- `docs/contract.md` has a Releases section: tag naming, additive changes within a major, and the release steps.
- `docs/contract.md` records the drift-detection design (central weekly `verify` over `repos.txt`), the adopted extra checks, and the deferred Python and Electron targets.

## v1

- Reusable workflows extracted from weekly-routine: lint, test-build, mutation, size, audit, e2e.
- `docs/contract.md`, with the required contexts in `<caller name> / <job id>` form.
- Callers pin by commit SHA; the `v1` tag is a convenience for finding it, not a ref to call.
