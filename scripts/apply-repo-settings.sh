#!/usr/bin/env bash
# Apply or verify the repo settings that live only in GitHub (see docs/contract.md).
#
#   apply-repo-settings.sh apply  <owner/repo> [options]
#   apply-repo-settings.sh verify <owner/repo> [options]
#
# verify is read-only: it prints one line per setting and exits 1 if anything drifted.
# apply is idempotent: it changes only what drifted, then re-checks and exits 1 if anything
# is still wrong. Requires gh (authenticated, admin on the repo) and jq. Bash 3.2 compatible.
#
# Options:
#   --checks "a,b,c"    required status check contexts. Default: the six in docs/contract.md.
#                       Pass "" to require none (for a repo that has no CI yet).
#   --branch NAME       branch to protect. Default: the repo's default branch.
#   --no-environment    do not manage the `production` environment.
#   --environment NAME  environment to manage. Default: production.
#
# Managed (and nothing else): required status checks (strict, union with existing), a required
# pull request with 0 approvals, enforce_admins off, force pushes and deletions off, Actions
# enabled with allowed_actions all and sha_pinning_required, vulnerability alerts, Dependabot
# security updates, secret scanning with push protection, and the environment.
# Existing protection that is not listed here (extra checks, code-owner review, signatures,
# linear history, conversation resolution, lock) is preserved, because the protection endpoint
# replaces the whole object.
#
# Exit: 0 no drift, 1 drift or a failed apply, 2 usage error or unsupported repo.

set -uo pipefail

DEFAULT_CHECKS="Lint / lint,Unit tests + build / test,Mutation testing / mutation,Bundle size / size,Dependency audit / audit,End-to-end / e2e"

usage() {
  sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//' >&2
  exit 2
}
die() { printf 'error: %s\n' "$*" >&2; exit 2; }
ok() { printf 'ok     %s\n' "$*"; }
drift() { printf 'DRIFT  %s\n' "$*"; DRIFT=$((DRIFT + 1)); }

DRIFT=0
FAIL=0
MODE="${1:-}"
REPO="${2:-}"
[ "$MODE" = apply ] || [ "$MODE" = verify ] || usage
printf '%s' "$REPO" | grep -Eq '^[^/[:space:]]+/[^/[:space:]]+$' || usage
shift 2

CHECKS="$DEFAULT_CHECKS"
BRANCH=""
ENV_NAME="production"
MANAGE_ENV=1
while [ $# -gt 0 ]; do
  case "$1" in
    --checks) [ $# -ge 2 ] || usage; CHECKS="$2"; shift 2 ;;
    --branch) [ $# -ge 2 ] || usage; BRANCH="$2"; shift 2 ;;
    --environment) [ $# -ge 2 ] || usage; ENV_NAME="$2"; shift 2 ;;
    --no-environment) MANAGE_ENV=0; shift ;;
    *) usage ;;
  esac
done

command -v gh >/dev/null 2>&1 || die "gh is required"
command -v jq >/dev/null 2>&1 || die "jq is required"

CHECKS_JSON=$(printf '%s' "$CHECKS" | tr ',' '\n' | jq -R 'gsub("^\\s+|\\s+$"; "")' | jq -s 'map(select(. != ""))')

# --- preflight: refuse what the script cannot manage ---------------------------------------
REPO_JSON=$(gh api "repos/$REPO" 2>/dev/null) || die "cannot read $REPO (does it exist, and is gh logged in?)"
[ "$(printf '%s' "$REPO_JSON" | jq -r .private)" = false ] \
  || die "$REPO is private: branch protection on the Free plan is public-only, so this script refuses private repos"
[ "$(printf '%s' "$REPO_JSON" | jq -r '.permissions.admin // false')" = true ] \
  || die "admin permission on $REPO is required"
[ -n "$BRANCH" ] || BRANCH=$(printf '%s' "$REPO_JSON" | jq -r .default_branch)
OWNER_ID=$(printf '%s' "$REPO_JSON" | jq -r .owner.id)
if [ "$MANAGE_ENV" = 1 ] && [ "$(printf '%s' "$REPO_JSON" | jq -r .owner.type)" != User ]; then
  die "environment reviewers are only supported for user-owned repos (use --no-environment)"
fi

# --- vulnerability alerts (dependency graph) -----------------------------------------------
check_vulnerability_alerts() {
  if gh api "repos/$REPO/vulnerability-alerts" --silent >/dev/null 2>&1; then
    ok "vulnerability alerts: enabled"
  else
    drift "vulnerability alerts: disabled"
  fi
}
apply_vulnerability_alerts() { gh api -X PUT "repos/$REPO/vulnerability-alerts" --silent; }

# --- Dependabot security updates (needs vulnerability alerts first) ------------------------
check_security_fixes() {
  if [ "$(gh api "repos/$REPO/automated-security-fixes" --jq .enabled 2>/dev/null)" = true ]; then
    ok "dependabot security updates: enabled"
  else
    drift "dependabot security updates: disabled"
  fi
}
apply_security_fixes() { gh api -X PUT "repos/$REPO/automated-security-fixes" --silent; }

# --- secret scanning + push protection -----------------------------------------------------
check_secret_scanning() {
  local sa
  sa=$(gh api "repos/$REPO" --jq '[.security_and_analysis.secret_scanning.status, .security_and_analysis.secret_scanning_push_protection.status] | join(" ")' 2>/dev/null)
  if [ "$sa" = "enabled enabled" ]; then
    ok "secret scanning + push protection: enabled"
  else
    drift "secret scanning + push protection: '$sa' (want 'enabled enabled')"
  fi
}
apply_secret_scanning() {
  printf '%s' '{"security_and_analysis":{"secret_scanning":{"status":"enabled"},"secret_scanning_push_protection":{"status":"enabled"}}}' \
    | gh api -X PATCH "repos/$REPO" --input - >/dev/null
}

# --- Actions permissions + SHA pinning -----------------------------------------------------
# Lists `uses:` lines in the default branch's workflows that are not pinned to a commit SHA.
unpinned_actions() {
  local files f
  files=$(gh api "repos/$REPO/contents/.github/workflows" --jq '.[].name' 2>/dev/null) || return 0
  for f in $files; do
    gh api -H "Accept: application/vnd.github.raw" "repos/$REPO/contents/.github/workflows/$f" 2>/dev/null \
      | grep -nE '^[[:space:]-]*uses:[[:space:]]*[^[:space:]#]+' \
      | grep -vE 'uses:[[:space:]]*(\./|docker://)' \
      | grep -vE '@[0-9a-f]{40}([[:space:]]|$)' \
      | sed "s|^|$f:|"
  done
}
check_actions() {
  local a
  a=$(gh api "repos/$REPO/actions/permissions" 2>/dev/null) || { drift "actions permissions: unreadable"; return; }
  [ "$(printf '%s' "$a" | jq -r .enabled)" = true ] && ok "actions: enabled" || drift "actions: disabled"
  [ "$(printf '%s' "$a" | jq -r .allowed_actions)" = all ] && ok "actions: allowed_actions all" \
    || drift "actions: allowed_actions is '$(printf '%s' "$a" | jq -r .allowed_actions)' (want all)"
  if [ "$(printf '%s' "$a" | jq -r .sha_pinning_required)" = true ]; then
    ok "actions: sha_pinning_required"
  else
    drift "actions: sha_pinning_required is off"
    unpinned_actions | sed 's/^/         unpinned: /'
  fi
}
apply_actions() {
  local sha=true
  # Turning pinning on while a workflow uses a tag would fail every run of it.
  if [ -n "$(unpinned_actions)" ]; then
    echo "         not enabling sha_pinning_required: unpinned actions exist (pin them first)"
    sha=false
  fi
  printf '{"enabled":true,"allowed_actions":"all","sha_pinning_required":%s}' "$sha" \
    | gh api -X PUT "repos/$REPO/actions/permissions" --input - >/dev/null
}

# --- production environment ----------------------------------------------------------------
E_JSON='{}'
check_environment() {
  local policies msgs
  E_JSON=$(gh api "repos/$REPO/environments/$ENV_NAME" 2>/dev/null) || { E_JSON='{}'; drift "environment $ENV_NAME: missing"; return; }
  policies=$(gh api "repos/$REPO/environments/$ENV_NAME/deployment-branch-policies" --jq '[.branch_policies[].name]' 2>/dev/null || echo '[]')
  msgs=$(printf '%s' "$E_JSON" | jq -r --argjson oid "$OWNER_ID" --argjson pol "$policies" --arg br "$BRANCH" '
    [ (if ([.protection_rules[]? | select(.type == "required_reviewers") | .reviewers[].reviewer.id] | index($oid)) then empty else "owner is not a required reviewer" end),
      (if ([.protection_rules[]? | select(.type == "required_reviewers") | .prevent_self_review] | any) then "self-review is prevented (want allowed)" else empty end),
      (if (.deployment_branch_policy.custom_branch_policies // false) then empty else "custom deployment branch policies are off" end),
      (if ($pol | index($br)) then empty else "no deployment policy for " + $br end)
    ] | .[]')
  if [ -z "$msgs" ]; then ok "environment $ENV_NAME: reviewer, self-review, $BRANCH-only policy"; else
    printf '%s\n' "$msgs" | while IFS= read -r m; do printf 'DRIFT  environment %s: %s\n' "$ENV_NAME" "$m"; done
    DRIFT=$((DRIFT + $(printf '%s\n' "$msgs" | wc -l)))
  fi
}
apply_environment() {
  local body
  # Keep reviewers that are already there; the PUT replaces the whole list.
  body=$(printf '%s' "$E_JSON" | jq --argjson oid "$OWNER_ID" '{
    reviewers: (([.protection_rules[]? | select(.type == "required_reviewers") | .reviewers[] | {type: .type, id: .reviewer.id}] + [{type: "User", id: $oid}]) | unique),
    prevent_self_review: false,
    deployment_branch_policy: {protected_branches: false, custom_branch_policies: true}
  }')
  printf '%s' "$body" | gh api -X PUT "repos/$REPO/environments/$ENV_NAME" --input - >/dev/null || return 1
  if ! gh api "repos/$REPO/environments/$ENV_NAME/deployment-branch-policies" --jq '.branch_policies[].name' 2>/dev/null | grep -qx "$BRANCH"; then
    jq -n --arg n "$BRANCH" '{name: $n, type: "branch"}' \
      | gh api -X POST "repos/$REPO/environments/$ENV_NAME/deployment-branch-policies" --input - >/dev/null
  fi
}

# --- branch protection ---------------------------------------------------------------------
PROT='{}'
fetch_protection() { PROT=$(gh api "repos/$REPO/branches/$BRANCH/protection" 2>/dev/null) || PROT='{}'; }
check_protection() {
  local msgs
  fetch_protection
  msgs=$(printf '%s' "$PROT" | jq -r --argjson want "$CHECKS_JSON" '
    [ (if . == {} then "no branch protection" else empty end),
      (if (.required_status_checks.strict // false) then empty else "strict required checks are off" end),
      (($want - (.required_status_checks.contexts // [])) | if length > 0 then "missing required checks: " + join("; ") else empty end),
      (if .required_pull_request_reviews == null then "pull request is not required"
       elif .required_pull_request_reviews.required_approving_review_count != 0 then "approvals required: \(.required_pull_request_reviews.required_approving_review_count) (want 0)"
       else empty end),
      (if (.enforce_admins.enabled // false) then "enforce_admins is on" else empty end),
      (if (.allow_force_pushes.enabled // false) then "force pushes are allowed" else empty end),
      (if (.allow_deletions.enabled // false) then "deletions are allowed" else empty end)
    ] | .[]')
  if [ -z "$msgs" ]; then ok "branch protection on $BRANCH"; else
    printf '%s\n' "$msgs" | while IFS= read -r m; do printf 'DRIFT  branch protection %s: %s\n' "$BRANCH" "$m"; done
    DRIFT=$((DRIFT + $(printf '%s\n' "$msgs" | wc -l)))
  fi
}
apply_protection() {
  local body
  body=$(printf '%s' "$PROT" | jq --argjson want "$CHECKS_JSON" '
    . as $c | {
      required_status_checks: {strict: true, contexts: ((($c.required_status_checks.contexts // []) + $want) | unique)},
      enforce_admins: false,
      required_pull_request_reviews: {
        dismiss_stale_reviews: ($c.required_pull_request_reviews.dismiss_stale_reviews // false),
        require_code_owner_reviews: ($c.required_pull_request_reviews.require_code_owner_reviews // false),
        require_last_push_approval: ($c.required_pull_request_reviews.require_last_push_approval // false),
        required_approving_review_count: 0
      },
      restrictions: (if $c.restrictions then {users: [$c.restrictions.users[].login], teams: [$c.restrictions.teams[].slug], apps: [$c.restrictions.apps[].slug]} else null end),
      required_linear_history: ($c.required_linear_history.enabled // false),
      allow_force_pushes: false,
      allow_deletions: false,
      block_creations: ($c.block_creations.enabled // false),
      required_conversation_resolution: ($c.required_conversation_resolution.enabled // false),
      lock_branch: ($c.lock_branch.enabled // false),
      allow_fork_syncing: ($c.allow_fork_syncing.enabled // false)
    }')
  printf '%s' "$body" | gh api -X PUT "repos/$REPO/branches/$BRANCH/protection" --input - >/dev/null
}

# --- run -----------------------------------------------------------------------------------
run_group() {
  local before=$DRIFT
  "check_$1"
  if [ "$MODE" = apply ] && [ "$DRIFT" -gt "$before" ]; then
    echo "apply  $1"
    "apply_$1" || { echo "FAILED apply $1"; FAIL=1; }
    DRIFT=$before
    "check_$1"
  fi
}

echo "$MODE $REPO (branch $BRANCH)"
run_group vulnerability_alerts
run_group security_fixes
run_group secret_scanning
run_group actions
[ "$MANAGE_ENV" = 1 ] && run_group environment
run_group protection

if [ "$DRIFT" -gt 0 ] || [ "$FAIL" = 1 ]; then
  echo "result: $DRIFT setting(s) out of line"
  exit 1
fi
echo "result: no drift"
