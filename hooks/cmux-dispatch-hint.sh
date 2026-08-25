#!/usr/bin/env bash
# SessionStart hook — cmux/orca env 감지 시 dispatch-first 안내를 stdout 으로 출력.
# tmux·비-mux 환경엔 출력 없음 (exit 0). 출력은 additionalContext 로 모델에 inject 됨.
#
# 정책: cmux 또는 orca workspace 에서는 plan-dev Slice 가 **dispatch(해당 멀티플렉서) 기본**.
#   direct-edit 는 plan Mode 컬럼에 쓰지 않는다 — ExitPlanMode 게이트(enforce-cmux-dispatch)가 차단.
#   정말 direct-edit 가 필요하면 CBP_DIRECT_EDIT_OK=1(또는 CMUX_DIRECT_EDIT_OK=1) escape.
#   tmux·비-mux 환경은 direct-edit 기본(무관). advisory nudge.
#
# 멀티플렉서 종류 판정은 직접 신호(env var)만 본다 — scripts/detect-pane-env.sh 의
# ping/status 프로브(외부 프로세스 호출)는 SessionStart 라 하더라도 불필요한 지연이라 쓰지 않는다.
# 우선순위는 그 스크립트와 동일: tmux > cmux > orca > 그 외.
set -uo pipefail

if [ -n "${TMUX:-}" ]; then
  exit 0
elif [ -n "${CMUX_WORKSPACE_ID:-}" ] || [ -n "${CMUX_SURFACE_ID:-}" ] || [ -n "${CMUX_SOCKET:-}" ] || [ -n "${CMUX_SOCKET_PASSWORD:-}" ]; then
  KIND=cmux
elif [ -n "${ORCA_TERMINAL_HANDLE:-}" ] || [ -n "${ORCA_WORKSPACE_ID:-}" ] || [ "${TERM_PROGRAM:-}" = "Orca" ]; then
  KIND=orca
else
  exit 0
fi

case "$KIND" in
  cmux)
    MUX_NAME="cmux"; WRAPPER="cmux-pane.sh"; MODE="cmux"
    ;;
  orca)
    MUX_NAME="orca"; WRAPPER="orca-pane.sh"; MODE="orca"
    ;;
esac

cat <<EOF
=== ${MUX_NAME} dispatch 기본 (이 세션 ${MUX_NAME} 환경) ===
- 이 워크스페이스는 ${MUX_NAME}. plan-dev Slice 는 **dispatch(${MUX_NAME}) 기본** — 직접 Edit 가 아니라
  \${CLAUDE_PLUGIN_ROOT}/scripts/dispatch-slice-pane.sh --mode=${MODE} 로 자식 surface 띄워 작업.
- Slice File Map 의 Mode 는 ${MUX_NAME} 환경에서 **dispatch(${MUX_NAME}) 만** 정상값.
  direct-edit 가 정말 필요하면(dispatch 자체가 불가한 환경 등 진짜 예외) out-of-band escape:
    CBP_DIRECT_EDIT_OK=1 <명령>  — ExitPlanMode 게이트(enforce-cmux-dispatch) 1회 통과.
- 자식 surface 는 ${MUX_NAME} 사이드바에서 사용자가 직접 진행 시각화. 회수: \${CLAUDE_PLUGIN_ROOT}/scripts/${WRAPPER}
  wait-idle → capture | grep ✅/❌.
- tmux·비-mux 환경이면 이 안내는 안 뜸 (direct-edit 기본 유지).
EOF
exit 0
