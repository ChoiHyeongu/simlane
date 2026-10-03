# simlane

One iOS simulator + Metro bundler **lane** per git worktree, so several React Native sessions (people or coding agents)
can work on the same repo in parallel without fighting over ports and simulators.

[한국어 README](README.ko.md)

## Why

React Native's dev loop assumes one checkout, one Metro on 8081, one simulator. Add git worktrees and two or three
parallel sessions and everything collides: the same Metro port, the same bundle id installed on the same simulator, and
— worst of all — an app that **silently** falls back to port 8081 when its own Metro is not there, so you end up looking
at someone else's bundle without an error.

simlane gives each worktree a lane:

| lane N | Metro port | simulator | tmux session |
| --- | --- | --- | --- |
| 1 … `maxLanes` | `portBase + N` (default 8091…) | `Simlane N` (created on first use) | `simlane-N` |

- The native app is built **once, from the main checkout**, and installed on each lane's simulator (JS-only workflow).
- Each lane's simulator gets the Metro address written into the app's `NSUserDefaults` (`ios.jsLocationKey`), so the
  same binary attaches to the right Metro on every simulator.
- `simlane up` never launches the app before Metro answers `/status` — that is the 8081 guard.
- Claude Code sessions learn their lane through hooks (`SIMLANE_*` variables) and a skill that spells out the rules.

## Requirements

macOS 12.3+, Xcode (`xcrun simctl`), `jq`, `tmux` ≥ 3.2, `git` ≥ 2.31, stock `/bin/bash` 3.2 is enough.
Tests: `brew install bats-core`, then `bats tests/`.

## Install

```sh
git clone https://github.com/ChoiHyeongu/simlane.git ~/.local/share/simlane
~/.local/share/simlane/scripts/install.sh              # ~/bin/simlane, ~/.claude/skills/simlane
~/.local/share/simlane/scripts/install-claude-hooks.sh # hooks in ~/.claude/settings.json (optional, for Claude Code)
```

## Usage

```sh
cd <repo>/.claude/worktrees/<name>   # inside a worktree
simlane prepare        # dependencies only (link: symlink from main / install: run the install command)
simlane up [--no-app]  # lane → simulator → Metro → bundle address → build/install/launch
simlane env [--json]   # SIMLANE_LANE SIMLANE_METRO_PORT SIMLANE_SIM_UDID SIMLANE_BUNDLE_ID SIMLANE_PROJECT SIMLANE_RESERVED_UDIDS
simlane status
simlane metro logs|restart
simlane down [N|--all]
simlane gc
```

The main checkout has no lane (`up` exits 2); use your repo's own scripts there. `env` still exports
`SIMLANE_RESERVED_UDIDS` on the main checkout — those simulators belong to lanes, leave them alone.

## `.simlane.json` (repo root, committed)

| key | default | meaning |
| --- | --- | --- |
| `appDir` | `"."` | RN app directory (`apps/mobile` in a monorepo) |
| `ios.scheme` | required | Xcode scheme |
| `ios.bundleId` | required | the `NSUserDefaults` domain the bundle address is written to |
| `ios.buildCommand` | `react-native run-ios --scheme <scheme>` | run in the main `appDir`; without a `{udid}` placeholder, ` --udid <udid> --no-packager` is appended |
| `ios.jsLocationKey` | `RCT_jsLocation` | the key the app reads. The RN template reads the default key; an app that bakes its own port should read a dedicated key (see below) |
| `metro.startCommand` | `react-native start` | run in the worktree `appDir` with `--port` appended |
| `deps.link` | `["node_modules"]` | directories symlinked from the main checkout; Metro gets `--watchFolders <main>/<appDir>/node_modules`. **Never run install inside the worktree** |
| `deps.install` / `deps.after` | — | if present, run at the worktree root instead of linking (pnpm monorepos) |
| `env` | `[]` | variable names forwarded into the tmux Metro session with `-e` |

Global config `~/.config/simlane/config.json`: `maxLanes` (6), `portBase` (8090), `simulator.deviceType`
(`"iPhone 17 Pro"`), `simulator.runtime` (`"latest"`), `metroReadyTimeoutSec` (60).

### Apps that bake their Metro port

If your `AppDelegate` sets `RCTBundleURLProvider.jsLocation` from Info.plist on every launch, read a dedicated key first
so lanes can override it while the main checkout stays deterministic:

```swift
let provider = RCTBundleURLProvider.sharedSettings()
if let lane = UserDefaults.standard.string(forKey: "SimlaneJsLocation"), !lane.isEmpty {
  provider.jsLocation = lane                        // written by `simlane up`, deleted by `simlane down`
} else if let port = Bundle.main.object(forInfoDictionaryKey: "RCT_METRO_PORT") as? String, !port.isEmpty {
  provider.jsLocation = "localhost:\(port)"         // your existing behaviour
}
```

and set `"ios": { "jsLocationKey": "SimlaneJsLocation" }`.

### Keep the main Metro out of nested worktrees

Metro crawls the whole project root, including `.claude/worktrees/*`. Anchor the block list to the config file's own
directory so the same config works from main and from a worktree:

```js
const path = require("path");
const exclusionList = require("metro-config/private/defaults/exclusionList").default;
const escapeRegExp = (s) => s.replace(/[-[\]{}()*+?.\\^$|]/g, "\\$&");
const nestedWorktrees = new RegExp(escapeRegExp(path.join(__dirname, ".claude", "worktrees")) + "/.*");
config.resolver = { ...config.resolver, blockList: exclusionList([nestedWorktrees]) };
```

## Exit codes

`2` main checkout · `3` all lanes in use · `4` Metro not ready (app not launched) · `5` port held by a foreign process · `1` anything else

## Claude Code integration

`scripts/install-claude-hooks.sh` registers `simlane claude-hook` for `SessionStart`, `CwdChanged` and `FileChanged`.
The hook appends `simlane env` to `CLAUDE_ENV_FILE` and returns `hookSpecificOutput.watchPaths` pointing at the lane
registry, so the variables refresh when `simlane up` runs mid-session. The skill in `skills/simlane/` tells the agent what
is provisioning (simlane) and what is interaction (argent), and which shortcuts are forbidden.

## Design notes

See [docs/design.md](docs/design.md) for the lane model, the 8081 fallback, what was verified against real devices and
which pitfalls the test fakes deliberately reproduce (tmux prefix matching, ports lingering after `kill-session`).

## License

MIT
