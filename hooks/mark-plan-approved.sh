#!/usr/bin/env bash
# PostToolUse ExitPlanMode — ExitPlanMode 승인 시 plan-approved marker 기록.
#
# 목적: ExitPlanMode 가 사용자에게 승인되면 PostToolUse 가 발화 → 이 hook 이
#   approved marker(<git-common-dir>/plan-dev-plan-approved)에 session_id 를 기록.
#   enforce-dispatch-gate.sh 가 dispatch 전에 이 marker 를 확인해 승인 여부 판단.
#
# PostToolUse 특성: 도구 **성공** 시에만 발화 → ExitPlanMode reject/interrupt 면 미발화.
#   = 신뢰 가능한 "plan 승인" 신호. 차단용이 아님(PostToolUse 는 informational).
#
# 동작:
#   - tool_name != ExitPlanMode → exit 0 (관심 도구 아님)
#   - plan-dev 세션 marker 없음 → exit 0 (비-plan-dev 세션, no-op)
#   - session_id 추출 → PLAN_APPROVED_MARKER 에 기록
#   - python3/jq 파싱 실패 시 conservative exit 0 (절대 비차단)
#
# 환경변수(테스트 mock):
#   PLAN_APPROVED_MARKER     — approved marker 경로 override
#   DISPATCH_GATE_SESSION_FILE — 세션 marker 경로 override (mark-plan-approved.sh 도 참조)
set -uo pipefail

PAYLOAD=$(cat)

# python3 로 tool_name 추출 (파싱 실패 시 conservative exit 0)
TOOL=$(printf '%s' "$PAYLOAD" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    print(d.get('tool_name', ''))
except Exception:
    print('')
" 2>/dev/null || echo "")

[ "$TOOL" = "ExitPlanMode" ] || exit 0

# 세션 marker 경로 결정
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
GIT_COMMON=""
if command -v git >/dev/null 2>&1; then
  GIT_COMMON=$(git rev-parse --git-common-dir 2>/dev/null || echo "")
fi

SESSION_FILE="${DISPATCH_GATE_SESSION_FILE:-}"
if [ -z "$SESSION_FILE" ]; then
  if [ -n "$GIT_COMMON" ]; then
    SESSION_FILE="${GIT_COMMON}/plan-dev-session.json"
  else
    SESSION_FILE="${PROJECT_DIR}/.git/plan-dev-session.json"
  fi
fi

# 세션 marker 없음 → 비-plan-dev → no-op
[ -f "$SESSION_FILE" ] || exit 0

# session_id 추출 (파싱 실패 시 conservative exit 0)
SESSION_ID=$(printf '%s' "$PAYLOAD" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    sid = d.get('session_id', '')
    print(sid)
except Exception:
    print('')
" 2>/dev/null || echo "")

[ -n "$SESSION_ID" ] || exit 0

# approved marker 경로 결정
APPROVED_MARKER="${PLAN_APPROVED_MARKER:-}"
if [ -z "$APPROVED_MARKER" ]; then
  if [ -n "$GIT_COMMON" ]; then
    APPROVED_MARKER="${GIT_COMMON}/plan-dev-plan-approved"
  else
    APPROVED_MARKER="${PROJECT_DIR}/.git/plan-dev-plan-approved"
  fi
fi

# session_id 기록 (echo -n 으로 개행 없이)
printf '%s' "$SESSION_ID" > "$APPROVED_MARKER" 2>/dev/null || exit 0

exit 0
