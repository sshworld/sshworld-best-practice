#!/usr/bin/env bash
# Stop hook: enforce plan-dev goal machine-checks
# 우회: SKIP_PLAN_DEV_GOAL=1 (1회), DISABLE_PLAN_DEV_GOAL_HOOK=1 (영구)
set -euo pipefail

TAG="[enforce-plan-dev-goal]"

if [[ -n "${DISABLE_PLAN_DEV_GOAL_HOOK:-}" ]]; then
  echo "$TAG disabled (DISABLE_PLAN_DEV_GOAL_HOOK=1)" >&2
  exit 0
fi

if [[ -n "${SKIP_PLAN_DEV_GOAL:-}" ]]; then
  echo "$TAG skipped (SKIP_PLAN_DEV_GOAL=1)" >&2
  exit 0
fi

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
SESSION_FILE="${PLAN_DEV_GOAL_SESSION_FILE:-$PROJECT_DIR/.git/plan-dev-session.json}"

if [[ ! -f "$SESSION_FILE" ]]; then
  exit 0
fi

# Active dispatch worktree (자식 implementor 진행 중) → skip
# Goal Statement 평가는 자식 작업 완료 전엔 자연히 미충족이므로 hook 차단 false-positive
# `git worktree list --porcelain` 결과의 .worktrees/ 안 active worktree 만 감지 (stale dir 무시)
ACTIVE_WT=$(git -C "$PROJECT_DIR" worktree list --porcelain 2>/dev/null | grep -c "^worktree.*\.worktrees/" || true)
if [[ "${ACTIVE_WT:-0}" -gt 0 ]]; then
  exit 0
fi

# Determine plan path
if [[ -n "${PLAN_DEV_GOAL_PLAN_PATH:-}" ]]; then
  PLAN_PATH="$PLAN_DEV_GOAL_PLAN_PATH"
else
  # Try jq from session file
  PLAN_PATH=""
  if command -v jq &>/dev/null; then
    PLAN_PATH=$(jq -r '.plan_path // empty' "$SESSION_FILE" 2>/dev/null || true)
  fi
  # Fallback: marker(SESSION_FILE)보다 새로 수정된 plan 만 (stale plan 다음 세션 이월 차단).
  # start 는 plan 작성 前 → marker mtime < 이 세션 plan mtime. 직전 세션 stale plan 은 marker 보다 오래됨 → 제외.
  if [[ -z "$PLAN_PATH" ]]; then
    PLAN_PATH=$(find ~/.claude/plans -maxdepth 1 -name '*.md' -newer "$SESSION_FILE" 2>/dev/null \
                | xargs -r ls -t 2>/dev/null | head -1)
    # 해결한 경로를 marker 에 best-effort persist (다음 turn 안정 + 빠름)
    if [[ -n "$PLAN_PATH" ]] && command -v python3 &>/dev/null; then
      PLAN_PATH="$PLAN_PATH" SESSION_FILE="$SESSION_FILE" python3 -c "
import json, os
f = os.environ['SESSION_FILE']
try:
    d = json.load(open(f))
    d['plan_path'] = os.environ['PLAN_PATH']
    json.dump(d, open(f, 'w'), indent=2); open(f, 'a').write('\n')
except Exception:
    pass
" 2>/dev/null || true
    fi
  fi
fi

if [[ -z "$PLAN_PATH" ]] || [[ ! -f "$PLAN_PATH" ]]; then
  exit 0
fi

# Extract content between <!-- machine-checks --> and <!-- /machine-checks -->
MC_BLOCK=$(sed -n '/<!-- machine-checks -->/,/<!-- \/machine-checks -->/p' "$PLAN_PATH" | \
           sed '1d;$d')

if [[ -z "$MC_BLOCK" ]]; then
  exit 0
fi

# Extract lines inside ```bash ... ``` fenced block
CHECKS=$(echo "$MC_BLOCK" | awk '/^```bash/{p=1;next} /^```/{p=0} p{print}')

if [[ -z "$CHECKS" ]]; then
  exit 0
fi

echo "$TAG plan: $PLAN_PATH" >&2

PASS=0
FAIL=0
FAIL_DETAILS=""

while IFS= read -r line; do
  # Skip blank lines and comments
  [[ -z "$line" ]] && continue
  [[ "$line" =~ ^[[:space:]]*# ]] && continue

  # Run check in PROJECT_DIR with timeout
  TMPOUT=$(mktemp)
  TMPERR=$(mktemp)
  EXIT_CODE=0
  if command -v timeout &>/dev/null; then
    (cd "$PROJECT_DIR" && timeout 5s bash -c "$line" >"$TMPOUT" 2>"$TMPERR") || EXIT_CODE=$?
  else
    (cd "$PROJECT_DIR" && bash -c "$line" >"$TMPOUT" 2>"$TMPERR") || EXIT_CODE=$?
  fi

  if [[ $EXIT_CODE -eq 0 ]]; then
    PASS=$((PASS + 1))
    if [[ -n "${PLAN_DEV_GOAL_VERBOSE:-}" ]]; then
      echo "$TAG ✅ PASS: $line" >&2
    fi
  else
    FAIL=$((FAIL + 1))
    STDOUT_TAIL=$(tail -5 "$TMPOUT")
    STDERR_TAIL=$(tail -5 "$TMPERR")
    DETAIL="--- FAIL: $line ---
exit: $EXIT_CODE"
    if [[ -n "$STDOUT_TAIL" ]]; then
      DETAIL="$DETAIL
stdout: $STDOUT_TAIL"
    fi
    if [[ -n "$STDERR_TAIL" ]]; then
      DETAIL="$DETAIL
stderr: $STDERR_TAIL"
    fi
    FAIL_DETAILS="$FAIL_DETAILS
$DETAIL
"
  fi

  rm -f "$TMPOUT" "$TMPERR"
done <<< "$CHECKS"

TOTAL=$((PASS + FAIL))

if [[ $FAIL -gt 0 ]]; then
  echo "$TAG ❌ $FAIL/$TOTAL failed (machine-checks)" >&2
  echo "$FAIL_DETAILS" >&2
  echo "$TAG 위 실패 항목 보완 후 다시 시도하세요." >&2
  echo "우회:" >&2
  echo "  SKIP_PLAN_DEV_GOAL=1         — 1회 우회" >&2
  echo "  DISABLE_PLAN_DEV_GOAL_HOOK=1 — 영구 비활성" >&2
  exit 2
fi

if [[ -n "${PLAN_DEV_GOAL_VERBOSE:-}" ]]; then
  echo "$TAG ✅ $PASS/$TOTAL passed" >&2
fi

# ── Agent layer (S1) ──────────────────────────────────────────────
run_agent_layer() {
  local plan_path="$1" session_file="$2" project_dir="$3"

  if [[ -n "${DISABLE_GOAL_AGENT:-}" ]]; then
    echo "$TAG agent layer disabled (DISABLE_GOAL_AGENT=1)" >&2
    return 0
  fi
  if [[ -n "${SKIP_GOAL_AGENT:-}" ]]; then
    echo "$TAG agent layer skipped (SKIP_GOAL_AGENT=1)" >&2
    return 0
  fi
  if ! command -v claude &>/dev/null; then
    echo "$TAG claude binary unavailable — agent layer skipped" >&2
    return 0
  fi

  local sem_goal start_ref diff_stat log prompt agent_out agent_pass

  # 인라인 `**Semantic goal**: <텍스트>` 형식 캡처 (템플릿 계약). `next` 없이 매치 줄 포함, prefix strip.
  sem_goal=$(awk '/\*\*[Ss]emantic goal\*\*/{flag=1} flag && /^## /{flag=0} flag' "$plan_path" \
    | sed 's/^\*\*[Ss]emantic goal\*\*:[[:space:]]*//' | head -10)

  if [[ -z "${sem_goal//[[:space:]]/}" ]]; then
    echo "$TAG semantic goal 추출 실패 — agent layer skipped" >&2
    return 0
  fi

  start_ref=""
  if command -v jq &>/dev/null; then
    start_ref=$(jq -r '.start_ref // empty' "$session_file" 2>/dev/null || true)
  fi
  if [[ -z "$start_ref" ]] && command -v python3 &>/dev/null; then
    start_ref=$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d.get('start_ref',''))" "$session_file" 2>/dev/null || true)
  fi
  if [[ -z "$start_ref" ]]; then
    echo "$TAG start_ref 없음 — agent layer skipped" >&2
    return 0
  fi

  diff_stat=$(cd "$project_dir" && git diff "$start_ref..HEAD" --stat 2>/dev/null | tail -20 || true)
  log=$(cd "$project_dir" && git log "$start_ref..HEAD" --oneline 2>/dev/null | head -20 || true)

  prompt=$(cat <<PROMPTEOF
You are goal-checker. Evaluate if Semantic goal is met by changes.

Semantic goal:
$sem_goal

Commits:
$log

Diff stat:
$diff_stat

Output JSON only: {"pass": true|false, "missing": ["..."]}. No other text.
PROMPTEOF
)

  if command -v timeout &>/dev/null; then
    agent_out=$(timeout 30s claude -p --output-format text "$prompt" 2>/dev/null || true)
  else
    agent_out=$(claude -p --output-format text "$prompt" 2>/dev/null || true)
  fi

  local missing_file="/tmp/goal_agent_missing.$$"
  agent_pass=$(printf '%s' "$agent_out" | python3 -c "
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
" 2>"$missing_file" || echo "parse-fail")

  if [[ "$agent_pass" = "false" ]]; then
    echo "$TAG ❌ agent layer: Semantic goal 미충족" >&2
    cat "$missing_file" >&2 2>/dev/null || true
    rm -f "$missing_file"
    echo "$TAG 우회: SKIP_GOAL_AGENT=1 (1회) / DISABLE_GOAL_AGENT=1 (영구)" >&2
    return 2
  elif [[ "$agent_pass" = "true" ]]; then
    if [[ -n "${PLAN_DEV_GOAL_VERBOSE:-}" ]]; then
      echo "$TAG ✅ agent layer PASS" >&2
    fi
  else
    echo "$TAG agent layer parse-fail — bash-only PASS" >&2
  fi
  rm -f "$missing_file"
  return 0
}
run_agent_layer "$PLAN_PATH" "$SESSION_FILE" "$PROJECT_DIR" || exit $?

exit 0
