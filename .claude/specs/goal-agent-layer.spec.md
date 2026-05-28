# Spec — Goal agent layer (S1)

## 목적

`enforce-plan-dev-goal.sh` Stop hook 에 bash machine-checks 통과 후 추가 layer 로 **goal-checker agent** 호출. agent 가 plan 의 Semantic goal + git diff 보고 의미적 판단 → JSON 응답. bash + agent dual gate.

## 산출 파일

1. `.claude/agents/goal-checker.md` — 신규 Haiku agent
2. `.claude/hooks/enforce-plan-dev-goal.sh` — agent layer 추가
3. `tests/enforce_plan_dev_goal_agent.test.sh` — 신규 테스트

## 1. `.claude/agents/goal-checker.md`

frontmatter:
- `name: goal-checker`
- `description: plan-dev Stop hook 의 dual gate 중 semantic layer. plan Semantic goal + start_ref..HEAD diff 보고 JSON {pass, missing} 응답.`
- `tools: Bash, Read`
- `model: haiku`

본문:
- 책임: bash machine-checks 통과 후 호출됨. plan 파일 Semantic goal 섹션 + `git log start_ref..HEAD --oneline` + `git diff start_ref..HEAD --stat` 입력. JSON 출력 강제.
- 출력 형식: `{"pass": true|false, "missing": ["..."]}`. **다른 텍스트 일절 없음**. JSON 외 출력 시 hook 파싱 실패 → conservative bash-only fallback.
- 판단 기준: Semantic goal 명시 항목이 diff 에 실제 반영됐는지. 누락 항목은 `missing` array 에 자연어로.
- 안 하는 것: 파일 수정, 사용자 질문, 코드 리뷰.

## 2. `.claude/hooks/enforce-plan-dev-goal.sh` 수정

기존 bash loop (L75~127) 후, 모든 PASS 시 agent layer 진입:

추가 위치: L127 `exit 0` 직전 (`if [[ $FAIL -gt 0 ]]; then ... fi` 블록 후).

추가 로직:
```bash
# ── Agent layer (S1) ──────────────────────────────────────────────
if [[ -n "${DISABLE_GOAL_AGENT:-}" ]]; then
  echo "$TAG agent layer disabled (DISABLE_GOAL_AGENT=1)" >&2
elif [[ -n "${SKIP_GOAL_AGENT:-}" ]]; then
  echo "$TAG agent layer skipped (SKIP_GOAL_AGENT=1)" >&2
elif ! command -v claude &>/dev/null; then
  echo "$TAG claude binary unavailable — agent layer skipped" >&2
else
  # Semantic goal 추출 (## Semantic goal | **Semantic goal**: 어느 형태든)
  SEM_GOAL=$(awk '/[Ss]emantic goal/{flag=1; next} flag && /^##/{flag=0} flag' "$PLAN_PATH" | head -10)
  # start_ref 추출
  START_REF=""
  if command -v jq &>/dev/null; then
    START_REF=$(jq -r '.start_ref // empty' "$SESSION_FILE" 2>/dev/null || true)
  fi
  if [[ -z "$START_REF" ]]; then
    echo "$TAG start_ref 없음 — agent layer skipped" >&2
  else
    DIFF_STAT=$(cd "$PROJECT_DIR" && git diff "$START_REF..HEAD" --stat 2>/dev/null | tail -20)
    LOG=$(cd "$PROJECT_DIR" && git log "$START_REF..HEAD" --oneline 2>/dev/null | head -20)
    PROMPT=$(cat <<PROMPTEOF
You are goal-checker. Evaluate if Semantic goal is met by changes.

Semantic goal:
$SEM_GOAL

Commits:
$LOG

Diff stat:
$DIFF_STAT

Output JSON only: {"pass": true|false, "missing": ["..."]}. No other text.
PROMPTEOF
)
    AGENT_OUT=$(timeout 30s claude -p --output-format text "$PROMPT" 2>/dev/null || true)
    # JSON 파싱
    AGENT_PASS=$(printf '%s' "$AGENT_OUT" | python3 -c "
import json,sys,re
t = sys.stdin.read()
m = re.search(r'\{.*?\}', t, re.DOTALL)
if not m: sys.exit(2)
try:
    d = json.loads(m.group(0))
    print('true' if d.get('pass') else 'false')
    miss = d.get('missing', [])
    if miss and not d.get('pass'):
        print('---', file=sys.stderr)
        for x in miss: print('- ' + str(x), file=sys.stderr)
except Exception:
    sys.exit(3)
" 2>/tmp/goal_agent_missing.$$ || echo "parse-fail")
    if [[ "$AGENT_PASS" = "false" ]]; then
      echo "$TAG ❌ agent layer: Semantic goal 미충족" >&2
      cat /tmp/goal_agent_missing.$$ >&2 2>/dev/null || true
      rm -f /tmp/goal_agent_missing.$$
      echo "$TAG 우회: SKIP_GOAL_AGENT=1 (1회) / DISABLE_GOAL_AGENT=1 (영구)" >&2
      exit 2
    elif [[ "$AGENT_PASS" = "true" ]]; then
      if [[ -n "${PLAN_DEV_GOAL_VERBOSE:-}" ]]; then
        echo "$TAG ✅ agent layer PASS" >&2
      fi
    else
      # parse-fail 또는 timeout — bash 만으로 PASS (conservative)
      echo "$TAG agent layer parse-fail — bash-only PASS" >&2
    fi
    rm -f /tmp/goal_agent_missing.$$
  fi
fi
```

## 3. `tests/enforce_plan_dev_goal_agent.test.sh`

테스트 시나리오:
1. **bash PASS + agent mock PASS → exit 0**: claude 를 mock 으로 `{"pass": true}` 출력하게 stub.
2. **bash PASS + agent mock FAIL → exit 2 + stderr 에 missing 항목**: mock `{"pass": false, "missing": ["X"]}`.
3. **SKIP_GOAL_AGENT=1 → bash 만 평가 (exit 0)**.
4. **DISABLE_GOAL_AGENT=1 → bash 만 평가 (exit 0)**.
5. **claude binary 없음 → bash 만 평가 (graceful, exit 0)**.
6. **agent parse-fail (JSON 아닌 텍스트) → bash 만 PASS 으로 fallback (exit 0)**.

mock 방법: `PATH=/tmp/mock_bin:$PATH` 로 `claude` stub 우선. stub 내용 e.g.:
```bash
#!/bin/bash
echo '{"pass": true}'
```

테스트 fixture:
- mock SESSION_FILE 에 `start_ref` 적힌 JSON
- mock PLAN_PATH 에 machine-checks bash + Semantic goal 섹션
- mock `claude` binary

각 시나리오는 환경변수 setup → hook 실행 → exit code + stderr 검증.

## TDD

- Red: 테스트 작성 → hook 미수정 상태에서 시나리오 1~2 FAIL (agent layer 없음)
- Green: hook 수정 → 전 시나리오 PASS
- Refactor: 함수 분리 — `run_agent_layer()` 함수로.

## 우회 env (CLAUDE.md 표 갱신은 S4)

- `SKIP_GOAL_AGENT=1` — agent layer 1회 우회 (bash 만)
- `DISABLE_GOAL_AGENT=1` — agent layer 영구 비활성 (bash 만)

## 완료 조건

```bash
test -f .claude/agents/goal-checker.md
grep -q "^model: haiku" .claude/agents/goal-checker.md
grep -qE "claude (--print|-p)" .claude/hooks/enforce-plan-dev-goal.sh
grep -qE "SKIP_GOAL_AGENT|DISABLE_GOAL_AGENT" .claude/hooks/enforce-plan-dev-goal.sh
bash tests/enforce_plan_dev_goal_agent.test.sh
bash -n .claude/hooks/enforce-plan-dev-goal.sh
```

모두 PASS 시 `✅ S1 done` 출력.
