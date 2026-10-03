# Contributing to simlane

## Setup

```sh
git clone https://github.com/ChoiHyeongu/simlane.git
cd simlane
scripts/install.sh            # ~/bin/simlane → this checkout, plus the Claude Code skill (add --hooks for hooks)
brew install bats-core shellcheck actionlint
```

If you also have the Homebrew formula installed, whichever `simlane setup` ran last owns the skill link and hooks.

## Rules

- **bash 3.2** (macOS `/bin/bash`): no `declare -A`, `mapfile`, `${var,,}`, `local -n`; empty arrays expand as
  `${arr[@]+"${arr[@]}"}`.
- Namespace `simlane::`, subcommands `cmd_*`, one subcommand per file in `lib/cmd/`.
- Exit codes, `.simlane.json` fields, `SIMLANE_*` variables and CLI flags are API. Changing them is a breaking change.
- `simlane` only ever touches simulators named `Simlane N`.
- Never run `simlane up/down/gc` against your machine as a test; the suite uses fakes in `tests/fakes/`.

## Tests

```sh
bats tests/
shellcheck bin/simlane lib/*.sh lib/cmd/*.sh scripts/*.sh
actionlint
```

- Write the failing test first.
- Assert with `[ … ]` or the helpers in `tests/test_helper.bash` (`assert_contains`, `assert_not_contains`,
  `assert_endswith`, `assert_fails`). Under bash 3.2 a failing `[[ ]]` on a non-final line, and `! cmd` on any line,
  do **not** fail a bats test.
- CI runs the same three commands on `macos-latest` with the stock `/bin/bash`.

## Pull requests

- Conventional Commits (`feat:`, `fix:`, `docs:` …); `feat!:` / `BREAKING CHANGE:` for API changes.
- Add a line under `## Unreleased` in `CHANGELOG.md` for anything a user would notice.

## Releasing (maintainers)

```sh
scripts/release.sh 0.3.0
```

The script checks that you are on a clean `main` in sync with `origin`, runs the tests, dates the `## Unreleased`
section, writes `VERSION`, commits, tags `v0.3.0`, and asks before pushing. The tag push runs
`.github/workflows/release.yml`: it verifies tag/VERSION/CHANGELOG, runs CI, creates the GitHub Release from the
CHANGELOG section, and updates `Formula/simlane.rb` in
[ChoiHyeongu/homebrew-tap](https://github.com/ChoiHyeongu/homebrew-tap) after installing and testing it on the runner.

SemVer; while 0.x a breaking change bumps the minor version.

| failure | what is public | recovery |
| --- | --- | --- |
| `release.sh` checks or tests | nothing | fix and re-run |
| push declined | nothing | run the printed undo command |
| CI verify/test | the tag | `git push --delete origin vX.Y.Z && git tag -d vX.Y.Z`, fix, release the same version |
| CI publish (e.g. expired token) | the GitHub Release; the tap still serves the previous version | fix the cause, `gh run rerun <run-id>` |
| a released version is broken | everything | never move a published tag; release a patch |

`TAP_GITHUB_TOKEN` is a fine-grained personal access token with *Contents: read and write* on `homebrew-tap` only.
It expires; renew it (at most yearly) with `gh secret set TAP_GITHUB_TOKEN --repo ChoiHyeongu/simlane`.
