---
name: parallel-consult
description: 자식 Claude pane 띄워 한 번 질문하고 답만 회수. tmux 또는 cmux 환경 지원.
args: <자식에게 보낼 질문>
---

# parallel-consult

부모 Claude 세션에서 **자식 Claude pane** 을 띄워 한 번 질문하고 응답만 회수하는 흐름.

## Prerequisite

> ⚠️ **먼저 `bash ${CLAUDE_PLUGIN_ROOT}/scripts/detect-pane-env.sh` 호출** — 결과로 tmux/cmux/default 분기. cmux 안인데 tmux 명령 reach 금지.

1. **터미널 환경 감지**: `env=$(${CLAUDE_PLUGIN_ROOT}/scripts/detect-pane-env.sh)`. 결과별 분기:
   - `tmux` → 기존 tmux 흐름 (아래 단계 2 tmux 분기)
   - `cmux` → cmux-pane.sh 흐름 (아래 단계 2 cmux 분기)
   - `default` → 사용자에게 tmux 또는 cmux 설치 안내 후 중단.
2. wrapper 결정 (tmux 분기): `command -v tmux-cli` 우선, 없으면 `${CLAUDE_PLUGIN_ROOT}/scripts/tmux-pane.sh` 폴백. 둘 다 없으면 `uv tool install claude-code-tools` 안내 후 중단.
3. **기존 자식 pane 정리** (tmux 분기): 새 작업 시작 전 `${CLAUDE_PLUGIN_ROOT}/scripts/tmux-pane.sh cleanup` 호출. `tmux-pane-mgr` 세션 + 현재 window 의 main/self 외 split pane 일괄 kill. 우회: `DISPATCH_SKIP_CLEANUP=1` 또는 호출 생략.

## 흐름 단계

다음 시퀀스를 그대로 실행 (안 거치고 단축 금지):

1. **환경 감지** — `env=$(${CLAUDE_PLUGIN_ROOT}/scripts/detect-pane-env.sh)`. `default` 면 중단.
2. **wrapper 결정**:
   - tmux: `W=$(command -v tmux-cli || echo "${CLAUDE_PLUGIN_ROOT}/scripts/tmux-pane.sh")`
   - cmux: `W="${CLAUDE_PLUGIN_ROOT}/scripts/cmux-pane.sh"`
3. **`launch zsh`** — pane id 저장. `pane=$($W launch zsh)`.
4. **`send "claude --model <alias>"` + `wait-idle`** — 자식 Claude 프롬프트가 뜰 때까지 대기. **model alias 규약**: 사용자 인자가 `sonnet:`/`opus:`/`haiku:` 으로 시작하면 그 토큰을 model 로 분리, 나머지를 prompt 로. 명시 안 하면 `sonnet` 디폴트.
   ```bash
   # 예: /parallel-consult "haiku: 이거 분석해줘"  →  model=haiku, prompt="이거 분석해줘"
   # 예: /parallel-consult "그냥 질문"            →  model=sonnet (default), prompt="그냥 질문"
   $W send "claude --model $MODEL" --pane=$pane
   # tmux: wait-idle 사용
   # cmux: wait-idle 은 Slice 2 구현 예정 — 이 시점엔 sleep 3 폴백
   # TODO(Slice 2): cmux wait-idle 구현 후 아래 sleep 제거
   if [ "$env" = "cmux" ]; then sleep 3; else $W wait-idle --pane=$pane --idle=2 --timeout=30; fi
   ```
5. **`send "$ARG"` + `wait-idle`** — 질문 전송 후 응답 마무리까지 대기.
   ```bash
   $W send "$ARG" --pane=$pane
   # TODO(Slice 2): cmux wait-idle 구현 후 아래 sleep 제거
   if [ "$env" = "cmux" ]; then sleep 3; else $W wait-idle --pane=$pane --idle=5 --timeout=180; fi
   ```
6. **`capture`** — pane 내용 회수.
   ```bash
   reply=$($W capture --pane=$pane)
   ```
7. **응답 추출** — 입력 echo / 프롬프트 라인 / 부수 출력을 필터링하고, **첫 응답 블록 또는 마지막 50줄** 만 부모 세션에 인용+요약으로 출력.
8. **사용자에게 묻기** — 자식 pane 을 유지할지 / `kill` 할지. 디폴트는 유지 (추가 질문 가능).

## 안전 수칙

- **shell 먼저 launch** — `$W launch claude` 직접 호출 시 자식 종료 = pane 종료라 출력 유실. 항상 `launch zsh` 후 `send "claude"`.
- **send 후 wait-idle (tmux) / sleep (cmux)** — 응답 완료 전 `capture` 하면 빈 응답 회수.
- **출력 폴링 금지** — `while; capture; sleep` 반복 금지. `wait-idle` 이 같은 일을 효율적으로 한다.

## 안티패턴

❌ 사전 prompt 없이 자식 시작 — 자식 Claude 는 첫 메시지가 와야 응답 시작
❌ 출력 폴링 (반복 capture 루프) — `wait-idle` 로 대체
❌ 자기 pane kill — wrapper 가 거부하지만 의식적으로 회피
❌ 환경 감지 없이 tmux 전용 명령 사용 — cmux 환경에서 실패

## 예시

```text
/parallel-consult "이 함수의 시간복잡도는?"
/parallel-consult "이 PR diff 를 staff engineer 관점에서 한 줄로 비평해줘: <diff 인라인>"
```

응답 회수 후 부모 세션에서 인용 → 사용자에게 표시 → "자식 pane 유지할까요?" 묻기.
