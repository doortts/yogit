# yogit

`yo`를 현재 Git 저장소에서 실행하면 macOS용 커밋 타임라인과 diff 창이 열립니다.

## 준비

- macOS와 Flutter 3.41.8 이상
- Git
- GitHub 또는 GHE 아바타를 표시하려면 GitHub CLI(`gh`)

```sh
flutter build macos --release
```

`bin` 디렉터리를 `PATH`에 추가합니다.

```sh
export PATH="/path/to/yogit/bin:$PATH"
```

이제 Git 저장소 안에서 실행할 수 있습니다.

```sh
yo
```

릴리스 앱이 없으면 `yo`가 처음 한 번 빌드한 뒤 현재 저장소의 절대 경로를 앱에 전달합니다.

## 사용법

```sh
yo [옵션] [경로]
```

경로를 생략하면 현재 디렉터리를 씁니다. 어느 쪽이든 `git rev-parse --show-toplevel`로 저장소 루트를 찾아 넘기므로 하위 디렉터리에서 실행해도 됩니다. Git 저장소가 아니면 오류를 내고 종료합니다.

| 옵션 | 설명 |
| --- | --- |
| `--repo PATH` | 열 저장소 경로. 위치 인자와 같고 마지막에 준 값을 씁니다. |
| `--debug` | Release 대신 Debug 빌드를 실행합니다. |
| `--build` | 실행 전에 다시 빌드합니다. |
| `--version` | `pubspec.yaml`의 버전을 출력합니다. |
| `--help` | 사용법을 출력합니다. |

```sh
yo ~/repos/other-project
yo --repo ~/repos/other-project --debug
yo --build
```

## GitHub와 GHE 아바타

앱은 현재 저장소의 `origin`만 확인하며 `gh auth login`으로 로그인한 계정을 그대로 사용합니다. 별도 토큰 입력 화면은 없습니다. GitHub와 GHE 커밋 API에서 받은 작성자·커미터 아바타만 표시하고 Gravatar는 조회하지 않습니다. 연결할 수 없으면 이니셜을 즉시 표시합니다.

## 탐색과 성능

- `↑`와 `↓`로 커밋을 선택하고 `Enter`로 미리보기를 엽니다.
- 미리보기 위치는 왼쪽, 오른쪽, 아래쪽 중에서 정할 수 있습니다.
- 커밋은 500개씩 읽고 마지막 12개 행에 가까워지면 다음 페이지를 불러옵니다.
- diff는 Unified와 Side-by-side를 지원합니다.
