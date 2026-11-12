#!/usr/bin/env bash
# Builds a throwaway git repository for one fixture pull request:
# main holds fixtures/app, the branch pr adds fixtures/<variant> on top.
# An inkan spec (for example the absolute path of a tarball from npm pack) replaces
# the locked @vxnsin/inkan 0.8.1 with @inkanjs/inkan, imports included; the lockfile goes, so npm install resolves it in the
# repository and in the base's worktree alike.
#
# scripts/fixture-repo.sh <breaking|clean|failing> <dir> [inkan spec]
set -euo pipefail

variant="$1"
dir="$2"
spec="${3:-}"
fixtures="$(cd "$(dirname "$0")/../fixtures" && pwd)"
[ -d "$fixtures/$variant" ] || { echo "no fixture $variant" >&2; exit 2; }

mkdir -p "$dir"
cd "$dir"
git init --quiet -b main
git config user.name fixture
git config user.email fixture@example.invalid
git config core.autocrlf false
cp "$fixtures/app/"* .
if [ -n "$spec" ]; then
  rm package-lock.json
  SPEC="$spec" node -e '
    const fs = require("fs");
    const pkg = JSON.parse(fs.readFileSync("package.json", "utf8"));
    delete pkg.dependencies["@vxnsin/inkan"];
    pkg.dependencies["@inkanjs/inkan"] = process.env.SPEC;
    fs.writeFileSync("package.json", JSON.stringify(pkg, null, 2) + "\n");
  '
fi
[ -z "$spec" ] || sed -i "s#@vxnsin/inkan#@inkanjs/inkan#g" ./*.js
git add -A
git commit --quiet -m "base"
git checkout --quiet -b pr
cp "$fixtures/$variant/"* .
[ -z "$spec" ] || sed -i "s#@vxnsin/inkan#@inkanjs/inkan#g" ./*.js
git add -A
git commit --quiet -m "$variant"
