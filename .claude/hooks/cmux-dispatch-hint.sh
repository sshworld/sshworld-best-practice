#!/usr/bin/env bash
# SessionStart hook — cmux env 감지 시 dispatch-first 안내를 stdout 으로 출력.
# 비-cmux 환경엔 출력 없음. additionalContext 로 모델에 inject 됨.
set -uo pipefail

[ -z "${CMUX_WORKSPACE_ID:-}" ] && exit 0

cat <<'EOF'
=== cmux dispatch 사용 가이드 (이 세션 cmux 환경) ===
- 슬라이스/멀티-파일 작업은 직접 Edit 대신 scripts/dispatch-slice-pane.sh --mode=cmux 로 자식 surface 띄우기 권장.
- 자식 surface 는 cmux 사이드바에서 사용자가 직접 진행 시각화 가능.
- 회수: scripts/cmux-pane.sh wait-idle → read-screen | grep ✅/❌.
- Edit/Write 누적 3회 시 PreToolUse advisory 알림 (CMUX_EDIT_BURST_THRESHOLD 로 조정).
EOF
exit 0
