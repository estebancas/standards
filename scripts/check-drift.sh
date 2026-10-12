#!/usr/bin/env bash
# Run `apply-repo-settings.sh verify` on every repo in repos.txt.
#
#   check-drift.sh [repos-file]      default: repos.txt next to scripts/
#
# Each line of the file is `owner/repo [verify options...]` (see repos.txt). A clean repo prints one
# line. A drifted or unreadable repo prints the full verify output, and the script exits 1 after
# checking all of them. It also exits 1 when the token in use expires within 30 days, so the
# rotation reminder arrives the same way as drift: a failed run and an email.
# Needs gh (authenticated) and jq. Bash 3.2 compatible.

set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
LIST="${1:-$HERE/../repos.txt}"
VERIFY="$HERE/apply-repo-settings.sh"
WARN_DAYS=30

[ -r "$LIST" ] || { printf 'error: cannot read %s\n' "$LIST" >&2; exit 2; }

BAD=""
CHECKED=0
SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/null}"
FENCE=$(printf '\140\140\140') # three backticks: a Markdown code fence for the run summary

set -f # repo options are split on spaces; never expand globs in them
while IFS= read -r line || [ -n "$line" ]; do
  line=${line%%#*}
  # shellcheck disable=SC2086 # splitting is the point: owner/repo, then its options
  set -- $line
  [ $# -gt 0 ] || continue
  repo=$1
  shift
  CHECKED=$((CHECKED + 1))
  out=$("$VERIFY" verify "$repo" "$@" 2>&1)
  code=$?
  if [ "$code" -eq 0 ]; then
    printf 'ok     %s\n' "$repo"
  else
    printf 'DRIFT  %s (verify exited %s)\n%s\n\n' "$repo" "$code" "$out"
    BAD="$BAD $repo"
    printf '### %s\n\n%s\n%s\n%s\n\n' "$repo" "$FENCE" "$out" "$FENCE" >>"$SUMMARY"
  fi
done <"$LIST"
set +f

if [ "$CHECKED" -eq 0 ]; then
  printf 'error: no repos in %s\n' "$LIST" >&2
  exit 2
fi

FAILED=0
if [ -n "$BAD" ]; then
  printf 'Drift or unreadable settings in:%s\n' "$BAD"
  printf '## Drift\n\nRepos out of line:%s\n' "$BAD" >>"$SUMMARY"
  FAILED=1
fi

# Fine-grained tokens report their expiry in a response header. Other tokens send none.
expiry=$(gh api -i rate_limit 2>/dev/null | tr -d '\r' | sed -n 's/^[Gg]ithub-[Aa]uthentication-[Tt]oken-[Ee]xpiration: *//p' | head -n 1)
if [ -n "$expiry" ]; then
  day=${expiry%% *}
  end=$(date -d "$day" +%s 2>/dev/null || date -j -f %Y-%m-%d "$day" +%s 2>/dev/null || true)
  if [ -n "$end" ]; then
    left=$(((end - $(date +%s)) / 86400))
    if [ "$left" -le "$WARN_DAYS" ]; then
      printf 'The token expires on %s (%s days). Create a new one and update the DRIFT_TOKEN secret.\n' "$day" "$left"
      printf '## Rotate the token\n\nIt expires on %s.\n' "$day" >>"$SUMMARY"
      FAILED=1
    fi
  fi
fi

exit "$FAILED"
