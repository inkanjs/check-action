# inkan check action

A GitHub Action for apps built with [inkan](https://inkan-dev.vercel.app/docs). On every pull
request it

- runs every example as a test against its contract (`inkan check`),
- compares the routes with the base branch and names what would break a client (`inkan diff`),
- writes one comment on the pull request, updated on every push, and the same report to the
  job summary.

```md
## 印 inkan check

**✗ 1 breaking change** · examples: 2 passed, 0 failed

### Breaks clients

| | Route | Change |
|---|---|---|
| ✗ | `GET /teas/{id}` | the 200 answer.price is gone |
```

With inkan 0.9.0 or newer the tables come from inkan itself (`--format markdown`, see
[The Markdown](#the-markdown)).

It is a composite action: a few lines of bash and one Node script without dependencies. There is
nothing to build, and it needs nothing on the runner beyond `node`, `npm`, `git` and `gh`.

## Usage

```yaml
# .github/workflows/inkan.yml
name: inkan

on:
  pull_request:

permissions:
  contents: read
  pull-requests: write # for the comment; without it the report is in the job summary only

jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
      - uses: actions/setup-node@v5
        with:
          node-version: 24 # a .ts entry needs Node 22.18 or newer
      - uses: inkanjs/check-action@v1
        with:
          entry: src/app.ts
```

The checkout can stay shallow: the action fetches the base commit it needs.

## Inputs

| Input | Default | What it does |
|---|---|---|
| `entry` | (required) | The file that builds the app and exports it (`export default app` or `export const app`), relative to `working-directory`. |
| `working-directory` | `.` | Where `package.json` and the entry live. |
| `base-ref` | the PR base | What to compare with: a branch or a commit. Empty takes `github.base_ref`; on `push`, the commit before the push. With no base at all, only the examples run. |
| `openapi-file` | | An OpenAPI document you commit (`npx inkan openapi src/app.ts -o openapi.json`), relative to `working-directory`. The base's copy is read with `git show`, so the base needs no install and no build: the fast path. Missing in the base, the action builds the base instead. |
| `install` | `true` | `npm ci` (or `npm install` without a lockfile) for the head and, when it is built, the base. With `false`, install yourself before the action; a built base then borrows the head's `node_modules`. |
| `strict` | `false` | `inkan check --strict`: a status a route promises that no example answers with fails the check. |
| `comment` | `true` | Create or update the pull request comment. |
| `fail-on-breaking` | `true` | Fail the job when a change would break a client. `false` reports it as a warning. |
| `github-token` | `github.token` | The token for the comment. |

## Outputs

| Output | Value |
|---|---|
| `breaking` | How many changes would break a client (`0` when nothing was compared). |
| `changes` | How many changes there are, breaking and safe. |
| `check-ok` | `true` when every example holds. |
| `compared` | `true` when there was a base to compare with. |
| `report` | The path of the Markdown report. |

```yaml
      - id: inkan
        uses: inkanjs/check-action@v1
        with:
          entry: src/app.ts
          fail-on-breaking: "false"
      - if: steps.inkan.outputs.breaking != '0'
        run: echo "this needs a major version"
```

## How the base is read

1. `base-ref` (or the PR base) is fetched, one commit deep.
2. With `openapi-file`, its copy in that commit is the base. Nothing is installed or run.
3. Otherwise the base commit is checked out next to the head with `git worktree add`, installed,
   and `inkan openapi <entry> -o base.json` writes its document.
4. `inkan diff base.json <entry> --json` compares it with the head, `inkan check <entry> --json`
   runs the head's examples. With inkan 0.9.0 or newer, each also runs with `--format markdown`
   for the report.

A base without the entry (the pull request that adds inkan) is reported as "nothing to compare
with", not as a failure.

## What "breaking" means

A change breaks a client that was written against the base: requests may only get looser, answers
may only get stricter. A route or a status that is gone, a request field that is required now, a
value a request may no longer send, a response field that is gone or may be `null` now, a value an
answer may send now: breaking. A new route, a new optional field, an answer that sends less
variety: safe. The rules are those of `inkan diff`, see
[the CLI docs](https://inkan-dev.vercel.app/docs/cli).

The job fails when an example fails, and when something breaks unless `fail-on-breaking` is
`false`. The comment is posted first, so it says why.

## The comment

There is one comment per pull request. It starts with `<!-- inkan-check -->`; the action finds it
by that marker and edits it on every run instead of adding a new one. A pull request where nothing
changed and nothing failed gets no comment, but an existing one is updated to say so.

It needs `pull-requests: write`. A comment the action cannot write (a missing permission, a
read-only token) is a warning, never a failure: the report is in the job summary either way.

## The Markdown

The action reads the version of the inkan the project installed (`npx inkan --version`).

- **0.9.0 and newer**: the report is inkan's own `inkan diff --format markdown` and
  `inkan check --format markdown`: the changes as one table, breaking first, with the machine
  `kind` of each (`route-removed`, `response-field-removed`, …), and the failing examples with
  what was answered and what was expected. The outputs still come from `--json`. Should
  `--format markdown` stop with exit code 2, the action warns and renders the report itself.
- **0.8**: `src/render.mjs` writes the report from `--json`.

Either way inkan's exit codes are read as 0.9 fixes them: 0 and 1 are results (all good, or a
check failed or a change breaks clients), 2 and up mean inkan could not load the app or was
called wrongly, and the action stops with an error that says so, since nothing was checked. inkan
0.8 exits with 1 on a load error too; the action tells that apart by the missing JSON.

## Pull requests from forks

GitHub gives `pull_request` workflows from forks a read-only token. The action sees that the head
is in another repository and writes the job summary only; the check and the diff run as usual and
can still fail the job.

**Do not switch to `pull_request_target` to get the comment on forks.** That event runs with a
token that can write to your repository and with your secrets, and this action installs and runs
the pull request's code: `npm ci` runs its install scripts and `inkan check` imports its app. With
`pull_request_target` any fork could run code with write access to your repository. The action is
written for `pull_request` and does not support the other.

If you want comments on fork pull requests, the safe pattern is two workflows: this one on
`pull_request` uploads the report as an artifact, and a second one on `workflow_run` (which never
checks out the fork's code) downloads it and posts it.

## Tests

`.github/workflows/test.yml` runs the action against the fixtures in `fixtures/`: a base app and
three pull requests on top of it (a breaking one, a clean one, one whose example fails).
`scripts/test-local.sh` runs the same scripts without GitHub, with git worktrees and
`@vxnsin/inkan` 0.8.1 from npm (the report from `src/render.mjs`). With `INKAN_CORE` set to a
checked-out inkan 0.9+ with `dist` built, it packs that with `npm pack` and runs every case
again against the tarball (the report from `--format markdown`).

```sh
bash scripts/test-local.sh
INKAN_CORE=../inkan bash scripts/test-local.sh
```

## License

MIT
