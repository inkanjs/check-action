#!/usr/bin/env bash
# Creates or updates the one PR comment marked <!-- inkan-check -->.
# Never fails the job: a token that may not write (a fork, Dependabot) only
# leaves the job summary, which run.sh already wrote.
#
# Env: REPORT, NOTEWORTHY, GH_TOKEN
# GitHub sets: GITHUB_REPOSITORY, GITHUB_EVENT_PATH
set -uo pipefail

say() { echo "inkan-check: $*" >&2; }
skip() { say "$* — the report is in the job summary"; exit 0; }

[ -f "${REPORT:-}" ] || skip "no report to post"
[ -f "${GITHUB_EVENT_PATH:-}" ] || skip "no event payload"

read -r pr head_repo < <(node -e '
  const pr = require(process.env.GITHUB_EVENT_PATH).pull_request;
  console.log(pr ? `${pr.number} ${pr.head?.repo?.full_name ?? "-"}` : "- -");
')
[ "$pr" != "-" ] || skip "not a pull request, no comment"
[ "$head_repo" = "${GITHUB_REPOSITORY:-}" ] || skip "a pull request from a fork gets a read-only token, no comment"
command -v gh >/dev/null || skip "gh is not installed"

marker='<!-- inkan-check -->'
id="$(gh api --paginate "repos/$GITHUB_REPOSITORY/issues/$pr/comments" \
  --jq ".[] | select(.user.type == \"Bot\" and (.body | startswith(\"$marker\"))) | .id" 2>/dev/null | head -n 1)" \
  || skip "could not list the comments of #$pr"

if [ -n "$id" ]; then
  gh api --silent -X PATCH "repos/$GITHUB_REPOSITORY/issues/comments/$id" -F "body=@$REPORT" \
    && say "updated the comment on #$pr" \
    || echo "::warning title=inkan check::could not update the comment on #$pr (does the job have pull-requests: write?)"
elif [ "${NOTEWORTHY:-true}" = "true" ]; then
  gh api --silent -X POST "repos/$GITHUB_REPOSITORY/issues/$pr/comments" -F "body=@$REPORT" \
    && say "commented on #$pr" \
    || echo "::warning title=inkan check::could not comment on #$pr (does the job have pull-requests: write?)"
else
  say "nothing changed and nothing failed, no comment on #$pr"
fi
exit 0
