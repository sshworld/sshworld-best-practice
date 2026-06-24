#!/usr/bin/env bash
# PreToolUse Write|Edit — /plan-dev plan mode 진입 강제.
#
# 목적: /plan-dev 는 plan mode(EnterPlanMode→ExitPlanMode 승인) 진입이 필수인데,
#   콘텐츠 가이드만 있고 하네스 강제가 없어 모델이 plan-dev-session start 만 돌리고
#   plan mode 를 건너뛴 채 바로 Edit/Write 직행해도 막히지 않았음. 이 hook 이 차단.
#
# "plan mode 거침" 판정 = PLANS_DIR(~/.claude/plans)에 marker 의 start_ts 이후 작성된
#   plan 파일이 존재. marker 는 Phase 0(plan-dev-session start)에 start_ts 기록 → plan mode
#   진입 시 작성하는 plan 파일 mtime 이 그보다 큼.
#   ⚠️ marker **파일 mtime** 이 아니라 **start_ts JSON 필드** 사용 — plan-dev-progress.sh 가
#      total_slices 등으로 marker 를 재기록해 mtime 을 plan 보다 newer 로 bump 하기 때문
#      (mtime 기준이면 progress start 후 매번 false-positive 차단). start_ts 는 progress 가 보존.
#   (과거: PreToolUse Write 의 permission_mode==plan 시 flag 를 찍는 방식이었으나, plan 파일
#    write 가 일반 Write tool 경로를 안 타 flag 미기록 → 승인 후 모든 Edit 를 false-positive
#    차단했음. 신호를 start_ts 기반 plan-파일 탐지로 교체해 수정.)
#
# 동작:
#   - plan-dev 세션 마커 없음 → no-op (비-plan-dev 세션 무관).
#   - permission_mode==plan → allow (plan mode 중 — 하네스가 편집 대상 제한).
#   - permission_mode==bypassPermissions → allow (dispatch 자식 / 명시 우회).
#   - 자식 worktree(git-dir≠git-common-dir) → allow.
#   - marker start_ts 이후 작성된 plan 파일 존재 → allow (plan mode 거침).
#   - start_ts 파싱 불가 → conservative allow (false-block 회피).
#   - 그 외(마커 활성 + plan mode 미진입) → exit 2 차단.
#
# 우회: SKIP_PLAN_MODE_ENFORCE=1 (1회) / DISABLE_PLAN_MODE_ENFORCE_HOOK=1 (영구).
#
# 한계: plan 을 reject 해도 plan 파일은 남아 통과. 본 hook 목적은 "plan mode 아예 미진입"
#   catch 이지 "plan reject 후 강행" 방지가 아님.
#
# 환경변수(테스트 mock):
#   PLAN_MODE_SESSION_FILE — 마커 경로 override (디폴트 $CLAUDE_PROJECT_DIR/.git/plan-dev-session.json)
#   PLAN_MODE_PLANS_DIR    — plan 파일 디렉토리 override (디폴트 $HOME/.claude/plans)
set -uo pipefail

[ "${DISABLE_PLAN_MODE_ENFORCE_HOOK:-0}" = "1" ] && exit 0
[ "${SKIP_PLAN_MODE_ENFORCE:-0}" = "1" ] && exit 0

PAYLOAD=$(cat)

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
SESSION_FILE="${PLAN_MODE_SESSION_FILE:-$PROJECT_DIR/.git/plan-dev-session.json}"

# 마커 없음 → 비-plan-dev 세션 → no-op
[ -f "$SESSION_FILE" ] || exit 0

# dispatch 자식 worktree 감지 (git-dir != git-common-dir) → skip
GIT_DIR=$(git rev-parse --git-dir 2>/dev/null || true)
GIT_COMMON=$(git rev-parse --git-common-dir 2>/dev/null || true)
if [ -n "$GIT_DIR" ] && [ -n "$GIT_COMMON" ] && [ "$GIT_DIR" != "$GIT_COMMON" ]; then
  exit 0
fi

TOOL=$(printf '%s' "$PAYLOAD" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('tool_name',''))" 2>/dev/null || echo "")
case "$TOOL" in Write|Edit) ;; *) exit 0 ;; esac

PMODE=$(printf '%s' "$PAYLOAD" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('permission_mode',''))" 2>/dev/null || echo "")

# plan mode 중 / dispatch 자식·명시 우회 모드 → allow
[ "$PMODE" = "plan" ] && exit 0
[ "$PMODE" = "bypassPermissions" ] && exit 0

# 이 세션에 plan mode 거침 = marker start_ts 이후 작성된 plan 파일 존재 → allow.
# start_ts 파싱 불가 시 "unknown" → conservative allow.
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
cat >&2 <<EOF
🛑 [enforce-plan-mode] /plan-dev 세션 활성인데 plan mode 미진입 상태에서 ${TOOL} 시도.
   /plan-dev 는 plan mode 진입이 필수 — 먼저 EnterPlanMode 호출 → plan 파일 작성 →
   ExitPlanMode 로 사용자 승인 후 편집할 것.
   우회: SKIP_PLAN_MODE_ENFORCE=1 (1회) / DISABLE_PLAN_MODE_ENFORCE_HOOK=1 (영구).
EOF
exit 2
