# simlane

git 워크트리마다 iOS 시뮬레이터 + Metro **레인(lane)** 하나씩. 여러 React Native 세션(사람이든 코딩 에이전트든)이 같은 레포를
포트·시뮬레이터 충돌 없이 병렬로 개발하게 해 줍니다.

[English README](README.md)

## 왜

RN의 개발 루프는 체크아웃 하나, 8081 Metro 하나, 시뮬레이터 하나를 전제합니다. 워크트리와 병렬 세션이 둘셋 생기면 같은
Metro 포트, 같은 bundle id가 같은 시뮬레이터에 설치되는 충돌이 나고, 최악은 자기 Metro가 없으면 앱이 **에러 없이 8081로
폴백**해 남의 번들을 보게 되는 것입니다.

simlane은 워크트리마다 레인을 줍니다:

| 레인 N | Metro 포트 | 시뮬레이터 | tmux 세션 |
| --- | --- | --- | --- |
| 1 … `maxLanes` | `portBase + N` (기본 8091…) | `Simlane N` (처음 쓸 때 생성) | `simlane-N` |

- 네이티브 앱은 **main 체크아웃에서 1회** 빌드해 각 레인 시뮬레이터에 설치합니다(JS-only 워크플로우).
- 레인 시뮬레이터의 `NSUserDefaults`(`ios.jsLocationKey`)에 Metro 주소를 써서 같은 바이너리가 시뮬레이터마다 다른 Metro에 붙습니다.
- `simlane up`은 Metro가 `/status`에 답하기 전엔 앱을 올리지 않습니다(8081 가드).
- Claude Code 세션은 훅(`SIMLANE_*`)으로 자기 레인을 알고, 스킬이 규칙을 못 박습니다.

## 요구 사항

macOS 12.3+, Xcode(`xcrun simctl`), `jq`, `tmux` ≥ 3.2, `git` ≥ 2.31. 기본 `/bin/bash` 3.2면 충분합니다.
테스트: `brew install bats-core` 후 `bats tests/`.

## 설치

```sh
brew install choihyeongu/tap/simlane
simlane setup --hooks   # Claude Code 스킬 링크 + 훅 등록 (스킬만 원하면 --hooks 생략)
```

`brew upgrade simlane`으로 업그레이드합니다. 스킬 링크와 훅은 Homebrew의 `opt/simlane` 경로를 가리키므로 업그레이드 후에도
그대로 동작합니다. 제거: `brew uninstall simlane`, `rm ~/.claude/skills/simlane`, `~/.claude/settings.json`에서
`simlane claude-hook` 항목 삭제(남겨 둬도 아무 일도 하지 않습니다).

simlane 자체를 개발하려면 [CONTRIBUTING.md](CONTRIBUTING.md)를 보세요.

## 사용

```sh
cd <레포>/.claude/worktrees/<이름>   # 워크트리 안에서
simlane prepare        # 의존성만 (link: main에서 심링크 / install: 설치 명령 실행)
simlane up [--no-app]  # 레인 → 시뮬 → Metro → 번들 주소 → 빌드·설치·실행
simlane env [--json]   # SIMLANE_LANE SIMLANE_METRO_PORT SIMLANE_SIM_UDID SIMLANE_BUNDLE_ID SIMLANE_PROJECT SIMLANE_RESERVED_UDIDS
simlane status
simlane metro logs|restart
simlane down [N|--all]
simlane gc
```

main 체크아웃에는 레인이 없습니다(`up`은 exit 2). 거기서는 레포의 기존 스크립트를 쓰세요. `env`는 main에서도
`SIMLANE_RESERVED_UDIDS`를 내보내는데, 그 시뮬레이터들은 레인 소유이니 건드리지 않습니다.

## `.simlane.json` (레포 루트, 커밋)

| 키 | 기본값 | 의미 |
| --- | --- | --- |
| `appDir` | `"."` | RN 앱 디렉터리(모노레포면 `apps/mobile`) |
| `ios.scheme` | 필수 | Xcode scheme |
| `ios.bundleId` | 필수 | 번들 주소를 쓸 `NSUserDefaults` 도메인 |
| `ios.buildCommand` | `react-native run-ios --scheme <scheme>` | main `appDir`에서 실행. `{udid}` 플레이스홀더가 없으면 ` --udid <udid> --no-packager`를 붙임 |
| `ios.jsLocationKey` | `RCT_jsLocation` | 앱이 읽는 키. RN 템플릿은 기본 키를 읽고, 포트를 직접 굽는 앱은 전용 키를 읽게 고칩니다(아래) |
| `metro.startCommand` | `react-native start` | 워크트리 `appDir`에서 `--port`를 붙여 실행 |
| `deps.link` | `["node_modules"]` | main에서 심링크할 디렉터리. Metro에 `--watchFolders <main>/<appDir>/node_modules` 부착. **워크트리에서 install 금지** |
| `deps.install` / `deps.after` | — | 있으면 심링크 대신 워크트리 루트에서 실행(pnpm 모노레포) |
| `env` | `[]` | tmux Metro 세션에 `-e`로 넘길 변수 이름 |

전역 설정 `~/.config/simlane/config.json`: `maxLanes`(6), `portBase`(8090), `simulator.deviceType`(`"iPhone 17 Pro"`),
`simulator.runtime`(`"latest"`), `metroReadyTimeoutSec`(60).

### Metro 포트를 직접 굽는 앱

`AppDelegate`가 매 실행 Info.plist 값으로 `jsLocation`을 덮어쓴다면, 전용 키를 먼저 읽게 해서 레인은 덮어쓰고 main은
결정적으로 유지합니다:

```swift
let provider = RCTBundleURLProvider.sharedSettings()
if let lane = UserDefaults.standard.string(forKey: "SimlaneJsLocation"), !lane.isEmpty {
  provider.jsLocation = lane                        // simlane up이 쓰고 simlane down이 지움
} else if let port = Bundle.main.object(forInfoDictionaryKey: "RCT_METRO_PORT") as? String, !port.isEmpty {
  provider.jsLocation = "localhost:\(port)"         // 기존 동작
}
```

그리고 `"ios": { "jsLocationKey": "SimlaneJsLocation" }`로 설정합니다.

### main Metro가 중첩 워크트리를 크롤하지 않게

Metro는 프로젝트 루트 전체(`.claude/worktrees/*` 포함)를 크롤합니다. 설정 파일 자신의 디렉터리에 anchor하면 같은 설정이
main과 워크트리 양쪽에서 옳게 동작합니다:

```js
const path = require("path");
const exclusionList = require("metro-config/private/defaults/exclusionList").default;
const escapeRegExp = (s) => s.replace(/[-[\]{}()*+?.\\^$|]/g, "\\$&");
const nestedWorktrees = new RegExp(escapeRegExp(path.join(__dirname, ".claude", "worktrees")) + "/.*");
config.resolver = { ...config.resolver, blockList: exclusionList([nestedWorktrees]) };
```

## 종료 코드

`2` main 체크아웃 · `3` 레인 고갈 · `4` Metro 미기동(앱 안 올림) · `5` 포트를 남의 프로세스가 점유 · `1` 그 외

## Claude Code 통합

`simlane setup --hooks`가 `SessionStart`·`CwdChanged`·`FileChanged`에 `simlane claude-hook`을 등록합니다. 훅은
`simlane env`를 `CLAUDE_ENV_FILE`에 덧붙이고 레인 레지스트리를 가리키는 `hookSpecificOutput.watchPaths`를 돌려줘,
세션 중 `simlane up`이 실행되면 변수가 갱신됩니다. `skills/simlane/`의 스킬은 provisioning(simlane)과 interaction(argent)의
경계와 금지 사항을 에이전트에게 알려줍니다.

## 설계 노트

레인 모델, 8081 폴백, 실기기로 검증한 것, 테스트 fakes가 일부러 재현하는 함정(tmux 접두 매칭, kill-session 뒤 포트 잔류)은
[docs/design.md](docs/design.md)(영문)를 보세요.

## 라이선스

MIT
