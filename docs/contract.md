# Contract

The single source of truth for what every project exposes and what CI requires. The reusable
workflows in `.github/workflows/` and (from M2) `scripts/apply-repo-settings.sh` both follow this
file. Change it here first.

## Commands

Every project exposes the same six commands. JS projects implement them as npm scripts. A check
that makes no sense for a stack is a no-op command, so the required-check list never varies.

| Command | npm script | Must guarantee |
| --- | --- | --- |
| lint | `lint` | Static analysis passes with zero errors. TypeScript projects run the typecheck (`tsc --noEmit`) inside this command, so the check names do not change. |
| test | `test`, `build` | The build succeeds and unit + integration tests pass with the coverage gate (90% lines, branches, functions, statements). The build output is uploaded as the `dist` artifact. |
| mutate | `mutate` | Mutation score stays above the break threshold (85; high 90, low 80). |
| size | `size` | Built assets stay inside the committed budgets (measured, then +10%). |
| audit | _(none: `npm audit` directly)_ | No high-severity advisory in production dependencies; package signatures verify; new PR dependencies pass dependency-review. |
| e2e | `e2e` | Playwright specs pass, including accessibility and visual regression, inside the pinned Playwright image. A missing Playwright config fails the check. |

## Required checks

Branch protection requires exactly these six, on the default branch, with `strict: true`:

| Required context | Reusable workflow | Caller job `name` |
| --- | --- | --- |
| `Lint / lint` | `lint.yml` | `Lint` |
| `Unit tests + build / test` | `test-build.yml` | `Unit tests + build` |
| `Mutation testing / mutation` | `mutation.yml` | `Mutation testing` |
| `Bundle size / size` | `size.yml` | `Bundle size` |
| `Dependency audit / audit` | `audit.yml` | `Dependency audit` |
| `End-to-end / e2e` | `e2e.yml` | `End-to-end` |

GitHub reports a reusable-workflow job as `<caller job name> / <called job id>`, so the contexts
are not the plain names weekly-routine requires today (`Lint`, `Unit tests + build`, ...). The
caller job `name` values above and the job ids in the reusable workflows are therefore part of
the contract: renaming either changes the required context. Confirmed on a spike repo for
`Lint / lint` and `Unit tests + build / test`; the other four follow the same rule from their job
ids and are confirmed when weekly-routine is converted (M3).

## Caller rules

- `size` and `e2e` need `test` in the caller (`needs: test-build`), because they download its
  `dist` artifact.
- Callers set `permissions: contents: read`. No check needs a secret.
- Callers pin the reusable workflows by commit SHA, never by branch or tag.
- Deploy is not part of the contract. It stays in the project's own `ci.yml` and is not a
  required check.

## Settings the repo must have

`scripts/apply-repo-settings.sh apply|verify <owner/repo>` manages exactly these, and nothing else:

- Branch protection on the default branch: strict required checks (the six contexts above, unioned
  with any existing ones), a required pull request with 0 approvals, enforce_admins off, force
  pushes and deletions off.
- Actions enabled, `allowed_actions: all`, `sha_pinning_required`. The script refuses to turn
  pinning on while a workflow still uses an unpinned action.
- Vulnerability alerts, Dependabot security updates, secret scanning with push protection.
- A `production` environment: owner as required reviewer, self-review allowed, deployment branch
  policy for the default branch.

Not managed, and preserved when already set (the protection endpoint replaces the whole object, so
the script reads current state and sends it back): code-owner review, stale-review dismissal,
signed commits, linear history, conversation resolution, branch lock, push restrictions, and
merge-button settings.

`verify` is read-only and exits 1 on drift. The script refuses private repos: branch protection on
the Free plan is public-only.
