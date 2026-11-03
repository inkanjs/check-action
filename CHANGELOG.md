# Changelog

## 1.0.0

- The first version: `inkan check` and `inkan diff` on every pull request, one comment marked
  `<!-- inkan-check -->` updated per run, the same report in the job summary.
- Inputs `entry`, `working-directory`, `base-ref`, `openapi-file`, `install`, `strict`,
  `comment`, `fail-on-breaking`, `github-token`; outputs `breaking`, `changes`, `check-ok`,
  `compared`, `report`.
- The base comes from a committed OpenAPI document (`git show`) or is built in a `git worktree`.
- Pull requests from forks get the job summary only.
- With inkan 0.9.0 or newer the report is the core's `--format markdown` (with each change's
  `kind`); with 0.8, `src/render.mjs` renders it from `--json`. Exit code 2 or more from inkan
  (it could not load the app, or a usage error) stops the action with an error; 0 and 1 are results.
