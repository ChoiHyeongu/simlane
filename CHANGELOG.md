# Changelog

## Unreleased

## 0.2.0 — 2026-10-06

- `simlane --version` and a `VERSION` file.
- `simlane setup [--hooks]` links the Claude Code skill and registers the hooks; replaces
  `scripts/install-claude-hooks.sh`. Paths survive `brew upgrade`.
- Hook registration no longer removes other tools' `claude-hook` entries.
- Homebrew tap: `brew install choihyeongu/tap/simlane`.
- CI on macOS bash 3.2 (bats, shellcheck, actionlint) and tag-driven releases.

## 0.1.0 — 2026-10-03

First public release.

- `simlane up/down/status/env/prepare/metro/gc/init` — one iOS simulator + Metro lane per git worktree.
- Native build shared from the main checkout; per-simulator bundle address via `NSUserDefaults`.
- Metro-ready guard against React Native's silent fallback to port 8081.
- Claude Code hooks (`claude-hook`) and the `simlane` skill.
- bats test suite with fakes for `xcrun simctl`, `tmux`, `curl` and `lsof`.
