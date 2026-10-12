# Gotchas

Lessons from building the reference (`weekly-routine`), the settings script and the template. Each one says what goes wrong and what to do. `docs/contract.md` is the source of truth for check names and settings.

## GitHub settings

- **The branch protection PUT replaces the whole object.** Restate every setting you care about or it is wiped. `apply-repo-settings.sh` reads the current protection and sends it back with its managed fields changed. Signed commits, which have their own endpoint, survived the PUT in testing.
- **Required contexts are `<caller job name> / <job id>`.** A reusable-workflow job is reported as `Lint / lint`, not `Lint`. Renaming the caller job or the job id in the reusable workflow changes the required context. When migrating names, use `--replace-checks`, because the default keeps the old ones required and blocks PRs forever.
- **A context can be required before it has run** when you set it through the API (the settings script does), but only the names a workflow really produces will ever turn green. Check the real names on a first PR.
- **`dependency-review-action` fails until the dependency graph is on.** The script enables vulnerability alerts (`PUT /repos/{o}/{r}/vulnerability-alerts`) before anything else.
- **Turn `sha_pinning_required` on only after every workflow is SHA-pinned.** A tag-pinned open PR (Dependabot's, for example) fails until it is rebased. The script refuses to enable it while an unpinned `uses:` exists and prints the lines.
- **Strict required checks make other open PRs "behind"** after every merge, so expect rebases.
- **Branch protection on the Free plan is public-only**, and it is the same for a personal account or an organization. The script refuses private repos.
- **Org rulesets are not enforced on a Free organization**, so an org is not worth it only for Dependabot defaults. Settings stay per repo, through the script.
- **Admins can push to a protected `main`** while `enforce_admins` is off. That is deliberate for a solo owner, and it is how the first commit after the settings are applied still goes in. The exception is a repo with the `CodeQL alerts` ruleset: it has no bypass and a code scanning rule cannot be met by a direct push, so there every change goes through a pull request. To push directly anyway, delete the ruleset first and run `apply` afterwards to restore it.

## CI

- **`npm audit` needs no install**, because it reads the lockfile. `npm audit signatures` verifies installed packages, so it needs `npm ci` first.
- **Dev-only advisories.** `braces` (GHSA-vfj7-8cjw-p6xm, no fix as of 2026-10-04) arrives only through `patch-package`, a postinstall tool, so the blocking audit uses `--omit=dev`. The optional non-blocking full audit (`audit-dev: true`) keeps the findings visible. Drop both once `braces` is fixed.
- **The `qs` override** in `package.json` (`"qs": "^6.16.0"`) exists for a security fix that would otherwise show up as a moderate advisory.
- **The Playwright image tag must equal the installed `@playwright/test` version**, in the workflow's `container-image` and in the `e2e:visual` script. Bump all three together.
- **Visual baselines must come from that image**, so generate them in Docker (`npm run e2e:visual -- --update-snapshots`). The visual specs skip outside Linux so `npm run e2e` stays green on macOS.
- **Stryker and Vitest 5.** `@stryker-mutator/vitest-runner` 10.0.0 does not work with Vitest 5 (stryker-js#6210: Vitest joins test names with `' > '`). The template carries a `patch-package` patch that backports the open fix (#6220). Check whether a release has fixed it before copying the patch into a new project.
- **Stryker needs a flat Vitest config.** The runner crashes with circular JSON when given `test.projects`, hence `vitest.stryker.config.ts`. Use `coverageAnalysis: perTest` with it.
- **A mutant that guards an async DOM event can crash the runner.** weekly-routine accepts one (the `if (onToggle)` guard in `Details.js`) and covers it with a dedicated unit test.
- **A mutation break threshold only holds if tests hit the boundaries.** Even a tiny app needed tests at both ends of every range and for disabled-button states.
- **The e2e workflow does not skip when there is no Playwright config.** A missing config fails the check, so a project cannot pass silently without e2e.
- **Visual baselines and size budgets cannot be templated.** After the first real UI, regenerate the baselines and re-measure the budgets (measured size plus about 10%).
- **The icon and generated-assets check must include untracked files** (`git status --porcelain`), not only diffs, or a new generated file passes unnoticed.
- **Generated icons must come from Linux.** `pwa-assets-generator` writes a slightly different `pwa-64x64.png` on macOS than on the CI runner, so the Lint generated-assets check fails on icons committed from a Mac. Regenerate with `npm run generate-icons:docker` (Linux x64) in the template.

## TypeScript and Dependabot

- **Keep TypeScript below 6.1** while `typescript-eslint`'s peer range stops there (TypeScript 7 already exists). A newer TypeScript makes `npm install` fail with ERESOLVE while `npm ci` still passes. The template's Dependabot ignores TypeScript majors and minors.
  - **Trigger to revisit:** `npm view typescript-eslint peerDependencies.typescript` includes the TypeScript version you want. Dependabot will not tell you, because the ignore rule hides every TypeScript bump. Last checked 2026-10-11: TypeScript 7.0.2 is out, `typescript-eslint` 8.71.1 still stops below 6.1.0, and the template is on `~6.0.3`.
- **TypeScript 6 no longer auto-includes `@types/*`**, so `tsconfig.json` lists `types` explicitly (`vite/client`, `node`).
- **`cooldown` and `ignore` wildcard syntax are valid** in `dependabot.yml` (`@vitest/*`, `@stryker-mutator/*`).
- **Dependabot reads a standards release as a normal version.** Checked 2026-10-11 with the Dependabot CLI: a caller pinned `<sha> # v1` on the commit that also carries the `v1.0.0` tag is read as `1.0.0`, and `v1.1.0` is found as the newer release. Adding `v1.0.0` on the same commit as `v1` is what makes that work, so keep both tags. A GitHub release for each tag is published too, though Dependabot did not need it.
- **A new standards release reaches consumers only after the cooldown.** Dependabot holds a version back until it is `cooldown` days old (7 in the template and weekly-routine). Even with no `cooldown` configured, the updater applied 3 days in the CLI run. A release made on day 0 therefore opens no PR for a week, and the log line is `All versions are in cooldown period`.
- **The dependency name of a reusable workflow includes its path** (`estebancas/standards/.github/workflows/lint.yml`), and Dependabot opens one update per workflow file, grouped by `actions-minor-patch` when minor or patch.
- **See why Dependabot did not open a PR** by running the CLI: `docker context inspect` gives the socket for `DOCKER_HOST`, then `dependabot update github_actions <owner/repo>` (release binary from `dependabot/cli`, no token needed for a public repo). The workflow-run view of a Dependabot job has no log in the API.
- **Ignore majors of the coupled toolchain** (`vite`, `vitest`, `@vitest/*`, `@stryker-mutator/*`, `@playwright/test`). They are tied to the pinned Playwright tag and the Stryker patch, so upgrade them by hand.
- **PWA-only packages** (`vite-plugin-pwa`, `@vite-pwa/assets-generator`) belong in the ignore list only for PWA projects. `@vite-pwa/assets-generator` 2.x breaks `npm install` against `vite-plugin-pwa`'s `^1.0.0` peer range.
- **npm 12 turns dependency install scripts off by default.** npm 11 only prints an `allow-scripts` warning (`npm warn allow-scripts ... not yet covered by allowScripts`); npm 12 completes the install but skips the scripts of anything not approved. Approve each package that needs its script with `npm approve-scripts <pkg>`, which writes `allowScripts` into `package.json`, and commit it. The template approves `fsevents` (macOS file watcher; Linux CI does not install it). Entries are pinned to an exact version (`fsevents@2.3.3`), so a Dependabot bump of an approved package makes the warning come back until the entry is updated. Review any new package that needs approval; do not use `--all` or `dangerously-allow-all-scripts`.

## Extra checks (zizmor, actionlint, gitleaks, CodeQL)

Fix a finding when you can. Suppress it only with a reason written next to the suppression.

- **zizmor:** add `# zizmor: ignore[<rule>]` at the end of the flagged line, with a comment above saying why. Example: the `unpinned-images` ignore on the e2e container in `e2e.yml`. Run it locally with `uvx zizmor@1.30.1 .`, and with `GH_TOKEN=$(gh auth token)` for the online audits CI also runs.
- **actionlint:** put `paths:` ignores or `ignore:` regexes in `.github/actionlint.yaml`, each with a comment. Local run: `docker run --rm -v "$PWD":/repo -w /repo rhysd/actionlint:1.7.12`.
- **gitleaks:** add the finding's fingerprint to `.gitleaksignore`, on its own line under a `#` comment saying why it is not a secret. A real secret is rotated first, because it stays in the history.
- **CodeQL:** dismiss the alert on the Security tab (false positive, used in tests, or won't fix) and write the reason. The ruleset has no bypass actors, so dismissing is the way past a false positive.
- **zizmor's online audits flag stale version comments.** `ref-version-mismatch` fires when `# v7` no longer matches the commit the tag points to. Bump the SHA to the tag's current commit (what Dependabot proposes), or fix the comment.
- **zizmor `cache-poisoning` fires on a deploy job** that restores a cache. In publishing jobs use `package-manager-cache: false` on `actions/setup-node` instead of `cache: npm`.
- **Every `actions/checkout` needs `persist-credentials: false`** unless the job pushes. zizmor's `artipacked` audit flags it otherwise.
- **zizmor wants a Dependabot `cooldown` of at least 7 days.** Both the template and standards use `default-days: 7`.
- **The scans run even when an earlier step fails** (`!cancelled()`), so one run lists every problem, not only the first.
- **gitleaks scans the whole history of the checked-out commit** (`--log-opts=HEAD`), so a secret removed in a later commit still fails until it is in `.gitleaksignore`. The checkout uses `fetch-depth: 0` for this. Without `--log-opts` gitleaks scans every fetched branch, and a leak on one unmerged branch fails every other PR.
- **GitHub push protection blocks well-known secret formats** (AWS keys, for example) before CI runs, so a gitleaks test needs a generic `api_key = "..."` string.
- **CodeQL default setup turns on asynchronously.** `apply` waits up to a minute for it to report `configured`.

## Shell and `gh`

- **Scripts run under bash, not zsh.** zsh does not word-split unquoted variables. The settings script targets bash 3.2, the macOS default.
- **Wrapped pastes break multi-line `gh api --input -` commands.** Put the command in a script file.
- **`gh repo create --clone` clones into the current directory.** Run it from a scratch or parent directory, never from inside another repo.
- **`gh api` exit codes carry state.** `vulnerability-alerts` answers 204 when on and 404 when off, so the script tests the exit status instead of parsing output.
- **`gh repo delete` needs the `delete_repo` scope.** Add it only when needed (`gh auth refresh -h github.com -s delete_repo`) and remove it afterwards (`--remove-scopes delete_repo`).
