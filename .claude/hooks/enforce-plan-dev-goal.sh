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
  # Fallback: mtime newest .md in ~/.claude/plans/
  if [[ -z "$PLAN_PATH" ]]; then
    if ls ~/.claude/plans/*.md &>/dev/null 2>&1; then
      PLAN_PATH=$(ls -t ~/.claude/plans/*.md 2>/dev/null | head -1)
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

exit 0
