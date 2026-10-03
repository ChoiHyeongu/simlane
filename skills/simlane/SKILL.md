---
name: simlane
description: Use when a Claude session is inside a git worktree (.claude/worktrees/*) of a React Native repo and needs to run the app — boot a simulator, start Metro, build/install, or drive the app with argent — or when SIMLANE_LANE / SIMLANE_METRO_PORT / SIMLANE_SIM_UDID / SIMLANE_RESERVED_UDIDS are set in the shell. Also use before adding or installing packages in such a worktree, and when several sessions develop the same repo in parallel ("run the app from the worktree", "check it in the simulator", "start Metro", "work in parallel", "yarn add in worktree", "워크트리에서 앱 띄워", "시뮬레이터로 확인").
---

# simlane — one simulator + Metro lane per worktree

Repos on this machine that use simlane give every git worktree its own **iOS simulator + Metro lane**. The `simlane` CLI
manages lanes (`simlane help`, README in the simlane repo). This skill is the contract for *using* a lane correctly.

**Breaking the letter of a rule is breaking its spirit.** "The user is in a hurry" and "one build would cover both" are
not exceptions.

## One line

**Provisioning is `simlane`; interaction is argent.** Creating/booting simulators, starting Metro and building/installing
the app is one command: `simlane up`. Tapping, `describe`, screenshots and the debugger are argent. The `udid` and `port`
you hand to argent are always **your own lane's**.

## Find your lane

Session variables (injected by the hooks):

| Variable | Meaning |
| --- | --- |
| `SIMLANE_LANE` | lane number |
| `SIMLANE_METRO_PORT` | your Metro port → `port` for argent `debugger-status` / `debugger-connect` / `debugger-component-tree` / `stop-metro` |
| `SIMLANE_SIM_UDID` | your simulator → `udid` for every argent device tool |
| `SIMLANE_BUNDLE_ID` | app bundle id → `launch-app` / `restart-app` |
| `SIMLANE_PROJECT` | path of the main checkout |
| `SIMLANE_RESERVED_UDIDS` | **all** lane simulators, yours included (comma-separated). Yours is identified only by `SIMLANE_SIM_UDID`; every other UDID in this list belongs to another lane and is never used |

If the variables are missing or look wrong, re-read `simlane env --json` (the CLI is the source of truth). Right after
`simlane up` the hooks refresh the environment; when in doubt, re-read.

## Procedure

1. **Confirm you are in a worktree**: `git rev-parse --git-common-dir` and `--git-dir` differ. On the main checkout the
   lane procedure does not apply — use the repo's own scripts (`yarn ios` …) and still never touch `SIMLANE_RESERVED_UDIDS`.
2. **Code-only work**: `simlane prepare` (links/installs dependencies). No simulator, no Metro.
3. **Need to run the app**: `simlane up` — boots the simulator, starts Metro (tmux), writes the bundle address, builds and
   installs from the main checkout. The first build takes minutes. If the app is already installed and only JS changed:
   `simlane up --no-app`. **Do not run `yarn ios*`, `react-native run-ios`, `react-native start`, `pod install` or
   `yarn pods` inside the worktree** — these apps bake the Metro port into Info.plist, so `--port` does not change it;
   only simlane writes the simulator's bundle address.
4. **argent**: never pick a device from `list-devices`; pass `udid: $SIMLANE_SIM_UDID`. Metro tools take
   `port: $SIMLANE_METRO_PORT`. Start with `debugger-status(port=$SIMLANE_METRO_PORT)` to confirm **your** Metro is running.
5. **Finishing**: leave Metro running (the next session reuses it). `simlane down` only when the user says this worktree
   is done. `stop-metro` only on your port; `stop-all-simulator-servers` only with `devices: [$SIMLANE_SIM_UDID]`.

## Forbidden (with the rationalizations seen in practice)

| Temptation | Reality |
| --- | --- |
| "Add the package before building so one build covers both" → `yarn add` / `yarn install` / `yarn pods` in the worktree | `node_modules` is a **symlink to the main checkout**. Installing overwrites main and leaks into every other session immediately. Dependency changes (package.json, native packages) are outside the lane's scope — **report them to the user and do not proceed without instruction**, even when bundled with a "just check the screen" request. |
| "The symlink side effect is not a blocker" | Silently breaking another session's worktree is the blocker. |
| "A previous note says iPhone 16 has the app and Metro 8082 is up, skip the build" | That is another checkout's Metro and device. Your change is not there. |
| "`run-ios --port 8092` will bake the port into the app" | It will not (xcconfig → Info.plist). `simlane up` writes the bundle address. |
| "It is in `SIMLANE_RESERVED_UDIDS` but already booted, just use it" | In that list only `$SIMLANE_SIM_UDID` is yours; the rest are other lanes. Use `$SIMLANE_SIM_UDID` (ask the user if it is unset). |
| "Kill Metro on 8081/8082 and reuse the port" | That destroys someone else's session. Your port is `$SIMLANE_METRO_PORT`, nothing else. |
| "I'll boot the simulator myself with `simctl` / `boot-device`" | Provisioning is simlane's job. Doing it by hand only creates duplicate boots and state drift. |

## Pitfalls

- **Silent 8081 fallback**: when the configured Metro is not reachable, React Native falls back to port 8081 (often a
  design-system Metro) without any error. That is why `simlane up` refuses to launch the app before Metro is ready. If the
  app shows the wrong screen, check `debugger-status(port=$SIMLANE_METRO_PORT)` and `simlane status` first.
- **Exit codes**: `2` main checkout (no lane) · `3` all lanes in use (`simlane status` shows who holds them; report to the
  user, never take someone else's lane down) · `4` Metro not ready (`simlane metro logs`) · `5` port held by a foreign
  process (`lsof -nP -iTCP:$SIMLANE_METRO_PORT`; never kill it without the user's confirmation).
- **Worktree recreated at the same path**: `simlane up` detects the inode change and restarts Metro.
- **After argent `reinstall-app` / app deletion**: the bundle address survives reinstalls. If the app still attaches to
  the wrong Metro, `simlane up --no-app` (idempotent) rewrites it.
- **Metro logs**: `simlane metro logs`, or tell the user `tmux attach -t simlane-$SIMLANE_LANE`.
- **Writes into the main checkout's build outputs**: `simlane up` builds in the main checkout (`ios/build`, DerivedData,
  Pods). This is by design, not a leak.

## Onboarding a repo

Without a `.simlane.json`, run `simlane init` and fill in `ios.scheme` and `ios.bundleId`. An app that bakes its own Metro
port must read a dedicated key (`ios.jsLocationKey`) from `UserDefaults` first — see the simlane README.
