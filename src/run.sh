#!/usr/bin/env bash
# Runs inkan check and inkan diff for the head, gets the base OpenAPI document,
# writes the Markdown report to the job summary and the step outputs.
# Never fails because of what it found (verdict.sh does that), only when it
# cannot do its job.
#
# Env: ENTRY, WORKDIR, BASE_REF, OPENAPI_FILE, INSTALL, STRICT, ACTION_DIR
# GitHub sets: GITHUB_OUTPUT, GITHUB_STEP_SUMMARY, GITHUB_BASE_REF, GITHUB_EVENT_NAME, GITHUB_EVENT_PATH, RUNNER_TEMP
set -uo pipefail

say() { echo "inkan-check: $*" >&2; }
die() { echo "::error title=inkan check::$*"; exit 2; }

[ -n "${ENTRY:-}" ] || die "the input entry is missing: the file that builds and exports the app, for example src/app.ts"
cd "${WORKDIR:-.}" || die "working-directory ${WORKDIR} does not exist"
[ -f "$ENTRY" ] || die "$ENTRY does not exist in $(pwd)"
ACTION_DIR="${ACTION_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"

out="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/inkan-check.XXXXXX")"
outputs="${GITHUB_OUTPUT:-$out/outputs}"
summary="${GITHUB_STEP_SUMMARY:-$out/summary.md}"

inkan() { npx --no-install inkan "$@"; }

install() {
  if [ -f package-lock.json ] || [ -f npm-shrinkwrap.json ]; then npm ci --no-audit --no-fund >&2
  else npm install --no-audit --no-fund >&2
  fi
}

if [ "${INSTALL:-true}" = "true" ]; then
  say "installing ($(pwd))"
  install || die "npm could not install the dependencies in $(pwd)"
fi

# ---------- head: the examples ----------
strict=()
[ "${STRICT:-false}" = "true" ] && strict=(--strict)
inkan check "$ENTRY" --json ${strict[@]+"${strict[@]}"} >"$out/check.json" 2>"$out/check.err"
code=$?
if [ "$code" -gt 1 ]; then
  cat "$out/check.err" >&2
  die "inkan check $ENTRY stopped with exit code $code (see above)"
fi

# ---------- base: which commit ----------
ref="${BASE_REF:-${GITHUB_BASE_REF:-}}"
if [ -z "$ref" ] && [ "${GITHUB_EVENT_NAME:-}" = "push" ] && [ -f "${GITHUB_EVENT_PATH:-}" ]; then
  ref="$(node -p 'require(process.env.GITHUB_EVENT_PATH).before || ""')"
  case "$ref" in *[!0]*) ;; *) ref="" ;; esac # a new branch: before is all zeros
fi

base_sha=""
if [ -n "$ref" ]; then
  if git remote get-url origin >/dev/null 2>&1 && git fetch --quiet --no-tags --depth=1 origin "$ref" 2>/dev/null; then
    base_sha="$(git rev-parse FETCH_HEAD)"
  else
    base_sha="$(git rev-parse --verify --quiet "$ref^{commit}")"
  fi
  [ -n "$base_sha" ] || die "could not find the base $ref (fetched from origin and looked it up locally)"
fi

# ---------- base: its OpenAPI document ----------
note=""
base_json=""
prefix="$(git rev-parse --show-prefix)" # working-directory, relative to the repository root
if [ -n "$base_sha" ]; then
  if [ -n "${OPENAPI_FILE:-}" ] && git show "$base_sha:$prefix$OPENAPI_FILE" >"$out/base.json" 2>/dev/null; then
    say "base: $OPENAPI_FILE at ${base_sha:0:7}"
    base_json="$out/base.json"
  else
    [ -n "${OPENAPI_FILE:-}" ] && say "base: $OPENAPI_FILE is not in ${base_sha:0:7}, building the base instead"
    wt="$out/base"
    git worktree add --quiet --detach "$wt" "$base_sha" >&2 || die "git worktree add $base_sha failed"
    trap 'git worktree remove --force "$wt" >/dev/null 2>&1' EXIT
    here="$(pwd)"
    (
      cd "$wt/$prefix" 2>/dev/null || exit 3
      [ -f "$ENTRY" ] || exit 3
      if [ "${INSTALL:-true}" = "true" ]; then install || exit 4
      elif [ ! -e node_modules ] && [ -d "$here/node_modules" ]; then ln -s "$here/node_modules" node_modules
      fi
      inkan openapi "$ENTRY" -o "$out/base.json" >&2
    )
    case $? in
      0) base_json="$out/base.json"; say "base: built $ENTRY at ${base_sha:0:7}" ;;
      3) note="The base (${base_sha:0:7}) has no $ENTRY yet, so there is nothing to compare with." ;;
      4) die "npm could not install the dependencies of the base (${base_sha:0:7})" ;;
      *) note="inkan openapi could not build the base (${base_sha:0:7}), so the routes were not compared. See the job log." ;;
    esac
  fi
else
  say "no base to compare with (set base-ref, or run on pull_request)"
fi

# ---------- head against base ----------
diff_args=()
if [ -n "$base_json" ]; then
  inkan diff "$base_json" "$ENTRY" --json >"$out/diff.json" 2>"$out/diff.err"
  code=$?
  if [ "$code" -gt 1 ]; then
    cat "$out/diff.err" >&2
    die "inkan diff stopped with exit code $code (see above)"
  fi
  diff_args=(--diff "$out/diff.json" --base "${base_sha:0:7}${ref:+ ($ref)}")
fi
[ -n "$note" ] && diff_args+=(--note "$note")

node "$ACTION_DIR/src/render.mjs" --check "$out/check.json" ${diff_args[@]+"${diff_args[@]}"} --out "$out/report.md" >"$out/render.out" \
  || die "could not render the report"
cat "$out/render.out" >>"$outputs"
echo "report=$out/report.md" >>"$outputs"
cat "$out/report.md" >>"$summary"
cat "$out/report.md" >&2
exit 0
