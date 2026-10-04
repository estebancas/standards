# Contract

The single source of truth for what every project exposes and what CI requires. The reusable
workflows in `.github/workflows/` and (from M2) `scripts/apply-repo-settings.sh` both follow this
file. Change it here first.

## Commands

Every project exposes the same six commands. JS projects implement them as npm scripts. A check
that makes no sense for a stack is a no-op command, so the required-check list never varies.

| Command | npm script | Must guarantee |
| --- | --- | --- |
| lint | `lint` | Static analysis passes with zero errors. |
| test | `test`, `build` | The build succeeds and unit + integration tests pass with the coverage gate (90% lines, branches, functions, statements). The build output is uploaded as the `dist` artifact. |
| mutate | `mutate` | Mutation score stays above the break threshold (85; high 90, low 80). |
| size | `size` | Built assets stay inside the committed budgets (measured, then +10%). |
| audit | _(none: `npm audit` directly)_ | No high-severity advisory in production dependencies; package signatures verify; new PR dependencies pass dependency-review. |
| e2e | `e2e` | Playwright specs pass, including accessibility and visual regression, inside the pinned Playwright image. A missing Playwright config fails the check. |

## Required checks

Branch protection requires exactly these six, on the default branch, with `strict: true`:

| Check | Reusable workflow | Caller job `name` |
| --- | --- | --- |
| Lint | `lint.yml` | `Lint` |
| Unit tests + build | `test-build.yml` | `Unit tests + build` |
| Mutation testing | `mutation.yml` | `Mutation testing` |
| Bundle size | `size.yml` | `Bundle size` |
| Dependency audit | `audit.yml` | `Dependency audit` |
| End-to-end | `e2e.yml` | `End-to-end` |

**Context strings are unverified.** GitHub reports a reusable-workflow job as
`<caller job name> / <called job id>`, for example `Lint / lint`, not plain `Lint`. weekly-routine
requires the plain names today. The M1 spike confirms the real strings on a first run, and this
table is then updated with the exact required contexts. Until then, treat the left column as the
check's identity and the contexts as TBD.

## Caller rules

- `size` and `e2e` need `test` in the caller (`needs: test-build`), because they download its
  `dist` artifact.
- Callers set `permissions: contents: read`. No check needs a secret.
- Callers pin the reusable workflows by commit SHA, never by branch or tag.
- Deploy is not part of the contract. It stays in the project's own `ci.yml` and is not a
  required check.

## Settings the repo must have (applied by the M2 script)

Branch protection on the default branch (strict, the six checks, PR required with 0 approvals,
enforce_admins off, force pushes and deletions off), Actions with `sha_pinning_required`,
vulnerability alerts, Dependabot security updates, secret scanning with push protection, and a
`production` environment (owner as reviewer, `main` only).
