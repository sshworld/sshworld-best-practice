# Slice S3 — tmux-orchestrate SKILL.md 의 cmux browser 섹션

너는 implementor 다. TDD R→G→R. 작업 끝에 `✅ cmux-browser-guide:` 또는 `❌ cmux-browser-guide:` 출력.

## 작업 디렉토리

`/Users/sshworld/develop/claude-best-practice/.worktrees/cmux-browser-guide`

시작 즉시 `pwd` 출력 → 이 경로와 일치 안 하면 즉시 `❌ cmux-browser-guide: cwd mismatch` 보고 후 중단.

## 산출 파일

- `.claude/skills/tmux-orchestrate/SKILL.md`

다른 파일 수정 금지.

## 변경 명세

`tmux-orchestrate` skill 은 cmux/tmux pane 라이프사이클을 다루는 곳이라, cmux 의 **browser** 도구 (cmux browser open/eval/navigate) 사용 시 알려진 함정 3 가지를 새 섹션으로 명시한다.

기존 `## 안티패턴` 섹션 또는 그 위에 새 섹션 `## cmux browser 사용 (함정 3가지)` 추가. 위치는 마지막 `## 환경변수` 표 바로 위.

내용:

### 1. localhost dev 서버 접근 불가

- 증상: `cmux browser open http://localhost:3000/...` → about:blank 로 끝남. dev 서버 로그에 요청 안 찍힘.
- 원인: cmux 내장 chromium 의 network 정책이 호스트 loopback(127.0.0.1) 에 도달 못함. LAN IP 도 동일 네트워크 정책상 불가 — **우회 시도 금지**.
- 대안: dev 서버 검증이 필요하면 cmux 밖 외부 브라우저 / 스크린샷 / 직접 실행 으로. cmux browser 는 외부 도메인(외부 prod·staging) 검증 용도로만.

### 2. Navigate 후 silent cross-origin 실패 (stale render)

- 증상: 다른 origin 으로 `navigate` 후 reload --snapshot-after 해도 이전 페이지 DOM 잔존. url get 응답만 새 URL.
- 원인: cross-origin navigation 이 silently 실패하면서 이전 DOM 유지 → 진단을 헷갈리게 함.
- 대처: navigate 직후 반드시 페이지 내 **고유 selector 존재 검증** (`cmux browser eval` 로 querySelector 또는 `cmux browser find-text`). URL get 만으로 도달 판정 금지.

### 3. eval 의 복잡 JS 결과 JSON 파싱 실패

- 증상: `cmux browser eval "Array.from(...).map(x => ...)"` 시 `Error Domain=NSCocoaErrorDomain ... Unable to parse empty data`.
- 원인: eval 반환값이 native object 면 직렬화 단계에서 실패.
- 대처: 항상 결과를 **string 으로 강제** — `String(JSON.stringify(...))` 로 감싸 호출. 예: `cmux browser eval "String(JSON.stringify(Array.from(document.querySelectorAll('input')).map(i => i.name)))"`.

## TDD 검증

### Red (반드시 실패해야 함)

```bash
grep -E 'localhost dev 서버 접근 불가|cross-origin|JSON\.stringify' .claude/skills/tmux-orchestrate/SKILL.md
```

매칭이 있으면 즉시 `❌ cmux-browser-guide: pre-state mismatch` 보고 후 중단.

### Green (반드시 통과해야 함)

변경 후:
```bash
grep -c 'localhost' .claude/skills/tmux-orchestrate/SKILL.md  # >= 1
grep -c 'cross-origin' .claude/skills/tmux-orchestrate/SKILL.md  # >= 1
grep -c 'JSON\.stringify' .claude/skills/tmux-orchestrate/SKILL.md  # >= 1
```

### 회귀 가드

- `awk '/^##/' .claude/skills/tmux-orchestrate/SKILL.md` 로 헤더 트리 정렬.
- `## 환경변수` 표가 깨지지 않은 채 끝에 남았는지.
- `git diff --stat HEAD` 로 1개 파일만 수정.

## 출력 형식

성공:
```
✅ cmux-browser-guide: <변경 줄 수> lines changed, 1 file
Branch: docs/cmux-browser-guide
```

실패:
```
❌ cmux-browser-guide: <원인 한 줄>
단계: [Red/Green/Refactor]
```
