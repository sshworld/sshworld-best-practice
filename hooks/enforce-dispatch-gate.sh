#!/usr/bin/env bash
# PreToolUse Bash — ExitPlanMode 승인 전 dispatch-slice-pane.sh 실행 차단.
#
# 목적: /plan-dev Phase 2 dispatch 는 ExitPlanMode(사용자 승인) 후에만 허용.
#   dispatch-slice-pane.sh 는 Bash 도구라 enforce-plan-mode(Write/Edit 전용)를 안 타므로,
#   이 hook 이 Bash 레이어에서 별도 차단.
#
# 판정 순서 (enforce-plan-mode.sh 미러):
#   - DISABLE_DISPATCH_GATE_HOOK=1 → exit 0 (영구 비활성)
#   - SKIP_DISPATCH_GATE=1 → exit 0 (1회 우회)
#   - tool_name != Bash → exit 0
#   - tool_input.command 에 dispatch-slice-pane.sh 없음 → exit 0 (관심 명령 아님)
#   - 세션 marker 없음 → exit 0 (비-plan-dev)
#   - 자식 worktree(git-dir != git-common-dir) → exit 0
#   - permission_mode == bypassPermissions → exit 0 (dispatch 자식/명시 우회)
#   - approved marker 존재 AND session_id 일치 → exit 0 (승인됨)
#   - marker 부재 또는 session_id 불일치 → exit 2 차단
#   - 파싱 실패 등 → conservative exit 0 (false-block 회피)
#
# 우회:
#   SKIP_DISPATCH_GATE=1          — 1회 우회
#   DISABLE_DISPATCH_GATE_HOOK=1  — 영구 비활성
#
# 환경변수(테스트 mock):
#   DISPATCH_GATE_SESSION_FILE — 세션 marker 경로 override
#   PLAN_APPROVED_MARKER       — approved marker 경로 override
set -uo pipefail

[ "${DISABLE_DISPATCH_GATE_HOOK:-0}" = "1" ] && exit 0
[ "${SKIP_DISPATCH_GATE:-0}" = "1" ] && exit 0

PAYLOAD=$(cat)

# tool_name 검사
TOOL=$(printf '%s' "$PAYLOAD" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    print(d.get('tool_name', ''))
except Exception:
    print('')
" 2>/dev/null || echo "")

[ "$TOOL" = "Bash" ] || exit 0

# command 에 dispatch-slice-pane.sh 포함 여부 확인
CMD=$(printf '%s' "$PAYLOAD" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    print(d.get('tool_input', {}).get('command', ''))
except Exception:
    print('')
" 2>/dev/null || echo "")

# dispatch-slice-pane.sh 없으면 관심 명령 아님 → exit 0
printf '%s' "$CMD" | grep -q "dispatch-slice-pane.sh" || exit 0

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

# 세션 marker 없음 → 비-plan-dev → exit 0
[ -f "$SESSION_FILE" ] || exit 0

# 자식 worktree 감지 (git-dir != git-common-dir) → exit 0
GIT_DIR=$(git rev-parse --git-dir 2>/dev/null || echo "")
if [ -n "$GIT_DIR" ] && [ -n "$GIT_COMMON" ] && [ "$GIT_DIR" != "$GIT_COMMON" ]; then
  exit 0
fi

# permission_mode, session_id 추출 (파싱 실패 시 conservative exit 0)
PARSED=$(printf '%s' "$PAYLOAD" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    pmode = d.get('permission_mode', '')
    sid   = d.get('session_id', '')
    print(pmode + '|' + sid)
except Exception:
    print('error|')
" 2>/dev/null || echo "error|")

PMODE="${PARSED%%|*}"
SESSION_ID="${PARSED##*|}"

# 파싱 실패 → conservative exit 0
[ "$PMODE" = "error" ] && exit 0
[ -z "$SESSION_ID" ] && exit 0

# bypassPermissions → dispatch 자식/명시 우회 → exit 0
[ "$PMODE" = "bypassPermissions" ] && exit 0

# approved marker 경로 결정
APPROVED_MARKER="${PLAN_APPROVED_MARKER:-}"
if [ -z "$APPROVED_MARKER" ]; then
  if [ -n "$GIT_COMMON" ]; then
    APPROVED_MARKER="${GIT_COMMON}/plan-dev-plan-approved"
  else
    APPROVED_MARKER="${PROJECT_DIR}/.git/plan-dev-plan-approved"
  fi
fi

# approved marker 검사
if [ -f "$APPROVED_MARKER" ]; then
  MARKER_SESSION=$(cat "$APPROVED_MARKER" 2>/dev/null || echo "")
  if [ "$MARKER_SESSION" = "$SESSION_ID" ]; then
    # 승인됨 → exit 0
    exit 0
  fi
fi

# 미승인 또는 session_id 불일치(stale) → 차단
cat >&2 <<'EOF'
🛑 [enforce-dispatch-gate] plan-dev 세션인데 ExitPlanMode 승인 전 dispatch 시도.
   먼저 EnterPlanMode → plan 작성 → ExitPlanMode 로 사용자 승인 후 dispatch 할 것.
   우회: SKIP_DISPATCH_GATE=1 (1회) / DISABLE_DISPATCH_GATE_HOOK=1 (영구).
EOF
exit 2
