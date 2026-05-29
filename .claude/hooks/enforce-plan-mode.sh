#!/usr/bin/env bash
# PreToolUse Write|Edit — /plan-dev plan mode 진입 강제.
#
# 목적: /plan-dev 는 plan mode(EnterPlanMode→ExitPlanMode 승인) 진입이 필수인데,
#   콘텐츠 가이드만 있고 하네스 강제가 없어 모델이 plan-dev-session start 만 돌리고
#   plan mode 를 건너뛴 채 바로 Edit/Write 직행해도 막히지 않았음. 이 hook 이 차단.
#
# 동작:
#   - plan-dev 세션 마커 없음 → no-op (비-plan-dev 세션 무관).
#   - permission_mode==plan → plan-mode-seen flag 기록 후 allow (plan mode 진입 신호.
#     plan 파일 자체 Write 가 이 경로로 들어옴. 하네스가 plan mode 중 편집 대상은 이미 제한).
#   - permission_mode==bypassPermissions → allow (dispatch 자식 / 명시 우회).
#   - flag 존재(이 세션에 plan mode 거침) → allow.
#   - 그 외(마커 활성 + plan mode 미진입) → exit 2 차단.
#
# 우회: SKIP_PLAN_MODE_ENFORCE=1 (1회) / DISABLE_PLAN_MODE_ENFORCE_HOOK=1 (영구).
#
# 환경변수(테스트 mock):
#   PLAN_MODE_SESSION_FILE — 마커 경로 override (디폴트 $CLAUDE_PROJECT_DIR/.git/plan-dev-session.json)
#   PLAN_MODE_SEEN_FILE    — plan-mode-seen flag 경로 override (디폴트 마커 디렉토리/plan-dev-plan-mode-seen)
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

# flag 경로
if [ -n "${PLAN_MODE_SEEN_FILE:-}" ]; then
  FLAG="$PLAN_MODE_SEEN_FILE"
else
  FLAG="$(dirname "$SESSION_FILE")/plan-dev-plan-mode-seen"
fi

# plan mode 진입 신호 → flag 기록 후 allow (하네스가 plan mode 편집 대상 제한)
if [ "$PMODE" = "plan" ]; then
  mkdir -p "$(dirname "$FLAG")" 2>/dev/null || true
  : > "$FLAG" 2>/dev/null || true
  exit 0
fi

# dispatch 자식 / 명시 우회 모드 → allow
[ "$PMODE" = "bypassPermissions" ] && exit 0

# 이 세션에 plan mode 거침 → allow
[ -f "$FLAG" ] && exit 0

# 마커 활성 + plan mode 미진입 → 차단
cat >&2 <<EOF
🛑 [enforce-plan-mode] /plan-dev 세션 활성인데 plan mode 미진입 상태에서 ${TOOL} 시도.
   /plan-dev 는 plan mode 진입이 필수 — 먼저 EnterPlanMode 호출 → plan 파일 작성 →
   ExitPlanMode 로 사용자 승인 후 편집할 것.
   우회: SKIP_PLAN_MODE_ENFORCE=1 (1회) / DISABLE_PLAN_MODE_ENFORCE_HOOK=1 (영구).
EOF
exit 2
