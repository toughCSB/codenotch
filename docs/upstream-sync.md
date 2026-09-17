# upstream(원본 Codenotch) 반영 전략

이 포크는 [vinzdg/codenotch](https://github.com/vinzdg/codenotch)의 포크다. 원본은 계속 업데이트되므로,
그 변경을 어떻게 가져올지가 유지보수의 전부라고 해도 된다. 2026-09-17에 1.13.1을 병합하면서 확정한
방식을 여기에 남긴다.

## 결론

- **merge로 가져온다.** `git fetch upstream && git merge upstream/main`. rebase는 쓰지 않는다 —
  포크에 이미 공개한 커밋 해시가 전부 바뀌고, 그 위에 올린 빌드·릴리스 이력이 끊긴다.
- **macOS(`Sources/`)는 upstream이 정본이다.** 충돌하면 upstream 것을 기본으로 채택하고, 우리가
  일부러 다르게 만든 것(앱 이름·번들 ID, 잔여량 기준, 링 주기 전환, 한국어)만 우리 것을 유지한다.
- **`windows/`는 upstream과 합치지 않는다.** upstream에도 Windows 포트가 있지만 이 포크의 포트와는
  같은 기능을 각자 구현한 **다른 코드**다. 파일 단위로 섞으면 컴파일도 안 되고, 애써 맞춘 화면도
  무너진다. upstream Windows 수정 중 필요한 것만 골라 손으로 옮긴다.
- **`windows/`의 실질 검증은 GitHub Actions에서만 가능하다.** `rustup`도 크로스 타깃도 없는 맥에서는
  `cargo`가 Windows용 코드를 컴파일하지 못한다. `.github/workflows/windows-package.yml`을
  `workflow_dispatch`로 돌려 컴파일 + 설치 + `doctor` + 제거까지 확인한다.

## 파일별 충돌 정책

| 대상 | 정책 | 이유 |
| --- | --- | --- |
| `Sources/**` (macOS 앱) | upstream 채택, 우리 의도적 변경은 유지 | 같은 코드베이스의 포크다 |
| `Sources/Settings/RingCadence.swift` 같은 포크 전용 파일 | 우리 것 유지 | upstream에 없다 |
| `Sources/Localizable.xcstrings` | 키 **합집합**. 같은 키는 `ko`가 있는 우리 것 유지 | 번역을 잃지 않는다 |
| `.github/workflows/**` | upstream 채택 | CI 정의는 원본을 따른다 |
| `windows/**` | **우리 것 유지** — `git checkout HEAD -- windows/` | 위 참조 |
| `project.yml` | downstream 버전·번들 ID·Sparkle 정책은 우리 것, upstream 설정 변경은 채택 | |

같은 키라도 **upstream이 더 새것이면 upstream 값을 택한다.** 이번에 `%lld%% of its %@ limit used.`의
zh-Hans 번역이 순서만 바꿔 놓은 채 남아 있었고(1.13.1에서 upstream이 `%1$lld`/`%2$@`로 고쳤다),
우리 값을 유지하는 규칙 때문에 그 수정이 되돌아가 `CatalogFormatTests`가 잡아냈다. 그건 #237의
중국어 크래시 그 자체다.

## 절차

```bash
git fetch upstream --tags
git switch -c merge/upstream-<버전> main
git merge upstream/main
# 충돌 해결: 위 표
git diff --name-only --diff-filter=U      # 남은 충돌이 0인지 확인
```

번역 누락은 손으로 찾지 않는다. Xcode에게 물어본다:

```bash
D=$(mktemp -d)
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -exportLocalizations -localizationPath "$D" \
  -project ProviderMonitor.xcodeproj -exportLanguage en
```

이 명령은 소스에서 참조되는 문자열을 추출해 `Sources/Localizable.xcstrings`에 없는 키를 직접
추가해 준다. 새로 들어온 키는 `ko` 번역이 없으므로 채워 넣는다.

검증:

```bash
make test          # 0 failures
```

Windows는 맥에서 컴파일할 수 없으므로 CI로 넘긴다:

```bash
gh workflow run windows-package.yml --repo toughCSB/codenotch --ref <브랜치>
gh run watch --repo toughCSB/codenotch
```

## 이번 병합(1.13.1)에서 실제로 내린 판단

- `Sources/Sessions/CodexActivityMonitor.swift`: 우리는 호버 지연을 커서(증분 읽기)로 고쳤고,
  upstream은 역방향 256KB 윈도 스캔으로 다시 썼다. **upstream 것을 채택했다.** 성능 목표가 같고,
  이후 다듬어진 쪽이 upstream이며, 앞으로의 병합 비용이 0이 된다. 대신 1MB보다 뒤에 있는 라이프사이클
  이벤트는 찾지 않는 명시적 상한이 생긴다(진행 중 턴은 그대로 `busy`로 답한다).
- `windows/codenotch/src/traymenu.rs`, `windows/scripts/check-ui-scripts.mjs`는 upstream 쪽
  추가분이라 병합 결과에서 제외했다. 앞의 것은 우리 `tray.rs`와 맞물려 있어 단독으로는 컴파일되지
  않고, 뒤의 것은 upstream `windows.yml`이 부르는 스크립트라 남겨 두었다.
- 카탈로그는 키 합집합 668개에서 시작해 Xcode 추출로 819개가 됐다. 자세한 수치는 커밋 메시지에 있다.

## 릴리스

macOS:

```bash
make release      # Developer ID로 서명하고 notarytool로 공증. 자격증명 필요
make dmg-ci       # 서명 자격증명이 없을 때: ad-hoc 서명 dmg
make publish      # 이미 있는 태그의 릴리스에 dmg 첨부
```

`make release`는 Developer ID 인증서와 `xcrun notarytool store-credentials UsageNotch` 프로필이
둘 다 있어야 한다. 없으면 `make dmg-ci`로 만든 dmg를 쓴다 — 서명도 공증도 없으므로 받는 사람이
Gatekeeper에서 **우클릭 → 열기**를 한 번 해야 하고, 업데이트마다 키체인 허용을 다시 묻는다.

Windows: `windows-package.yml`이 `workflow_dispatch`로 실행되면 NSIS 설치 프로그램을 만들어
설치·`doctor`·제거까지 스스로 확인한다. 릴리스에 첨부하려면 artifact를 받아
`gh release upload <태그> Codenotch-Setup.exe`로 올린다.

