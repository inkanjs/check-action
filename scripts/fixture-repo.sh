#!/usr/bin/env bash
# Builds a throwaway git repository for one fixture pull request:
# main holds fixtures/app, the branch pr adds fixtures/<variant> on top.
#
# scripts/fixture-repo.sh <breaking|clean|failing> <dir>
set -euo pipefail

variant="$1"
dir="$2"
fixtures="$(cd "$(dirname "$0")/../fixtures" && pwd)"
[ -d "$fixtures/$variant" ] || { echo "no fixture $variant" >&2; exit 2; }

mkdir -p "$dir"
cd "$dir"
git init --quiet -b main
git config user.name fixture
git config user.email fixture@example.invalid
git config core.autocrlf false
cp "$fixtures/app/"* .
git add -A
git commit --quiet -m "base"
git checkout --quiet -b pr
cp "$fixtures/$variant/"* .
git add -A
git commit --quiet -m "$variant"
