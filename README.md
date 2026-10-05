# standards

Shared CI and repo rules for personal projects. Derived from `weekly-routine`, the reference
implementation. See `docs/contract.md` for what every project exposes and what CI requires.

## Three layers

1. **Template repo** (`template-web-frontend`, separate repo): files copied once when a project
   is created.
2. **Reusable workflows** (this repo, `.github/workflows/`): CI logic that keeps improving.
   Projects call them pinned by commit SHA, and Dependabot proposes bumps as PRs.
3. **Settings script** (`scripts/apply-repo-settings.sh`): branch protection and other
   GitHub-only settings, with `apply` and `verify` modes. Needs `gh` (admin on the repo) and `jq`.

```sh
scripts/apply-repo-settings.sh verify owner/repo   # read-only, exits 1 on drift
scripts/apply-repo-settings.sh apply  owner/repo   # idempotent
# A repo that has no CI yet, or still uses the old plain check names:
scripts/apply-repo-settings.sh verify owner/repo --checks "Lint,Unit tests + build"
```

## Reusable workflows

| Workflow | Check | Notable inputs |
| --- | --- | --- |
| `lint.yml` | Lint | `generated-assets-command`, `generated-assets-path`, `generated-assets-required-files` |
| `test-build.yml` | Unit tests + build | `build-command`, `test-command`, `dist-path` |
| `mutation.yml` | Mutation testing | `mutate-command`, `report-path` |
| `size.yml` | Bundle size | `size-command`, `dist-path` |
| `audit.yml` | Dependency audit | `audit-dev` |
| `e2e.yml` | End-to-end | `container-image` (required), `e2e-command` |

Every workflow takes `node-version-file` (default `.nvmrc`), needs only `contents: read`, and
uses no secrets. `size` and `e2e` download the `dist` artifact from `test-build`, so callers
must run them after it.

## Rules for this repo

- Every action is pinned by commit SHA with the version in a trailing comment.
- Dependabot bumps the actions weekly. Consumers move to a new version through their own PR.
- A bad change here breaks every consumer, so changes land by PR and callers pin a tagged SHA.
