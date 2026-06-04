#!/usr/bin/env bash
# SessionStart hook — cmux env 감지 시 dispatch-first 안내를 stdout 으로 출력.
# 비-cmux 환경엔 출력 없음 (exit 0). 출력은 additionalContext 로 모델에 inject 됨.
#
# 정책: cmux workspace 에서는 plan-dev Slice 가 **dispatch(cmux) 기본**.
#   direct-edit 는 opt-in 예외(+1줄 justification). 비-cmux 환경은 direct-edit 기본(무관).
#   하드 차단 아님 — advisory nudge (편집 자체는 자유).
set -uo pipefail

[ -z "${CMUX_WORKSPACE_ID:-}" ] && exit 0

cat <<'EOF'
=== cmux dispatch 기본 (이 세션 cmux 환경) ===
- 이 워크스페이스는 cmux. plan-dev Slice 는 **dispatch(cmux) 기본** — 직접 Edit 가 아니라
  @@SCRIPTS_DIR@@/dispatch-slice-pane.sh --mode=cmux 로 자식 surface 띄워 작업.
- Slice File Map 의 Mode 는 cmux 환경에선 dispatch 가 기본값. direct-edit 는 **opt-in 예외**로,
  선택 시 1줄 justification 필수 (예: "정책/문서 파일 자체 편집", "단일 trivial 수정").
- 자식 surface 는 cmux 사이드바에서 사용자가 직접 진행 시각화. 회수: @@SCRIPTS_DIR@@/cmux-pane.sh
  wait-idle → read-screen | grep ✅/❌.
- 비-cmux 환경이면 이 안내는 안 뜸 (direct-edit 기본 유지).
EOF
exit 0
