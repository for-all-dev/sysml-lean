# STPA Safety Findings action

A reusable, configurable version of this repo's `findings-diff` CI job:
it runs the repo's Lean-built `sysml` CLI to compute STPA safety findings,
diffs them between a pull request's base and head, posts a sticky PR
comment with the diff, and fails the check when error findings regress.

## Usage

```yaml
name: STPA safety findings

on:
  pull_request:

permissions:
  pull-requests: write

jobs:
  findings-diff:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
        with:
          fetch-depth: 0

      - uses: for-all-dev/sysml-lean@v1
        with:
          github-token: ${{ github.token }}
          oracle-jar-url: https://www.monticore.de/download/MCSysMLv2.jar
          oracle-sha256: <pin>
```

`fetch-depth: 0` (or at least enough history to include the PR base commit)
is required so the action can create a git worktree at the base sha.

## Inputs

| Name | Default | Description |
| --- | --- | --- |
| `github-token` | `${{ github.token }}` | Token used to read PR metadata and post the sticky comment. |
| `working-directory` | `.` | Directory containing the Lean project (`lakefile.toml`). |
| `comment` | `true` | Post/refresh the sticky PR comment on `pull_request` events. |
| `fail-on-regression` | `true` | Fail the action when error findings are introduced relative to the PR base. |
| `install-elan` | `true` | Install the Lean toolchain manager (`elan`) if `lake` is not already on `PATH`. |
| `oracle-jar-url` | `""` | Optional URL for the MCSysMLv2.jar second-source oracle, fetched into `vendor/`. Fetch failures are non-fatal. |
| `oracle-sha256` | `""` | Expected sha256 checksum of the oracle jar; a mismatch discards the fetched jar with a warning. |

## Outputs

| Name | Description |
| --- | --- |
| `regressed` | `"true"` if error findings were introduced relative to the PR base, `"false"` otherwise. |
| `introduced` | Count of findings introduced relative to the PR base. |
| `fixed` | Count of findings fixed relative to the PR base. |
| `verdicts-path` | Path to the head verdicts JSON file (`lake exe sysml check --json` output). |
| `diff-markdown-path` | Path to the rendered `lake exe sysml diff --markdown` output. |

## Notes

- The runner needs network access for the first `elan` install (skipped if
  `lake` is already on `PATH`, e.g. via `leanprover/lean-action`).
- `permissions: pull-requests: write` is required on the calling job for the
  sticky PR comment to be created/updated.
- On non-`pull_request` events (e.g. `push`), the action only computes and
  outputs head verdicts — there is no base to diff against, and no comment
  is posted.

## Marketplace publishing notes

- `action.yml` lives at the repository root (Marketplace requirement), and
  points at `action/dist/index.js`.
- `action/dist/` (the `ncc`-bundled output) **must be committed** — GitHub
  Actions runs the built JS directly, it does not run `npm install`/`npm
  run build` for you.
- Tag releases like `v1`, and keep a moving major-version tag (`v1`)
  pointing at the latest `v1.x.y` release, per GitHub's recommended
  versioning scheme for actions.
