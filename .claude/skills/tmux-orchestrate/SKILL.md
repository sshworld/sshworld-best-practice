---
name: tmux-orchestrate
description: 다른 tmux **또는 cmux** pane/surface 의 CLI 에이전트(다른 Claude / 디버거 / 장시간 스크립트)와 통신. 부모-자식 Claude 협업 패턴. user 가 명시 요청하거나, /parallel-consult / /plan-dev --mode=pane 흐름에서 호출.
context: tmux
---

# tmux-orchestrate

부모 Claude 가 **다른 tmux pane 또는 cmux surface** 의 CLI 에이전트(또 다른 Claude / Codex / 디버거 / 장시간 스크립트) 라이프사이클을 관리하는 패턴.

## 핵심 패턴

부모는 자식 pane 에 대해 다음 5단계 흐름을 유지한다 (각 단계는 단일 책임):

1. **launch zsh** — shell 을 먼저 띄움 (자식 명령 실패해도 pane 유지). `claude` 를 바로 launch 하면 pane 닫혀 출력 유실.
2. **send "claude"** — pane 안 shell 에서 자식 CLI 실행.
3. **wait-idle** — 자식이 입력 받을 준비 (프롬프트 출력) 까지 대기.
4. **send prompt + wait-idle** — 질문/명세 전송 후 응답이 마무리될 때까지 대기.
5. **capture** — pane 내용을 부모로 회수. 필요 시 마지막 N줄 또는 응답 블록만 추출.
6. (선택) **kill** — 후속 질문 가능성 있으면 유지, 작업 끝나면 종료.

## 호출 시퀀스

```bash
# 1. shell 먼저
pane=$(./scripts/tmux-pane.sh launch zsh)

# 2. 자식 Claude 실행
./scripts/tmux-pane.sh send "claude" --pane=$pane
./scripts/tmux-pane.sh wait-idle --pane=$pane --idle=2 --timeout=30

# 3. 질문 전송 → 응답 대기
./scripts/tmux-pane.sh send "분석해줘: ..." --pane=$pane
./scripts/tmux-pane.sh wait-idle --pane=$pane --idle=5 --timeout=180

# 4. 회수
reply=$(./scripts/tmux-pane.sh capture --pane=$pane)
echo "$reply" | tail -50  # 마지막 응답 블록

# 5. 정리 (선택)
./scripts/tmux-pane.sh kill --pane=$pane
```

`tmux-cli` (uv 로 설치된 외부 도구) 가 있으면 동일 호출 표면을 그대로 사용 가능:

```bash
pane=$(tmux-cli launch zsh)
tmux-cli send "claude" --pane=$pane
tmux-cli wait_idle --pane=$pane     # 인자명만 정렬 (외부: --idle-time)
tmux-cli capture --pane=$pane
```

## 도구 선택 가이드

| 상황 | 선택 |
|---|---|
| `command -v tmux-cli` 성공 (uv 로 설치됨) | **외부 `tmux-cli` 우선** — `execute` 등 고급 기능 활용 가능 |
| 외부 tool 미설치, 본 repo 의 wrapper 만 존재 | `scripts/tmux-pane.sh` 폴백 — 의존성 없음 |
| 둘 다 없음 | tmux 도 없는 환경 — `brew install tmux` + `uv tool install claude-code-tools` 안내 |
| cmux 안 surface (`CMUX_SOCKET_PASSWORD` set) | `scripts/cmux-pane.sh` 사용 — launch/send/capture/wait-idle 동일 5단계 |

두 도구는 명령 표면이 정렬되어 있어 스크립트는 wrapper 변수로 추상화 가능:
```bash
W=$(command -v tmux-cli || echo "./scripts/tmux-pane.sh")
pane=$("$W" launch zsh)
```

cmux 도 동일 5단계 — wrapper 만 `scripts/cmux-pane.sh` 로 바꿈:
```bash
W="./scripts/cmux-pane.sh"
pane=$("$W" launch zsh)
"$W" send "claude" --pane=$pane
"$W" wait-idle --pane=$pane --idle=2 --timeout=30
"$W" send "분석해줘: ..." --pane=$pane
"$W" wait-idle --pane=$pane --idle=5 --timeout=180
reply=$("$W" capture --pane=$pane)
```

## 안티패턴

❌ **shell 거치지 않고 `claude` 직접 launch** — 자식 명령이 실패하거나 종료되면 pane 도 같이 닫혀 출력 유실. 항상 `launch zsh` 먼저.

❌ **`send` 후 즉시 `capture`** — 입력이 자식에게 반영되기 전에 캡처 → 빈 응답. 반드시 사이에 `wait-idle` 1회.

❌ **자기 pane kill** — wrapper 가 자체 거부 (exit 5)하지만 의식적으로 회피. 우회는 `FORCE_SELF_KILL=1` 또는 `tmux kill-pane -t <id>` 직접 호출.

❌ **출력 폴링 (반복 capture 루프)** — `while true; do capture; sleep 1; done` 식 금지. `wait-idle` 한 번으로 대체.

❌ **자식 pane 토큰/비용을 부모 token-stats hook 으로 추적 시도** — token-stats 는 부모 세션 한정. 자식의 비용은 별도 추적 불가.

❌ **`tmux-cli` 의 인자명을 wrapper 에도 그대로** — 외부는 `--idle-time`, 본 wrapper 는 `--idle`. 도구별 인자명 확인 후 호출.

## cmux browser 사용 (함정 3가지)

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

## 환경변수

| 변수 | 기본 | 효과 |
|---|---|---|
| `FORCE_SELF_KILL` | unset | wrapper 의 자기 pane kill 거부 우회 |
| `CLAUDE_MAX_CHILD_PANES` | 5 (Slice D 이후) | 부모 세션의 자식 pane 상한 — 초과 시 PreToolUse hook 이 차단 |
| `DISABLE_PANE_LIMIT_HOOK` | unset | pane 상한 hook 비활성화 |
| `CLAUDE_FAKE_SELF_PANE` | unset | 테스트용 — wrapper 가 보는 "현재 pane id" 를 강제 주입 |
