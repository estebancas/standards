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
- Merge settings: squash merge on, merge commits off, rebase merge off, auto-merge off, delete
  branch on merge on. History is one commit per pull request.
- CodeQL default setup, and the `CodeQL alerts` ruleset that blocks merging while a high or
  critical CodeQL alert is open (see Extra checks). `--no-codeql` skips both.
- A `production` environment: owner as required reviewer, self-review allowed, deployment branch
  policy for the default branch.

Not managed, and preserved when already set (the protection endpoint replaces the whole object, so
the script reads current state and sends it back): code-owner review, stale-review dismissal,
signed commits, linear history, conversation resolution, branch lock, push restrictions, and the
"update branch" button.

`verify` is read-only and exits 1 on drift. The script refuses private repos: branch protection on
the Free plan is public-only.

## Releases

Consumers pin a commit SHA, and Dependabot proposes a new one when a newer tag exists. A change
reaches a project only when its owner merges that bump, after the project's own checks pass.

- **Tags** are `vMAJOR.MINOR.PATCH`, annotated, and never moved or deleted. The existing `v1`
  stays as it is, and `v1.0.0` points at the same commit so Dependabot reads a `# v1` caller as
  version 1.0.0. Each tag also gets a GitHub release.
- **A release reaches consumers after their Dependabot cooldown** (7 days in the template), so
  expect the bump PRs a week after the tag.
- **Within a major, changes are additive.** New inputs are optional. Existing inputs, job ids and
  caller job names do not change, because renaming either changes a required context. A change
  that breaks this needs a new major tag and a migration note in `CHANGELOG.md`.
- **Patch** for fixes with no visible change, **minor** for new optional inputs or new checks
  that sit inside an existing job, **major** for anything consumers must edit.
- **To release:** rename `Unreleased` in `CHANGELOG.md` to the new version, commit, tag that
  commit, and push the tag. Then consumers get a Dependabot PR.
- Docs, the settings script and the skill can change on `main` without a tag. Only workflow
  changes need a release. Every change still goes through a pull request (see Checks on this
  repo).

## Drift detection

`apply-repo-settings.sh verify` is run centrally, not in each project. A weekly scheduled
workflow in this repo reads `repos.txt` (one `owner/repo` per line, kept by hand) and runs
`verify` on each. A clean run is silent. Drift fails the job, and GitHub emails the owner.

- Only repos in `repos.txt` are watched. Add a repo when it adopts the standards; the
  `new-project` skill does this as a step. Private repos stay off the list, because `verify`
  refuses them.
- The default `GITHUB_TOKEN` cannot read branch protection, so the workflow uses one
  fine-grained token stored as a secret here, with read-only Administration, Environments and
  Metadata access. It expires within a year and is rotated by hand.
- Projects carry no drift workflow and no extra secret.

## Extra checks

actionlint, zizmor, CodeQL and gitleaks are adopted (decided 2026-10-11). The six required
checks stay as they are. Making any of them a required check needs a contract change here and a
`--replace-checks` migration note.

| Tool | Where it runs | What it guarantees | Turn off |
| --- | --- | --- | --- |
| zizmor (default persona) | `Lint / lint` | Workflow security audits pass: no template injection, no unpinned actions, no over-broad permissions, no credential persistence, no cache poisoning in publishing jobs. | `workflow-checks: false` |
| actionlint | `Lint / lint` | Workflow syntax, expressions and shellcheck on `run:` blocks pass. | `workflow-checks: false` |
| gitleaks | `Lint / lint` | No secret in the full git history. | `secret-scan: false` |
| CodeQL | GitHub default setup | No open high or critical alert on the default branch, enforced by a ruleset. | `--no-codeql` on the settings script |

- **The first three sit inside `Lint / lint`**, so no required context is added. `workflow-checks`
  and `secret-scan` are optional boolean inputs of `lint.yml`, both `true` by default, and the
  lint job checks out the full history for gitleaks.
- **CodeQL is not a required status check.** The settings script turns on default setup (GitHub
  picks the languages) and a ruleset named `CodeQL alerts` with one `code_scanning` rule at
  `high_or_higher` / `errors` on the default branch and no bypass actors. `verify` reports both.
- **Findings are fixed or suppressed with a written reason.** How to suppress each tool is in
  `docs/gotchas.md`.
- **The tools are pinned.** zizmor by action SHA and `version`, actionlint and gitleaks by release
  URL and sha256 in `lint.yml`. A new version is a `lint.yml` change and a new release.

## Checks on this repo

`standards` checks itself with `.github/workflows/ci.yml` on every pull request and push to
`main`. The four job names are its required contexts, set with
`apply-repo-settings.sh apply estebancas/standards --no-environment --checks "actionlint,zizmor,shellcheck,gitleaks"`.
They are not part of the consumer six above.

| Context | What it checks |
| --- | --- |
| `actionlint` | The reusable workflows and `ci.yml`: syntax, expressions, shellcheck on `run:` blocks. |
| `zizmor` | The same files, default persona, with the online audits. |
| `shellcheck` | `scripts/apply-repo-settings.sh` (it targets Bash 3.2). |
| `gitleaks` | The history of the checked-out commit. |

- **`main` needs a pull request**, with all four checks green and the branch up to date. The
  `CodeQL alerts` ruleset has no bypass, so even the admin cannot push straight to `main`.
- **The tools are pinned** the same way as in `lint.yml`: release URL and sha256, or action SHA.
- There is no dependency audit, because the repo has no npm dependencies.

## Deferred

Contract targets for Python and Electron (make vs just, check shape) are decided when the first
project of that kind starts. The Python side is piloted with workout-coach.
