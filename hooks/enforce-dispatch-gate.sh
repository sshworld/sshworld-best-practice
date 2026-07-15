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
#   - marker 가 24시간 넘게 stale → exit 0 (이전 세션 잔재)
#   - start_ts 파싱 불가 → conservative exit 0
#   - marker `plan_file` 있고 stat 가능 ∧ mtime ≥ (start_ts − GRACE) → exit 0 (세션격리 latch)
#   - marker `plan_file` 있고 stat 가능 ∧ mtime < (start_ts − GRACE) → exit 2 (latch 확정 차단 — 폴백 안 함)
#   - marker `plan_file` 없음/stat 불가 → 전역 glob 폴백: `$HOME/.claude/plans/*.md` 중
#     mtime ≥ (start_ts − GRACE) 존재 → exit 0. 없으면 exit 2.
#     (폴백=세션격리 약함 — plan_file 이 아직 latch 되지 않은 최초 1회에만 해당)
#   - GRACE=600(초) — plan mode 를 Phase 0 세션 시작보다 먼저 써도(순서 무관) 판정 통과.
#
# 우회:
#   SKIP_DISPATCH_GATE=1          — 1회 우회
#   DISABLE_DISPATCH_GATE_HOOK=1  — 영구 비활성
#
# 환경변수(테스트 mock):
#   DISPATCH_GATE_SESSION_FILE — 세션 marker 경로 override
#   PLAN_MODE_PLANS_DIR        — plan 파일 디렉토리 override (디폴트 $HOME/.claude/plans)
set -uo pipefail

GRACE=600

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

# skip-once marker-file escape (R1): <git-common-dir>/cbp-skip-once-dispatch-gate.
# 원자적 소비(rm, -f 금지)에 성공한 1개 프로세스만 allow.
if [ -n "$GIT_COMMON" ] && rm "${GIT_COMMON}/cbp-skip-once-dispatch-gate" 2>/dev/null; then
  exit 0
fi

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

# plan mode 거침 판정 — read-only. 우선순위:
#   1) marker plan_file latch (stat 가능 시 결정적 — GRACE 창 안이면 allow, 밖이면 확정 block)
#   2) plan_file 없음/stat 불가 → 전역 glob 폴백 (GRACE 반영)
PLANS_DIR="${PLAN_MODE_PLANS_DIR:-$HOME/.claude/plans}"
FRESH=$(SF="$SESSION_FILE" PD="$PLANS_DIR" GRACE="$GRACE" python3 - <<'PY' 2>/dev/null || echo unknown
import json, os, glob, datetime
sf = os.environ["SF"]; pd = os.environ["PD"]; grace = float(os.environ["GRACE"])
try:
    data = json.load(open(sf))
    ts = data.get("start_ts", "")
    st = datetime.datetime.fromisoformat(ts.replace("Z", "+00:00"))
    now = datetime.datetime.now(datetime.timezone.utc)
    if (now - st).total_seconds() >= 24 * 3600:
        print("stale"); raise SystemExit
except SystemExit:
    raise
except Exception:
    print("unknown"); raise SystemExit

threshold = st.timestamp() - grace
plan_file = data.get("plan_file", "")

if plan_file:
    try:
        mtime = os.path.getmtime(plan_file)
        print("allow" if mtime >= threshold else "block")
        raise SystemExit
    except SystemExit:
        raise
    except Exception:
        pass  # stat 불가 → absent 취급, 폴백으로

try:
    fresh = any(os.path.getmtime(p) >= threshold for p in glob.glob(os.path.join(pd, "*.md")))
except Exception:
    print("unknown"); raise SystemExit
print("allow" if fresh else "block")
PY
)
[ "$FRESH" = "allow" ] && exit 0
[ "$FRESH" = "unknown" ] && exit 0
if [ "$FRESH" = "stale" ]; then
  cat >&2 <<EOF
⚠️  [enforce-dispatch-gate] plan-dev 세션 marker 가 24시간 넘게 stale — 이전 세션 잔재로 판단해 allow.
   정리: rm "$SESSION_FILE" (또는 scripts/plan-dev-session.sh clear)
EOF
  exit 0
fi

# FRESH = "block": plan_file latch 확정 차단이거나 전역 폴백도 미탐지.
cat >&2 <<EOF
[enforce-dispatch-gate] plan-dev 세션인데 plan mode 미진입 상태에서 dispatch 시도.
   EnterPlanMode → plan 작성 → ExitPlanMode 로 사용자 승인 후 dispatch 할 것.
   1회 우회: touch "\$(git rev-parse --git-common-dir)/cbp-skip-once-dispatch-gate"
   그 외: SKIP_DISPATCH_GATE=1 (1회) / DISABLE_DISPATCH_GATE_HOOK=1 (영구).
EOF
exit 2
