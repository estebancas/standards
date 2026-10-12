# New project

How to start a PWA project (TypeScript, Vite, installable and offline-capable) with all the guardrails. The `new-project` skill (`skills/new-project/`) automates steps 1 to 4. The reasons behind the traps are in `docs/gotchas.md`, and what each check guarantees is in `docs/contract.md`.

Measured on the smoke test: 126 seconds from creating the repo to a green first PR.

## Before you start

- `gh` is logged in, and you can administer the new repo (you will own it).
- `jq` is installed (the settings script needs it).
- The repo will be **public**. Branch protection on the Free plan is public-only, and the script refuses private repos.
- You have a checkout of this repo (`standards`), for the script.

## 1. Create the repo from the template

From a scratch or parent directory, not from inside another repo:

```sh
gh repo create <owner>/<name> --template estebancas/template-pwa --public --clone
cd <name>
```

## 2. Make it yours

1. `npm install`, so `package-lock.json` is yours.
2. Set `name` in `package.json`, and the title and description in `index.html`.
3. Change `@estebancas` in `.github/CODEOWNERS` if the owner differs.
4. Commit and push straight to `main`. Protection is not on yet.

`TEMPLATE.md` in the new repo has the full list, including steps for later.

## 3. Apply the repo settings

From this repo's checkout:

```sh
scripts/apply-repo-settings.sh apply  <owner>/<name>
scripts/apply-repo-settings.sh verify <owner>/<name>   # must exit 0
```

This sets branch protection with the six required checks, Actions with SHA pinning, vulnerability alerts, Dependabot security updates, secret scanning with push protection, CodeQL default setup with the `CodeQL alerts` ruleset (it blocks merging while a high or critical alert is open), and the `production` environment. See `docs/contract.md` for the exact list.

## 4. Prove it with a first PR

Open a branch (for example `chore/first-change`) with a trivial change and a PR. All six checks should go green:
`Lint / lint`, `Unit tests + build / test`, `Mutation testing / mutation`, `Bundle size / size`, `Dependency audit / audit`, `End-to-end / e2e`. The six names do not change when the extra checks are on: zizmor, actionlint and gitleaks run inside `Lint / lint`, and CodeQL reports separately.

## 4b. Add it to the drift check

In this repo, add `<owner>/<name>` as a line in `repos.txt` and open a PR. The weekly `Drift` workflow then runs `verify` on the new project (see "Drift detection" in `docs/contract.md`).

## 5. Manual follow-ups

The script and the template cannot do these:

- **Deploy.** `ci.yml` has a `Deploy to Cloudflare` job that is skipped until the repository variable `CLOUDFLARE_ACCOUNT_ID` is set, so a new project stays green. To turn it on, set the Worker `name` in `wrangler.jsonc`, replace the environment URL in `ci.yml`, add the `CLOUDFLARE_ACCOUNT_ID` variable and the `CLOUDFLARE_API_TOKEN` secret by hand, and approve the first run in the `production` environment (the script already created it, with you as the reviewer). `Deploy` is not a required check.
- **Visual baselines.** The committed ones belong to the starter counter. After the first real UI, run `npm run e2e:visual -- --update-snapshots` (needs Docker running) and commit `e2e/__screenshots__/**`.
- **Size budgets.** After the first real build, set each limit in `.size-limit.json` to the measured size plus about 10%.
- **PWA identity.** Set the manifest names and colours in `vite.config.ts`, replace `public/icon.svg`, and run `npm run generate-icons:docker` (needs Docker; macOS output differs from CI for the 64px icon). Commit what it changes in `public/`.
- **Findings.** If zizmor, actionlint, gitleaks or CodeQL flags something, fix it, or suppress it with a written reason (how is in the "Extra checks" section of `docs/gotchas.md`). A CodeQL false positive is dismissed on the Security tab.
- **Docs.** Fill in "What this is" and "Architecture" in `CLAUDE.md`.

## Keeping a project current

- When `standards` changes, Dependabot opens a PR in each project that bumps the pinned workflow SHA. Merge it when the checks are green.
- Run `scripts/apply-repo-settings.sh verify <owner>/<name>` now and then to catch drift in the GitHub settings. To change the required checks, change `docs/contract.md` and the caller job names together, then run `apply --replace-checks`.
