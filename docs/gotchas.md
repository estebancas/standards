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
- **Admins can push to a protected `main`** while `enforce_admins` is off. That is deliberate for a solo owner, and it is how the first commit after the settings are applied still goes in.

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

## TypeScript and Dependabot

- **Keep TypeScript below 6.1** while `typescript-eslint`'s peer range stops there (TypeScript 7 already exists). A newer TypeScript makes `npm install` fail with ERESOLVE while `npm ci` still passes. The template's Dependabot ignores TypeScript majors and minors.
- **TypeScript 6 no longer auto-includes `@types/*`**, so `tsconfig.json` lists `types` explicitly (`vite/client`, `node`).
- **`cooldown` and `ignore` wildcard syntax are valid** in `dependabot.yml` (`@vitest/*`, `@stryker-mutator/*`).
- **Ignore majors of the coupled toolchain** (`vite`, `vitest`, `@vitest/*`, `@stryker-mutator/*`, `@playwright/test`). They are tied to the pinned Playwright tag and the Stryker patch, so upgrade them by hand.
- **PWA-only packages** (`vite-plugin-pwa`, `@vite-pwa/assets-generator`) belong in the ignore list only for PWA projects. `@vite-pwa/assets-generator` 2.x breaks `npm install` against `vite-plugin-pwa`'s `^1.0.0` peer range.
- **npm 11 prints an `allow-scripts` warning** for packages with install scripts, such as `fsevents`. It is only a warning today and may become an error later.

## Shell and `gh`

- **Scripts run under bash, not zsh.** zsh does not word-split unquoted variables. The settings script targets bash 3.2, the macOS default.
- **Wrapped pastes break multi-line `gh api --input -` commands.** Put the command in a script file.
- **`gh repo create --clone` clones into the current directory.** Run it from a scratch or parent directory, never from inside another repo.
- **`gh api` exit codes carry state.** `vulnerability-alerts` answers 204 when on and 404 when off, so the script tests the exit status instead of parsing output.
- **`gh repo delete` needs the `delete_repo` scope.** Add it only when needed (`gh auth refresh -h github.com -s delete_repo`) and remove it afterwards (`--remove-scopes delete_repo`).
