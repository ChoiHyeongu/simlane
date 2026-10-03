# Release pipeline and versioning — design

Date: 2026-10-03 · Status: approved in conversation, pending spec review

## Goal

Make simlane installable and upgradable by people outside the maintainer's machine — it is a public open-source
project — through Homebrew, with releases that are reproducible from public CI logs and a version that a running
`simlane` can report.

Success looks like:

- `brew install choihyeongu/tap/simlane` then `simlane setup --hooks` gives a working install; `brew upgrade simlane`
  keeps the skill and the hooks working without re-running anything.
- A release is `scripts/release.sh X.Y.Z` on the maintainer's machine; everything after the tag push is CI.
- Every PR runs the test suite on macOS' stock `/bin/bash` 3.2.

## Decisions (and why)

| decision | choice | reason |
| --- | --- | --- |
| audience | public OSS | the maintainer wants other people to use it |
| install channel | own tap `ChoiHyeongu/homebrew-tap` | industry default before homebrew-core (Bun, Supabase, GoReleaser, Charm); one-line install; move to homebrew-core once notable |
| git clone install | kept, for contributors | `scripts/install.sh` stays; README moves it under "Contributing" |
| automation | tag push → CI does Release + tap bump | releases are reproducible from public logs; a co-maintainer only needs to push a tag |
| version source | `VERSION` file | Homebrew installs from a tarball without `.git`, so `git describe` is unavailable |
| versioning | SemVer; in 0.x breaking = minor | breaking means: exit codes, `.simlane.json` schema, `SIMLANE_*` variables, CLI flags |
| changelog | `## Unreleased` section (Keep a Changelog) | contributors add their line in the PR; the release script dates it |

Out of scope (YAGNI): pre-release channels (`-rc`), generated release notes, signing, `curl | bash` installer, Linux,
`simlane setup --remove`, homebrew-core submission.

## Components

### simlane repository

| path | status | role |
| --- | --- | --- |
| `VERSION` | new | single line, e.g. `0.2.0` |
| `bin/simlane` | changed | `--version` / `version` print `VERSION`; usage lists `setup` |
| `lib/common.sh` | changed | `simlane::stable_home` (below) |
| `lib/cmd/setup.sh` | new | `simlane setup [--hooks]` |
| `scripts/install.sh` | changed | links `~/bin/simlane`, then runs `simlane setup` |
| `scripts/install-claude-hooks.sh` | removed | logic moves into `simlane setup --hooks`; no compatibility wrapper (only the maintainer used it) |
| `scripts/release.sh` | new | local release preparation |
| `scripts/changelog-section.sh` | new | print one version's CHANGELOG section |
| `scripts/check-release.sh` | new | assert tag == `VERSION` == top CHANGELOG version |
| `scripts/update-formula.sh` | new | rewrite `url` + `sha256` in a formula; no-op if already current |
| `.github/workflows/ci.yml` | new | PR + push to main: bats, shellcheck, actionlint on `macos-latest`; also `workflow_call` |
| `.github/workflows/release.yml` | new | on `v*` tag: steps 6–11 below |
| `.shellcheckrc` | new | disable checks that are intentional project-wide (SC1090 dynamic `source`); per-line directives elsewhere |
| `CONTRIBUTING.md` | new | bash 3.2 rules, assert helpers, TDD, fakes, changelog, releasing |
| `.github/ISSUE_TEMPLATE/` | new | bug report (macOS/Xcode/simlane version, `simlane status` output), feature request |
| `README.md`, `README.ko.md` | changed | brew install + `simlane setup`; clone install under Contributing; uninstall notes |
| `CHANGELOG.md` | changed | add `## Unreleased` on top |
| `CLAUDE.md` | changed | layout table (setup, scripts, workflows), Releasing section points to `scripts/release.sh` |

### `ChoiHyeongu/homebrew-tap` repository (new, created by hand once)

- `Formula/simlane.rb`: `desc`, `homepage`, `url` (tag tarball), `sha256`, `license`, `depends_on "jq"`,
  `depends_on "tmux"`, `install` (`libexec.install Dir["*"]`, `bin.install_symlink libexec/"bin/simlane"`),
  `test do` (`simlane --version` equals the formula version), `caveats` (run `simlane setup --hooks`; how to remove
  the skill link and the hook entries).
- `README.md`: one-line install.

The only coupling between the two repositories is the CI commit that changes `url` and `sha256`.

## Release flow

```
scripts/release.sh 0.2.0                (maintainer machine)
  1 preconditions  2 bats  3 date CHANGELOG + write VERSION  4 commit + annotated tag  5 confirm, push
        │ tag v0.2.0
release.yml                             (GitHub Actions, macOS)
  6 check-release  7 tests (ci.yml via workflow_call)  8 GitHub Release
  9 tarball sha256  10 update formula, brew install + brew test from the local tap checkout  11 push tap
```

1. Preconditions — on `main`, clean tree, `HEAD == origin/main` after fetch, argument is `X.Y.Z` and greater than
   `VERSION`, tag does not exist locally or on origin, `## Unreleased` is non-empty. Any failure exits before a file
   is touched.
2. `bats tests/`.
3. Rename `## Unreleased` to `## X.Y.Z — YYYY-MM-DD`, insert a new empty `## Unreleased` above it, write `VERSION`.
4. Commit `chore(release): X.Y.Z`; `git tag -a vX.Y.Z -m "simlane X.Y.Z"`.
5. Prompt `push main and vX.Y.Z to origin? [y/N]`. On no: print the undo commands (`git tag -d vX.Y.Z`,
   `git reset --hard HEAD~1`) and exit 0.
6. `scripts/check-release.sh "$GITHUB_REF_NAME"`; also assert the tag commit is an ancestor of `origin/main`.
7. Reuse `ci.yml` through `workflow_call`.
8. `gh release create vX.Y.Z --notes-file <(scripts/changelog-section.sh X.Y.Z)`; skipped if the release exists.
9. Download `https://github.com/ChoiHyeongu/simlane/archive/refs/tags/vX.Y.Z.tar.gz` with retries; `shasum -a 256`.
10. Check out the tap with `TAP_GITHUB_TOKEN`, run `scripts/update-formula.sh`, then `brew tap` the checkout and
    `brew install` + `brew test` the formula on the runner.
11. Commit `simlane X.Y.Z` to the tap and push; no-op if the formula was already current.

`release.yml` uses `concurrency: release` so two releases never race on the tap.

`v0.1.0` stays as it is. The first tap release is `0.2.0`, the first version with `VERSION`, `--version` and `setup`.

## `simlane setup` and paths

Problem: under Homebrew, `bin/simlane` resolves `SIMLANE_HOME` (via `readlink -f`) to
`<prefix>/Cellar/simlane/<version>/libexec`. Anything outside pointing there breaks when `brew cleanup` removes the
old version after an upgrade.

`simlane::stable_home` prints the path outside references must use:

- `SIMLANE_HOME` matches `*/Cellar/simlane/*/libexec` → `<prefix>/opt/simlane/libexec`, where `<prefix>` is the part
  before `/Cellar/`. It does not call `brew` (hooks run on every session event; `brew --prefix` is slow).
- otherwise (git clone) → `SIMLANE_HOME` unchanged.

`simlane setup`:

- Link `~/.claude/skills/simlane` → `<stable_home>/skills/simlane`.
- Same target already → print `already linked`. Different symlink → replace it and print the old target. Real
  directory → refuse with exit 1 (current `install.sh` behaviour).

`simlane setup --hooks` (the skill link, plus):

- Port the jq logic of `install-claude-hooks.sh`: backup before writing, idempotent per event, `CLAUDE_SETTINGS`
  override for tests.
- Hook command uses an absolute path fixed at setup time:
  `[ -x "<stable_home>/bin/simlane" ] && "<stable_home>/bin/simlane" claude-hook || true`. It does not rely on
  `PATH`, which GUI-launched Claude Code may not share with the login shell.
- Stale-entry replacement only touches commands that invoke a `simlane` binary with `claude-hook` (any path, including
  the old `$HOME/bin/simlane`). Other tools' `claude-hook` entries are kept. This reverses the current expectation in
  `tests/install_hooks.bats` (the `oldtool` case).

After `brew uninstall`, a left-over hook is inert because of the `[ -x … ]` guard; the dangling skill link is removed
by hand (README + caveats).

## Failure handling

| failure | public state | recovery |
| --- | --- | --- |
| release.sh preconditions or bats | nothing | fix, re-run |
| push declined | nothing | printed undo commands |
| CI steps 6–7 | tag only | delete the remote tag, fix, release the same version again |
| CI steps 8–11 (e.g. expired token) | Release exists, tap still on the old version (users unaffected) | fix the cause, `gh run rerun`; steps 8 and 11 are idempotent |
| released version is broken | everything | never move a published tag (the sha256 would change); ship a patch release |

`CONTRIBUTING.md` documents this table and the yearly `TAP_GITHUB_TOKEN` rotation (fine-grained PAT, contents:write on
`homebrew-tap` only).

## Testing

Logic lives in scripts covered by bats; workflow YAML only calls them. TDD as usual.

- `simlane --version` prints `VERSION`.
- `simlane::stable_home` for a fake Cellar path and a clone path.
- `simlane setup`: create, idempotent, replace a different symlink, refuse a real directory (moved from
  `tests/install.bats`).
- `simlane setup --hooks`: absolute path, other tools' hooks preserved, old `$HOME/bin/simlane` entry replaced, backup
  written (moved from `tests/install_hooks.bats`).
- `scripts/install.sh`: links `~/bin/simlane` and runs setup.
- `scripts/release.sh`: in a temp repo with a local bare repository as `origin` (real git, no network) — each
  precondition failure leaves the tree untouched, CHANGELOG/VERSION rewrite, declined push prints undo commands,
  accepted push lands commit + tag in the bare repo.
- `scripts/changelog-section.sh`, `scripts/check-release.sh`, `scripts/update-formula.sh` against fixture files.
- CI: `actionlint` catches workflow errors before a tag; the first real release (0.2.0) is the end-to-end test, with
  step 10 validating the formula.
- `tests/rename_guard.bats` already scans new files.
