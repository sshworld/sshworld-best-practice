#!/usr/bin/env bash
# limit-child-panes.sh — PreToolUse: Bash hook.
# 자식 tmux pane spawn 명령 (`tmux-cli launch`, `scripts/tmux-pane.sh launch`,
# `scripts/dispatch-slice-pane.sh`) 가 호출될 때, 현재 자식 pane 수가
# CLAUDE_MAX_CHILD_PANES (기본 5) 이상이면 차단.
#
# stdin: {"tool_name":"Bash","tool_input":{"command":"..."}, ...}
# exit 0: 통과 / exit 2: 차단 (stderr 에 사유 + 우회법)
#
# 우회: DISABLE_PANE_LIMIT_HOOK=1 또는 CLAUDE_MAX_CHILD_PANES=<큰수>

set -uo pipefail

# stdin 항상 흡수 (호출자 pipe SIGPIPE 회피)
PAYLOAD=$(cat)

# 우회 환경변수
if [ "${DISABLE_PANE_LIMIT_HOOK:-0}" = "1" ]; then
  exit 0
fi
CMD=$(echo "$PAYLOAD" | python3 -c "
import json,sys
try:
    d=json.load(sys.stdin)
    print(d.get('tool_input',{}).get('command',''))
except Exception:
    pass
" 2>/dev/null)

# 자식 pane 을 spawn 하는 명령 패턴인지 검사
case "$CMD" in
  *"tmux-cli launch"*|*"tmux-pane.sh launch"*|*"dispatch-slice-pane.sh"*)
    ;;  # 검사 대상
  *)
    exit 0 ;;  # 관계 없음 통과
esac

# 현재 자식 pane 수 (관리 세션 'tmux-pane-mgr' 기준 — 외부 tmux 없으면 0)
LIMIT="${CLAUDE_MAX_CHILD_PANES:-5}"
CURRENT=0
if command -v tmux > /dev/null 2>&1; then
  CURRENT=$(tmux list-panes -s -t tmux-pane-mgr -F '#{pane_id}' 2>/dev/null | wc -l | tr -d ' ')
fi

if [ "$CURRENT" -ge "$LIMIT" ]; then
  cat >&2 <<EOF
limit-child-panes: 한도 초과 — 현재 자식 pane 수: $CURRENT / 한도: $LIMIT

차단된 명령: $CMD

우회:
  1. 기존 자식 pane 정리: scripts/tmux-pane.sh list 후 kill
  2. 한도 상향: CLAUDE_MAX_CHILD_PANES=N 으로 재실행
  3. hook 영구 비활성: export DISABLE_PANE_LIMIT_HOOK=1
EOF
  exit 2
fi

exit 0
