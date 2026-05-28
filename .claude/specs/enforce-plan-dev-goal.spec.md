# Spec — Stop hook: enforce-plan-dev-goal.sh (S2)

## Context (자식 implementor 용)

plan-dev workflow 를 native `/goal` 처럼 자체 loop 가능하게 만드는 작업의 2번 슬라이스.
S1 (`.claude/specs/plan-dev-goal-integration.spec.md`) 의 룰 contract 에 따라 Stop hook 구현.

mechanism:
- Stop hook = Claude Code 모델 응답 종료 (stop_reason="end_turn") 시 매번 호출
- plan-dev marker 활성 시만 작동
- plan 파일의 `<!-- machine-checks -->` ~ `<!-- /machine-checks -->` 사이 fenced bash block 추출
- 각 라인 `bash -c` 실행 → 전부 PASS → exit 0 (Stop 허용) / 하나라도 fail → exit 2 + stderr

## 산출 파일

- `.claude/hooks/enforce-plan-dev-goal.sh` (실행 가능)
- `.claude/hooks/enforce-plan-dev-goal.spec.md` (자체 단위 시나리오 test)
- `.claude/specs/enforce-plan-dev-goal.spec.md` (본 spec — 이미 작성, 자식 건드릴 필요 없음)

## 구현 명세

### 입력
- stdin: Claude Code Stop hook payload (JSON) — 본 hook 는 무시 (필요 시 jq 로 파싱 가능)
- env:
  - `CLAUDE_PROJECT_DIR` (Claude Code 제공) — 프로젝트 root
  - `SKIP_PLAN_DEV_GOAL` — set 이면 advisory skip (exit 0)
  - `DISABLE_PLAN_DEV_GOAL_HOOK` — set 이면 영구 비활성 (exit 0)
  - `PLAN_DEV_GOAL_PLAN_PATH` — plan 파일 경로 override (테스트 mock)
  - `PLAN_DEV_GOAL_SESSION_FILE` — marker 파일 경로 override (테스트 mock, 기본 `$CLAUDE_PROJECT_DIR/.git/plan-dev-session.json`)
  - `PLAN_DEV_GOAL_VERBOSE` — set 이면 PASS 도 stderr 에 요약 출력

### 동작 알고리즘
```
1. SKIP/DISABLE env set → echo "skipped|disabled" >&2; exit 0
2. PROJECT_DIR=${CLAUDE_PROJECT_DIR:-$(pwd)}
3. SESSION_FILE=${PLAN_DEV_GOAL_SESSION_FILE:-$PROJECT_DIR/.git/plan-dev-session.json}
4. [ ! -f $SESSION_FILE ] → exit 0 (marker 없음 = plan-dev 세션 아님)
5. PLAN_PATH 결정:
   a. $PLAN_DEV_GOAL_PLAN_PATH 있으면 그것
   b. 없으면 $SESSION_FILE 의 .plan_path (jq) 시도
   c. 없으면 ~/.claude/plans/*.md 의 mtime 최신 1건 (fallback)
   d. PLAN_PATH 파일 없음 → exit 0 (plan 없으면 평가 불가)
6. plan 파일에서 sed 로 `<!-- machine-checks -->` 와 `<!-- /machine-checks -->` 사이 내용 추출
7. 추출 내용에서 ```bash 와 ``` 사이 fenced 코드 추출 (sed 또는 awk)
8. 비어 있으면 exit 0 (Goal Statement 섹션 없거나 machine-checks 비어 있음)
9. 각 라인 순회 (빈 줄, # comment skip):
   - bash -c "<line>" 실행 (cwd = PROJECT_DIR)
   - exit != 0 → 실패. 실패 라인, exit code, stdout/stderr 마지막 5줄 stderr 출력
   - 첫 실패 즉시 break OR 전체 실행 후 종합? → **전체 실행** (모델이 모든 미충족 항목 한 번에 알도록)
10. 실패가 하나라도 있으면:
    - stderr 에 "❌ N/M failed" + 각 실패 줄 + 마지막 hint "보완 후 다시 시도하세요" 출력
    - exit 2
11. 전부 PASS:
    - VERBOSE 면 stderr 에 "✅ M/M passed" 출력
    - exit 0
```

### 출력 형식

**stderr (fail 시)**:
```
[enforce-plan-dev-goal] plan: <path>
[enforce-plan-dev-goal] ❌ 2/8 failed (machine-checks)

--- FAIL: grep -c "Goal Statement" .claude/commands/plan-dev.md | awk '$1>=3{exit 0}{exit 1}' ---
exit: 1
stdout: 0
(no stderr)

--- FAIL: test -x .claude/hooks/enforce-plan-dev-goal.sh ---
exit: 1

[enforce-plan-dev-goal] 위 실패 항목 보완 후 다시 시도하세요. 우회: SKIP_PLAN_DEV_GOAL=1
```

**stderr (skip/disable)**:
```
[enforce-plan-dev-goal] skipped (SKIP_PLAN_DEV_GOAL=1)
```

**stdout**: 항상 비움 (Claude Code 가 stdout 을 모델 입력으로 인젝트할 수 있어서 stderr 만 사용)

### 우회 방법 명시 (stderr 메시지 반드시 포함)

본 repo `enforce-cmux-context.sh`, `track-cmux-edit-burst.sh` 패턴 따름 — 실패/차단 메시지에 우회 env 명시:
```
우회:
  SKIP_PLAN_DEV_GOAL=1         — 1회 우회
  DISABLE_PLAN_DEV_GOAL_HOOK=1 — 영구 비활성
```

### 단위 시나리오 (`enforce-plan-dev-goal.spec.md` 으로 보존)

자식이 6 시나리오를 bash test script 로 작성해서 실행 + 결과 spec 에 기록:

```bash
#!/usr/bin/env bash
# tests/hooks/enforce-plan-dev-goal.test.sh
set -e

HOOK="$(pwd)/.claude/hooks/enforce-plan-dev-goal.sh"
TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

# Scenario 1: marker 없음 → exit 0
PLAN_DEV_GOAL_SESSION_FILE="$TMP/no-such.json" $HOOK < /dev/null
echo "1: marker 없음 → exit 0 ✓"

# Scenario 2: marker 있고 plan 없음 → exit 0
echo '{}' > $TMP/session.json
PLAN_DEV_GOAL_SESSION_FILE=$TMP/session.json PLAN_DEV_GOAL_PLAN_PATH=$TMP/no-such.md $HOOK < /dev/null
echo "2: plan 없음 → exit 0 ✓"

# Scenario 3: machine-checks 전부 PASS → exit 0
cat > $TMP/plan.md <<EOF
## Goal Statement
<!-- machine-checks -->
\`\`\`bash
true
[ 1 -eq 1 ]
\`\`\`
<!-- /machine-checks -->
EOF
PLAN_DEV_GOAL_SESSION_FILE=$TMP/session.json PLAN_DEV_GOAL_PLAN_PATH=$TMP/plan.md $HOOK < /dev/null
echo "3: 전부 PASS → exit 0 ✓"

# Scenario 4: 하나 fail → exit 2 + stderr 매치
cat > $TMP/plan.md <<EOF
## Goal Statement
<!-- machine-checks -->
\`\`\`bash
true
false
\`\`\`
<!-- /machine-checks -->
EOF
out=$(PLAN_DEV_GOAL_SESSION_FILE=$TMP/session.json PLAN_DEV_GOAL_PLAN_PATH=$TMP/plan.md $HOOK < /dev/null 2>&1 || echo "EXIT=$?")
echo "$out" | grep -q "EXIT=2"
echo "$out" | grep -q "FAIL"
echo "4: 한 줄 fail → exit 2 + stderr FAIL ✓"

# Scenario 5: SKIP env → exit 0
SKIP_PLAN_DEV_GOAL=1 $HOOK < /dev/null
echo "5: SKIP env → exit 0 ✓"

# Scenario 6: DISABLE env → exit 0
DISABLE_PLAN_DEV_GOAL_HOOK=1 $HOOK < /dev/null
echo "6: DISABLE env → exit 0 ✓"

echo "✅ all 6 scenarios passed"
```

자식은 위 test 작성 + 실행 + 결과 (`✅ all 6 scenarios passed`) 확인 후 ✅ 회수.

## TDD Red → Green

### Red
```bash
test -f .claude/hooks/enforce-plan-dev-goal.sh && echo "exists" || echo "not yet"  # not yet
```

### Green
```bash
test -x .claude/hooks/enforce-plan-dev-goal.sh           # exists + executable
bash tests/hooks/enforce-plan-dev-goal.test.sh           # 6 시나리오 PASS
SKIP_PLAN_DEV_GOAL=1 .claude/hooks/enforce-plan-dev-goal.sh < /dev/null  # exit 0
test -f .claude/hooks/enforce-plan-dev-goal.spec.md      # spec 파일 보존
```

## 자식이 끝나기 전 verification

```bash
set -e
test -x .claude/hooks/enforce-plan-dev-goal.sh
bash tests/hooks/enforce-plan-dev-goal.test.sh
SKIP_PLAN_DEV_GOAL=1 .claude/hooks/enforce-plan-dev-goal.sh < /dev/null > /dev/null
echo "✅ all green"
```

## 주의 사항

- 본 hook 는 stdout 으로 출력 금지 (Claude Code 가 inject 가능). 모든 메시지 stderr.
- machine-checks bash 라인이 비어있거나 # comment 만 → 무시 (PASS 카운트 제외, fail 도 아님)
- jq 부재 시 grep 으로 fallback (jq 가 없는 환경 가정 안 함, jq 있다고 가정 — 본 repo settings.json 이미 jq 사용)
- bash -c 호출 시 cwd 는 PROJECT_DIR. 명령이 상대 경로 쓸 수 있게.
- 시간 제약: 각 bash -c 라인은 정상적으로 빠르게 끝나야. timeout 5s 권장 (`timeout 5s bash -c "$line"`)
- 실패 출력의 stdout/stderr 발췌는 마지막 5줄까지 (긴 출력 자르기)

자식 응답 마지막에 `✅` 출력.
