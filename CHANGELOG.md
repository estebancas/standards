# Changelog

## Unreleased

- `scripts/apply-repo-settings.sh` (apply, verify, `--checks`, `--replace-checks`).
- `docs/new-project.md`, `docs/gotchas.md` and the `new-project` skill.

## v1

- Reusable workflows extracted from weekly-routine: lint, test-build, mutation, size, audit, e2e.
- `docs/contract.md`, with the required contexts in `<caller name> / <job id>` form.
- Callers pin by commit SHA; the `v1` tag is a convenience for finding it, not a ref to call.
