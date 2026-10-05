# New project

How to start a frontend project with all the guardrails. The `new-project` skill (`skills/new-project/`) automates steps 1 to 4. The reasons behind the traps are in `docs/gotchas.md`, and what each check guarantees is in `docs/contract.md`.

Measured on the smoke test: 126 seconds from creating the repo to a green first PR.

## Before you start

- `gh` is logged in, and you can administer the new repo (you will own it).
- `jq` is installed (the settings script needs it).
- The repo will be **public**. Branch protection on the Free plan is public-only, and the script refuses private repos.
- You have a checkout of this repo (`standards`), for the script.

## 1. Create the repo from the template

From a scratch or parent directory, not from inside another repo:

```sh
gh repo create <owner>/<name> --template estebancas/template-web-frontend --public --clone
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

This sets branch protection with the six required checks, Actions with SHA pinning, vulnerability alerts, Dependabot security updates, secret scanning with push protection, and the `production` environment. See `docs/contract.md` for the exact list.

## 4. Prove it with a first PR

Open a branch (for example `chore/first-change`) with a trivial change and a PR. All six checks should go green:
`Lint / lint`, `Unit tests + build / test`, `Mutation testing / mutation`, `Bundle size / size`, `Dependency audit / audit`, `End-to-end / e2e`.

## 5. Manual follow-ups

The script and the template cannot do these:

- **Deploy.** `ci.yml` has a placeholder `Deploy` job that only echoes. Replace it with a real deploy. For Cloudflare, copy `wrangler.jsonc` and the deploy job from `weekly-routine`, and add `environment: production` (the script already created it, with you as the reviewer). Set `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` as repository secrets by hand. `Deploy` is not a required check.
- **Visual baselines.** The committed ones belong to the starter counter. After the first real UI, run `npm run e2e:visual -- --update-snapshots` (needs Docker running) and commit `e2e/__screenshots__/**`.
- **Size budgets.** After the first real build, set each limit in `.size-limit.json` to the measured size plus about 10%.
- **Optional PWA.** Not in the template. Follow `weekly-routine`.
- **Docs.** Fill in "What this is" and "Architecture" in `CLAUDE.md`.

## Keeping a project current

- When `standards` changes, Dependabot opens a PR in each project that bumps the pinned workflow SHA. Merge it when the checks are green.
- Run `scripts/apply-repo-settings.sh verify <owner>/<name>` now and then to catch drift in the GitHub settings. To change the required checks, change `docs/contract.md` and the caller job names together, then run `apply --replace-checks`.
