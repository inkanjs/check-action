#!/usr/bin/env bash
# Runs the action's scripts the way action.yml does, without GitHub: one throwaway
# repository per fixture pull request (main + pr, the base built in a git worktree),
# @vxnsin/inkan from npm. Proves the JSON -> Markdown path, the outputs and the exit codes.
#
# scripts/test-local.sh            (needs node, npm, git)
set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/inkan-check-test.XXXXXX")"
pass=0
fail=0

ok() { pass=$((pass + 1)); echo "  ok   $*"; }
no() { fail=$((fail + 1)); echo "  FAIL $*"; }
expect() { # expect <label> <actual> <wanted>
  if [ "$2" = "$3" ]; then ok "$1 = $3"; else no "$1 = $2, wanted $3"; fi
}
output() { grep "^$1=" "$2" | tail -n 1 | cut -d= -f2-; }

# run_case <name> <variant> [VAR=value ...]: runs run.sh, then verdict.sh, like action.yml
run_case() {
  local name="$1" variant="$2"
  shift 2
  local dir="$tmp/$name"
  bash "$root/scripts/fixture-repo.sh" "$variant" "$dir/repo"
  : >"$dir/outputs"
  : >"$dir/summary.md"
  (
    unset GITHUB_EVENT_NAME GITHUB_EVENT_PATH GITHUB_BASE_REF
    ENTRY=app.js BASE_REF=main OPENAPI_FILE="" STRICT=false
    for kv in "$@"; do export "${kv?}"; done
    ACTION_DIR="$root" ENTRY="$ENTRY" WORKDIR="$dir/repo" BASE_REF="$BASE_REF" OPENAPI_FILE="$OPENAPI_FILE" \
      INSTALL=true STRICT="$STRICT" GITHUB_OUTPUT="$dir/outputs" GITHUB_STEP_SUMMARY="$dir/summary.md" \
      RUNNER_TEMP="$dir" bash "$root/src/run.sh" 2>"$dir/run.log" >"$dir/run.out"
  )
  echo "$?" >"$dir/run.code"
  (
    FAIL_ON_BREAKING=true
    for kv in "$@"; do export "${kv?}"; done
    CHECK_OK="$(output check-ok "$dir/outputs")" BREAKING="$(output breaking "$dir/outputs")" \
      FAIL_ON_BREAKING="$FAIL_ON_BREAKING" bash "$root/src/verdict.sh" >"$dir/verdict.log"
  )
  echo "$?" >"$dir/verdict.code"
}

check_case() { # check_case <name> <run code> <breaking> <changes> <check-ok> <compared> <verdict code>
  local dir="$tmp/$1"
  echo "$1"
  expect "run.sh exit" "$(cat "$dir/run.code")" "$2"
  expect "breaking" "$(output breaking "$dir/outputs")" "$3"
  expect "changes" "$(output changes "$dir/outputs")" "$4"
  expect "check-ok" "$(output check-ok "$dir/outputs")" "$5"
  expect "compared" "$(output compared "$dir/outputs")" "$6"
  expect "verdict.sh exit" "$(cat "$dir/verdict.code")" "$7"
  if head -n 1 "$dir/summary.md" | grep -qx '<!-- inkan-check -->'; then ok "summary starts with the marker"; else no "summary starts with the marker"; fi
}

has() { # has <name> <file> <text>
  if grep -qF -- "$3" "$tmp/$1/$2"; then ok "$2 has: $3"; else no "$2 lacks: $3"; fi
}

echo "inkan-check test in $tmp"
echo

run_case clean clean
check_case clean 0 0 2 true true 0
has clean summary.md "✓ nothing breaks a client"
has clean summary.md '| · | `GET /teas` | is new |'

run_case breaking breaking
check_case breaking 0 1 1 true true 1
has breaking summary.md "**✗ 1 breaking change**"
has breaking summary.md '| ✗ | `GET /teas/{id}` | the 200 answer.price is gone |'
has breaking run.log "base: built app.js at"

run_case breaking-warn breaking FAIL_ON_BREAKING=false
check_case breaking-warn 0 1 1 true true 0
has breaking-warn verdict.log "::warning title=inkan check::1 change(s) would break clients"

run_case openapi-file breaking OPENAPI_FILE=openapi.json
check_case openapi-file 0 1 1 true true 1
has openapi-file run.log "base: openapi.json at"

run_case failing failing
check_case failing 0 0 0 false true 1
has failing summary.md '- ✗ `GET /teas/:id` sencha (status 200)'
has failing summary.md 'body.name: expected "Sencha", got "SENCHA"'

run_case no-base clean BASE_REF=
check_case no-base 0 0 0 true false 0

run_case bad-entry clean ENTRY=missing.js
echo "bad-entry"
expect "run.sh exit" "$(cat "$tmp/bad-entry/run.code")" 2

echo "comment.sh"
printf '{"pull_request":{"number":7,"head":{"repo":{"full_name":"someone/fork"}}}}' >"$tmp/fork.json"
echo "<!-- inkan-check -->" >"$tmp/report.md"
log="$(REPORT="$tmp/report.md" GITHUB_EVENT_PATH="$tmp/fork.json" GITHUB_REPOSITORY=inkanjs/fixture bash "$root/src/comment.sh" 2>&1)"
expect "fork: exit" "$?" 0
case "$log" in *"from a fork"*) ok "fork: summary only" ;; *) no "fork: $log" ;; esac
printf '{"ref":"refs/heads/main"}' >"$tmp/push.json"
log="$(REPORT="$tmp/report.md" GITHUB_EVENT_PATH="$tmp/push.json" GITHUB_REPOSITORY=inkanjs/fixture bash "$root/src/comment.sh" 2>&1)"
expect "push: exit" "$?" 0
case "$log" in *"not a pull request"*) ok "push: no comment" ;; *) no "push: $log" ;; esac

echo
echo "$pass passed, $fail failed"
if [ "$fail" -eq 0 ]; then rm -r "$tmp"; else echo "kept $tmp"; exit 1; fi
