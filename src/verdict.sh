#!/usr/bin/env bash
# Fails the job for what run.sh found, after the comment is posted.
# Env: CHECK_OK, BREAKING, FAIL_ON_BREAKING
set -uo pipefail

failed=0
if [ "${CHECK_OK:-false}" != "true" ]; then
  echo "::error title=inkan check::examples fail against their contracts (see the job summary)"
  failed=1
fi
if [ "${BREAKING:-0}" -gt 0 ]; then
  if [ "${FAIL_ON_BREAKING:-true}" = "true" ]; then
    echo "::error title=inkan check::${BREAKING} change(s) would break clients (see the job summary)"
    failed=1
  else
    echo "::warning title=inkan check::${BREAKING} change(s) would break clients (see the job summary)"
  fi
fi
exit "$failed"
