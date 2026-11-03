# Changelog

## 1.0.0 (unreleased)

- The first version: `inkan check` and `inkan diff` on every pull request, one comment marked
  `<!-- inkan-check -->` updated per run, the same report in the job summary.
- Inputs `entry`, `working-directory`, `base-ref`, `openapi-file`, `install`, `strict`,
  `comment`, `fail-on-breaking`, `github-token`; outputs `breaking`, `changes`, `check-ok`,
  `compared`, `report`.
- The base comes from a committed OpenAPI document (`git show`) or is built in a `git worktree`.
- Pull requests from forks get the job summary only.
- The Markdown is rendered from `--json` by `src/render.mjs` until the core has
  `inkan diff --format markdown`.
