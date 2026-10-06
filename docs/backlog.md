# Backlog

Known gaps, mostly from the first code review. None blocks normal use.

## Robustness
- `down` cannot delete the bundle address when the simulator is shut down (`simctl spawn defaults` needs a booted device); log it and document it.
- `sim_boot` swallows boot failures; check `sim_state == Booted` after `bootstatus` and fail clearly.
- Concurrent `up` for the *same* worktree can create two simulators with the same name (no lock around `sim_ensure`).
- `up` ignores unknown arguments (`--noapp` → full build); reject them.
- An empty/corrupt `lanes.json` is treated as "no lanes" and re-allocates everything; validate with `jq -e` in `registry_read`.
- Broken `~/.config/simlane/config.json` prints the error twice through the exhaustion path; validate once in `main`.
- `sim_count_named` counts unavailable devices too (warns after an Xcode runtime change).
- `deps.link` paths are word-split (only matters for paths with spaces).

## Environment
- Forward `PATH` into the tmux Metro session (`-e PATH`), so Metro runs with the same node as the caller (mise/nvm).
- `install.sh` and `README`: macOS 12.3+ is required for `readlink -f`.

## Features
- `status`: add a PROJECT column.
- Android lanes (`adb shell setprop metro.host`, `-PreactNativeDevServerPort`).
- `--native-from-worktree` for worktrees that change native code.
- Homebrew tap / `curl | bash` installer.

## Setup and release (from the release-pipeline review)
- `setup --hooks`: the jq merge errors on a matcher group without `hooks`, an object-valued event or a non-string
  `command` (settings stay intact, but a `.bak` and a temp file are left); it also drops pre-existing empty groups.
- Stale-hook regex `simlane"? claude-hook`: removes `my-simlane claude-hook` and whole compound commands
  (`echo x; simlane claude-hook`); misses single-quoted paths. Anchor on a path boundary.
- `settings.json` is overwritten with `cat tmp > f` (keeps symlinks, not atomic); the first run backs up the fresh `{}`.
- `simlane setup -h/--help` exits 1 as an unknown argument.
- `release.yml`: scope `contents: write` to the `publish` job; the tarball sha uses `GITHUB_REPOSITORY` while
  `update-formula.sh` hard-codes `ChoiHyeongu/simlane`.

## Tests
- Symlinked `CLAUDE_SETTINGS` keeps its link after `setup --hooks`; a hook group without a `hooks` key.
- Integration test with two real `up` processes contending for the build lock.
- Document fake limitations in `tests/README` (no real `simctl spawn` on unbooted devices, commands are not executed).
