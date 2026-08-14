#!/usr/bin/env bash
# SessionStart hook — cmux env 감지 시 dispatch-first 안내를 stdout 으로 출력.
# 비-cmux 환경엔 출력 없음 (exit 0). 출력은 additionalContext 로 모델에 inject 됨.
#
# 정책: cmux workspace 에서는 plan-dev Slice 가 **dispatch(cmux) 기본**.
#   direct-edit 는 plan Mode 컬럼에 쓰지 않는다 — ExitPlanMode 게이트(enforce-cmux-dispatch)가 차단.
#   정말 direct-edit 가 필요하면 CMUX_DIRECT_EDIT_OK=1 escape (ExitPlanMode 게이트 1회 통과).
#   비-cmux 환경은 direct-edit 기본(무관). advisory nudge.
set -uo pipefail

[ -z "${CMUX_WORKSPACE_ID:-}" ] && exit 0

cat <<'EOF'
=== cmux dispatch 기본 (이 세션 cmux 환경) ===
- 이 워크스페이스는 cmux. plan-dev Slice 는 **dispatch(cmux) 기본** — 직접 Edit 가 아니라
  ${CLAUDE_PLUGIN_ROOT}/scripts/dispatch-slice-pane.sh --mode=cmux 로 자식 surface 띄워 작업.
- Slice File Map 의 Mode 는 cmux 환경에서 **dispatch(cmux) 만** 정상값.
  direct-edit 가 정말 필요하면(dispatch 자체가 불가한 환경 등 진짜 예외) out-of-band escape:
    CMUX_DIRECT_EDIT_OK=1 <명령>  — ExitPlanMode 게이트(enforce-cmux-dispatch) 1회 통과.
- 자식 surface 는 cmux 사이드바에서 사용자가 직접 진행 시각화. 회수: ${CLAUDE_PLUGIN_ROOT}/scripts/cmux-pane.sh
  wait-idle → capture | grep ✅/❌.
- 비-cmux 환경이면 이 안내는 안 뜸 (direct-edit 기본 유지).
EOF
exit 0
