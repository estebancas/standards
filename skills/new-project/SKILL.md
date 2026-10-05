---
name: new-project
description: Create a new frontend project from the user's template with the standard CI guardrails and repo settings applied. Use when asked to start, create or scaffold a new project, create a repo from the template, set up a project with the standard guardrails, or "new-project". Covers the template repo, the settings script, and a first PR that proves the six required checks.
version: 1.0.0
---

# new-project

Creates a GitHub repo from `estebancas/template-web-frontend`, applies the standard settings with `scripts/apply-repo-settings.sh`, and opens a first PR to prove the six required checks go green. The reasons behind every step are in `docs/new-project.md` and `docs/gotchas.md` in the `standards` repo; read them when something fails. `docs/contract.md` and the script's header (`scripts/apply-repo-settings.sh`) are the source of truth for check names and settings, not this file.

## Find the standards checkout

This skill is a symlink into the `standards` checkout. Resolve it, and read the docs from there:

```bash
STANDARDS=$(cd "$(readlink ~/.claude/skills/new-project)/../.." && pwd)
```

If that fails, ask the user where the `standards` checkout is, or offer to `gh repo clone estebancas/standards` into a place they pick.

## Inputs

Ask for anything not already given, one question at a time:

- **Project name**: kebab-case, becomes the repo and package name.
- **Owner**: default is the authenticated `gh` user (`gh api user --jq .login`).
- **Parent directory** to clone into: **always ask**. Never assume one.
- **Visibility**: public only. If the user wants private, say why it is refused (branch protection on the Free plan is public-only, and the script refuses private repos) and stop.

## Preflight (read-only)

1. `gh auth status` succeeds, and `jq` and `npm` are installed.
2. `gh repo view <owner>/<name>` fails (the name is free). If it exists, stop and ask.
3. The parent directory exists and is **not** inside a git repository (`git -C <dir> rev-parse` must fail). `gh repo create --clone` clones into the current directory, so every command below runs from the parent directory.
4. `$STANDARDS/scripts/apply-repo-settings.sh` exists.

## Confirm first

Creating a public repo is outward-facing. State the owner, name, visibility and the directory it will be cloned into, and **wait for a yes** before `gh repo create`. If a permission prompt appears for the repo creation, that is expected; do not look for another way around a refusal.

Note the start time (`date +%s`) after the yes, to report elapsed time at the end.

## Steps

Run from the parent directory:

1. **Create and clone.**
   `gh repo create <owner>/<name> --template estebancas/template-web-frontend --public --clone`, then `cd <name>`.
2. **Make it theirs.**
   - Set `name` in `package.json` and the `<title>` and description in `index.html`.
   - Replace `@estebancas` in `.github/CODEOWNERS` if the owner differs.
   - Run `npm install` to refresh the lockfile.
   - Check `TEMPLATE.md` in the new repo for anything that changed since this skill was written.
3. **Commit and push to `main`.** This goes straight to `main` because protection is not applied yet.
4. **Apply the settings.**
   `$STANDARDS/scripts/apply-repo-settings.sh apply <owner>/<name>`, then `verify`. `verify` must exit 0. If anything stays out of line, show the output and the relevant entry from `docs/gotchas.md`; do not retry blindly.
5. **Prove it with a first PR.** Create `chore/first-change`, append a line to `README.md`, push, and `gh pr create`. Wait for the six checks (`gh pr checks`, polling with an until-loop, not a chain of sleeps): `Lint / lint`, `Unit tests + build / test`, `Mutation testing / mutation`, `Bundle size / size`, `Dependency audit / audit`, `End-to-end / e2e`. Report the results and the elapsed time since the confirmation. Leave the PR open for the user to merge.
6. **Hand over the manual follow-ups** from `docs/new-project.md`, section 5: a real deploy and Cloudflare secrets, visual baselines after the first real UI (needs Docker), size budgets, optional PWA, and the `CLAUDE.md` description.

## Never

- Merge the PR, delete repos, or change settings on any repo except the one just created.
- Create a private repo, or apply settings to a repo the user did not just ask for.
- Weaken a guardrail (coverage, size, lint, the pinned Playwright tag) to make a check pass; report the failure and ask.
- Retry a failed command unchanged. Read the exit code and output, then act.

## If a check fails on the first PR

Read the failing job's log (`gh run view --log-failed`), match it against `docs/gotchas.md`, and report the cause and a proposed fix. The template's own CI is green, so a failure here usually means a change made in step 2.
