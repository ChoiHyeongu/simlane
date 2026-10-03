# CLAUDE.md — simlane

One iOS simulator + Metro bundler **lane** per git worktree, so parallel React Native sessions (people or coding agents)
never collide on ports, simulators or bundles. Read `README.md` for usage and `docs/design.md` for the model and the
facts that were verified on real devices. `docs/backlog.md` lists known gaps.

## Layout

| path | role |
| --- | --- |
| `bin/simlane` | entry point: sources `lib/*.sh` and `lib/cmd/*.sh`, dispatches subcommands |
| `lib/common.sh` | exit codes (`SIMLANE_EXIT_*`), `simlane::log/die`, global config (`~/.config/simlane/config.json` deep-merged over defaults) |
| `lib/lock.sh` | mkdir locks with pid + stale recovery; every registry write happens under the `registry` lock |
| `lib/worktree.sh` | worktree detection, `.simlane.json` load/validate (`simlane::project_config`) |
| `lib/registry.sh` | `~/.config/simlane/lanes.json`, lane allocation, dead-worktree reclaim, inode |
| `lib/simulator.sh` | `xcrun simctl` wrappers — only ever touches devices named `Simlane N` |
| `lib/metro.sh` | tmux session `simlane-N`, `/status` probe, `metro_wait_ready` / `metro_wait_free` |
| `lib/deps.sh`, `lib/app.sh` | dependency strategies (`link` / `install`), app build in the main checkout |
| `lib/cmd/*.sh` | one subcommand per file: `prepare up down status env metro gc init claude-hook` |
| `scripts/` | `install.sh` (symlinks), `install-claude-hooks.sh` (Claude Code hooks, idempotent, replaces stale entries) |
| `skills/simlane/SKILL.md` | the Claude Code skill (symlinked into `~/.claude/skills/simlane` by `install.sh`) |
| `tests/` | bats suite; `tests/fakes/` replaces `xcrun`, `tmux`, `curl`, `lsof` and the build command |

## Conventions

- **bash 3.2 compatible** (macOS stock `/bin/bash`): no `declare -A`, `mapfile`, `${var,,}`, `local -n`; empty arrays expand
  as `${arr[@]+"${arr[@]}"}`. `bin/simlane` runs with `set -euo pipefail`; `lib/*.sh` are sourced and must not set it.
- Function namespace `simlane::`, subcommands `cmd_*`. Messages, comments, test names: English. Conversation with the
  maintainer (@able) is in Korean.
- The ordering in `cmd_up` is the product contract: **Metro ready → bundle address → app**. Never launch the app before
  Metro answers (`/status` → `packager-status:running`) — React Native silently falls back to port 8081 otherwise.
- `simlane` only creates/boots/shuts down/writes defaults on simulators named `Simlane N`. Never touch other devices.
- Exit codes are API: `2` main checkout · `3` lanes exhausted · `4` Metro not ready · `5` port held by a foreign process.
- Conventional Commits in English; end commit messages with
  `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`. Don't push or force-push unless asked.

## Tests

```sh
brew install bats-core   # once
bats tests/              # whole suite; a single file: bats tests/metro.bats
```

- TDD: write the failing test first, watch it fail, then implement.
- **Assertions must be function helpers** from `tests/test_helper.bash` (`assert_contains`, `assert_not_contains`,
  `assert_endswith`, `assert_fails`). Under bash 3.2 a failing `[[ ]]` on a non-final line and `! cmd` on any line do **not**
  fail a bats test. `tests/common.bats` has a meta-test that pins this.
- `tests/rename_guard.bats` fails if any legacy `rn-slot` identifier reappears.
- The fakes deliberately reproduce real behaviour: tmux `-t` prefix matching (always use `=name`), ports lingering after
  `kill-session` (`FAKE_METRO_LINGER_SEC`), `FAKE_METRO_NEVER_READY`, `FAKE_BUILD_EXIT`. If you change a fake, check
  `docs/design.md` "Things the test fakes reproduce on purpose".
- Never run `simlane up/down/gc` against the real machine as a "test"; `simlane help|env|status` are read-only and fine.

## Releasing

Bump `CHANGELOG.md`, commit, `git tag -a vX.Y.Z -m "simlane X.Y.Z"`, push the tag (only when the maintainer asks).
