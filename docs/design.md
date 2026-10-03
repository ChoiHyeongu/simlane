# simlane design notes

## The problem

A React Native dev loop binds three things to one checkout: Metro on a fixed port, an app binary installed under a fixed
bundle id, and a simulator. With git worktrees and parallel sessions those collide — and the failure is silent:
`RCTBundleURLProvider` probes the configured Metro, and when it does not answer it falls back to the compile-time port
(8081) **without an error**. If another Metro happens to be on 8081 the app loads someone else's bundle.

## The lane model

A lane is a machine-global resource that a worktree borrows:

- lane `N` ⇒ Metro port `portBase + N`, simulator named `Simlane N` (created lazily), tmux session `simlane-N`.
- The registry `~/.config/simlane/lanes.json` maps worktree path → lane (with the directory inode, so a worktree deleted
  and recreated at the same path is detected and its Metro restarted).
- Lanes are project-agnostic: one simulator can host apps from different repos because the bundle address is stored per
  bundle id.
- The main checkout has no lane. It keeps working exactly as before.

## One native build, many simulators

Worktree work is mostly JavaScript. Building natively per worktree costs a full Xcode build each (DerivedData is keyed by
project path). So `simlane up` builds **in the main checkout** with `--udid <lane simulator> --no-packager` and installs
the result on the lane's simulator. The simulator's `NSUserDefaults` for the bundle id gets `localhost:<port>` under
`ios.jsLocationKey`, which `RCTBundleURLProvider` reads (`RCT_jsLocation` by default).

Verified on a real device:

- A key written with `xcrun simctl spawn <udid> defaults write <bundleId> …` is read by the app on launch.
- The app's own writes are *not* visible to `simctl spawn defaults read` (one-way). A dedicated key written only by
  simlane avoids any conflict with keys the app writes itself.
- The key survives uninstall + reinstall of the app.

## Ordering is the contract

`up` = allocate lane → ensure/boot simulator → apply the dependency strategy → start Metro in tmux → **wait for
`/status` to report `packager-status:running`** → write the bundle address → build/install/launch. If Metro never comes
up the app is not launched (exit 4): launching it would trigger the silent 8081 fallback.

## Dependency strategies

- `link` (yarn single-package repos): symlink `node_modules` from the main checkout into the worktree and start Metro with
  `--watchFolders <main>/node_modules` (symlink real paths must be inside a watched folder). Never install inside the
  worktree — it would write into the main checkout.
- `install` (pnpm monorepos): run the install command (and an optional `after`) at the worktree root; Metro config stays
  untouched.

## Claude Code integration

Three hook events (`SessionStart`, `CwdChanged`, `FileChanged`) run the same `simlane claude-hook`. It appends `simlane
env` to `CLAUDE_ENV_FILE` and returns `{"hookSpecificOutput":{"hookEventName":…,"watchPaths":[<registry>]}}`. The
`hookSpecificOutput` form matters for every event: a top-level `{"watchPaths":[…]}` is ignored and the watch is dropped
after the next `cd`. On the main checkout `env` still exports `SIMLANE_RESERVED_UDIDS` so an agent there never grabs a
lane simulator by "first booted device".

## Things the test fakes reproduce on purpose

- `tmux -t name` matches by **prefix** (`simlane-1` matches `simlane-10`); every target carries the `=` exact-match prefix.
- `tmux kill-session` only sends SIGHUP; the Metro port lingers for a moment, so a restart waits for the port to be free.
- `grep -c` prints `0` *and* exits 1 on no match.
- Under bash 3.2 (+bats) a failing `[[ ]]` on a non-final line does not fail the test, and `! cmd` never does; assertions
  are function helpers.

## Known limits

- iOS only. Android would follow the same model (`adb shell setprop metro.host`, `-PreactNativeDevServerPort`).
- Native changes inside a worktree are out of scope for the JS-only build sharing; build from that worktree yourself.
- `WorktreeCreate`/`WorktreeRemove` hooks are not used: the former replaces git's own worktree logic, the latter makes the
  hook responsible for deleting the directory. `simlane gc` reclaims lanes whose worktree is gone instead.
