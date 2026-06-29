#!/usr/bin/env bash
# PreToolUse Bash — plan mode 미진입 상태에서 dispatch-slice-pane.sh 실행 차단.
#
# 목적: /plan-dev Phase 2 dispatch 는 plan mode(EnterPlanMode→plan 작성→ExitPlanMode) 진입 후에만 허용.
#   dispatch-slice-pane.sh 는 Bash 도구라 enforce-plan-mode(Write/Edit 전용)를 안 타므로,
#   이 hook 이 Bash 레이어에서 별도 차단.
#
# 판정 순서:
#   - DISABLE_DISPATCH_GATE_HOOK=1 → exit 0 (영구 비활성)
#   - SKIP_DISPATCH_GATE=1 → exit 0 (1회 우회)
#   - tool_name != Bash → exit 0
#   - command 에 dispatch-slice-pane.sh AND --slice 둘 다 없으면 → exit 0 (관심 명령 아님)
#     (grep/git/test 등 우발 문자열 포함 명령 오탐 방지 — 실제 dispatch 는 항상 --slice 포함)
#   - 세션 marker 없음 → exit 0 (비-plan-dev 세션)
#   - 자식 worktree(git-dir != git-common-dir) → exit 0
#   - permission_mode == plan → exit 0 (plan mode 중)
#   - permission_mode == bypassPermissions → exit 0 (dispatch 자식/명시 우회)
#   - 파싱 실패 등 → conservative exit 0 (false-block 회피)
#   - marker start_ts 이후 mtime 인 plan 파일 존재 → exit 0 (plan mode 거침)
#   - start_ts 파싱 불가 → conservative exit 0
#   - 그 외(마커 활성 + plan mode 미진입) → exit 2 차단
#
# 우회:
#   SKIP_DISPATCH_GATE=1          — 1회 우회
#   DISABLE_DISPATCH_GATE_HOOK=1  — 영구 비활성
#
# 환경변수(테스트 mock):
#   DISPATCH_GATE_SESSION_FILE — 세션 marker 경로 override
#   PLAN_MODE_PLANS_DIR        — plan 파일 디렉토리 override (디폴트 $HOME/.claude/plans)
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

# command 추출
CMD=$(printf '%s' "$PAYLOAD" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    print(d.get('tool_input', {}).get('command', ''))
except Exception:
    print('')
" 2>/dev/null || echo "")

# dispatch-slice-pane.sh AND --slice 둘 다 있어야 관심 명령
# (grep/git/test 등이 dispatch-slice-pane.sh 문자열만 포함하는 오탐 방지)
printf '%s' "$CMD" | grep -q "dispatch-slice-pane.sh" || exit 0
printf '%s' "$CMD" | grep -q -- "--slice" || exit 0

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

# permission_mode 추출 (파싱 실패 시 conservative exit 0)
PMODE=$(printf '%s' "$PAYLOAD" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    print(d.get('permission_mode', ''))
except Exception:
    print('error')
" 2>/dev/null || echo "error")

# 파싱 실패 → conservative exit 0
[ "$PMODE" = "error" ] && exit 0

# plan mode 중 / dispatch 자식·명시 우회 모드 → allow
[ "$PMODE" = "plan" ] && exit 0
[ "$PMODE" = "bypassPermissions" ] && exit 0

# plan mode 거침 판정: marker start_ts 이후 mtime 인 plan 파일 존재 → allow
# (enforce-plan-mode.sh 의 FRESH 블록과 동일 로직)
PLANS_DIR="${PLAN_MODE_PLANS_DIR:-$HOME/.claude/plans}"
FRESH=$(SF="$SESSION_FILE" PD="$PLANS_DIR" python3 - <<'PY' 2>/dev/null || echo unknown
import json, os, glob, datetime
sf = os.environ["SF"]; pd = os.environ["PD"]
try:
    ts = json.load(open(sf)).get("start_ts", "")
    st = datetime.datetime.fromisoformat(ts.replace("Z", "+00:00")).timestamp()
except Exception:
    print("unknown"); raise SystemExit
try:
    fresh = any(os.path.getmtime(p) >= st for p in glob.glob(os.path.join(pd, "*.md")))
except Exception:
    print("unknown"); raise SystemExit
print("1" if fresh else "0")
PY
)
[ "$FRESH" = "1" ] && exit 0
[ "$FRESH" = "unknown" ] && exit 0

# 마커 활성 + plan mode 미진입 → 차단
cat >&2 <<'EOF'
[enforce-dispatch-gate] plan-dev 세션인데 plan mode 미진입 상태에서 dispatch 시도.
   EnterPlanMode → plan 작성 → ExitPlanMode 로 사용자 승인 후 dispatch 할 것.
   우회: SKIP_DISPATCH_GATE=1 (1회) / DISABLE_DISPATCH_GATE_HOOK=1 (영구).
EOF
exit 2
