#!/usr/bin/env bash
# SessionStart hook — no-op.
# (구) cmux env 에서 dispatch-first 안내를 inject 했으나, "진행 명령받았다고 반사적
# cmux dispatch" 압박을 제거하는 정책(direct-edit 기본, cmux opt-in)에 따라 비활성화.
# cmux dispatch 경로(scripts/dispatch-slice-pane.sh --mode=cmux)는 사용자 opt-in 시 그대로 동작.
# 파일/등록은 유지 (settings.json + install.sh propagate 호환). 되살리려면 git history 참조.
set -uo pipefail
exit 0
