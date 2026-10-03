# Changelog

## Unreleased

- `simlane --version` and a `VERSION` file.

## 0.1.0 — 2026-10-03

First public release.

- `simlane up/down/status/env/prepare/metro/gc/init` — one iOS simulator + Metro lane per git worktree.
- Native build shared from the main checkout; per-simulator bundle address via `NSUserDefaults`.
- Metro-ready guard against React Native's silent fallback to port 8081.
- Claude Code hooks (`claude-hook`) and the `simlane` skill.
- bats test suite with fakes for `xcrun simctl`, `tmux`, `curl` and `lsof`.
