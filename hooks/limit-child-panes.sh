#!/usr/bin/env bash
# limit-child-panes.sh — PreToolUse: Bash hook.
# 자식 tmux pane spawn 명령 (`tmux-cli launch`, `${CLAUDE_PLUGIN_ROOT}/scripts/tmux-pane.sh launch`,
# `${CLAUDE_PLUGIN_ROOT}/scripts/cmux-pane.sh launch`, `${CLAUDE_PLUGIN_ROOT}/scripts/orca-pane.sh launch`,
# `${CLAUDE_PLUGIN_ROOT}/scripts/dispatch-slice-pane.sh`) 가 호출될 때,
# 현재 자식 (tmux pane + cmux workspace + orca terminal) 합산 수가
# CLAUDE_MAX_CHILD_PANES (기본 99) 이상이면 차단.
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
  *"tmux-cli launch"*|*"tmux-pane.sh launch"*|*"cmux-pane.sh launch"*|*"orca-pane.sh launch"*|*"dispatch-slice-pane.sh"*)
    ;;  # 검사 대상
  *)
    exit 0 ;;  # 관계 없음 통과
esac

# 현재 자식 수 합산 카운트
# 1) tmux: 관리 세션 'tmux-pane-mgr' 기준 (tmux 없으면 0)
# 2) cmux: cbp- prefix workspace 카운트 (cmux 없거나 ping 실패 시 0)
# 3) orca: 원장(reap-agents.sh, kind=orca) ref ∩ 살아있는 terminal, 자기 terminal 제외
#    (orca 또는 reap-agents.sh 없으면 0 — title 은 자식이 덮어써 식별 근거로 못 씀, 실측 2026-08-25)
LIMIT="${CLAUDE_MAX_CHILD_PANES:-99}"
TMUX_COUNT=0
CMUX_COUNT=0
ORCA_COUNT=0

if command -v tmux > /dev/null 2>&1; then
  TMUX_COUNT=$(tmux list-panes -s -t tmux-pane-mgr -F '#{pane_id}' 2>/dev/null | wc -l | tr -d ' ')
fi

CMUX_BIN_FOR_HOOK="${CMUX_BIN:-cmux}"
if command -v "$CMUX_BIN_FOR_HOOK" > /dev/null 2>&1; then
  if "$CMUX_BIN_FOR_HOOK" ping > /dev/null 2>&1; then
    # state file 우선: CMUX_WORKSPACE_ID set 시 state file 라인 수 카운트
    if [ -n "${CMUX_WORKSPACE_ID:-}" ]; then
      # state file 경로 계산 (cmux-pane.sh 의 cbp_state_path 와 동일 로직)
      if [ -n "${CBP_STATE_FILE:-}" ]; then
        _STATE_FILE="$CBP_STATE_FILE"
      else
        _ws="${CMUX_WORKSPACE_ID}"
        _sanitized=$(printf '%s' "$_ws" | tr ':/' '__')
        _STATE_FILE="${HOME}/.cache/cbp/children-${_sanitized}.json"
      fi
      # grep -c 는 match 0 일 때도 "0" 한 줄을 stdout 출력 + exit 1.
      # `|| echo 0` 를 붙이면 두 줄("0\n0")이 되어 산술 비교 깨짐. 안전하게 한 줄만 보장.
      if [ -f "$_STATE_FILE" ]; then
        CMUX_COUNT=$(grep -c 'surface=' "$_STATE_FILE" 2>/dev/null | head -1)
      else
        # state file 없으면 폴백: cbp- workspace 수
        CMUX_COUNT=$("$CMUX_BIN_FOR_HOOK" list-workspaces 2>/dev/null | grep -c '^cbp-' | head -1)
      fi
    else
      # CMUX_WORKSPACE_ID 미설정: 폴백 cbp- workspace 카운트
      CMUX_COUNT=$("$CMUX_BIN_FOR_HOOK" list-workspaces 2>/dev/null | grep -c '^cbp-' | head -1)
    fi
    [ -z "$CMUX_COUNT" ] && CMUX_COUNT=0
  fi
fi

ORCA_BIN_FOR_HOOK="${ORCA_BIN:-orca}"
REAP_AGENTS_FOR_HOOK="${REAP_AGENTS_BIN:-$(dirname "${BASH_SOURCE[0]}")/../scripts/reap-agents.sh}"
if command -v "$ORCA_BIN_FOR_HOOK" > /dev/null 2>&1 && [ -x "$REAP_AGENTS_FOR_HOOK" ]; then
  ORCA_JSON=$("$ORCA_BIN_FOR_HOOK" terminal list --worktree active --json 2>/dev/null)
  if [ -n "$ORCA_JSON" ]; then
    # 원장(kind=orca) 의 ref 목록 — title 은 자식 claude TUI 가 덮어써 식별 근거로 쓸 수
    # 없다(실측 2026-08-25). 원장 없으면 빈 목록 → count=0 (훅이 세션을 막지 않음).
    LEDGER_REFS_FOR_HOOK=$("$REAP_AGENTS_FOR_HOOK" list 2>/dev/null | python3 -c '
import json, sys
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        d = json.loads(line)
    except Exception:
        continue
    if d.get("kind") == "orca" and d.get("ref"):
        print(d["ref"])
' 2>/dev/null)
    # 원장 ref ∩ 살아있는 terminal handle, 자기 terminal(ORCA_TERMINAL_HANDLE) 제외.
    # grep -c 와 같은 함정(매치 0 이면 exit 1) 을 피하려 python3 가 항상 정수 한 줄만 찍는다.
    ORCA_COUNT=$(printf '%s' "$ORCA_JSON" | LEDGER_REFS="$LEDGER_REFS_FOR_HOOK" python3 -c "
import json, os, sys
self_handle = sys.argv[1] if len(sys.argv) > 1 else ''
try:
    d = json.load(sys.stdin)
except Exception:
    print(0)
    sys.exit(0)
if not d.get('ok'):
    print(0)
    sys.exit(0)
terms = (d.get('result') or {}).get('terminals') or []
refs = set(os.environ.get('LEDGER_REFS', '').splitlines())
count = 0
for t in terms:
    h = t.get('handle')
    if h and h in refs and h != self_handle:
        count += 1
print(count)
" "${ORCA_TERMINAL_HANDLE:-}" 2>/dev/null)
    [ -z "$ORCA_COUNT" ] && ORCA_COUNT=0
  fi
fi

CURRENT=$(( TMUX_COUNT + CMUX_COUNT + ORCA_COUNT ))

if [ "$CURRENT" -ge "$LIMIT" ]; then
  cat >&2 <<EOF
limit-child-panes: 한도 초과 — tmux pane: $TMUX_COUNT, cmux child: $CMUX_COUNT, orca child: $ORCA_COUNT, total: $CURRENT — 상한 $LIMIT 초과

차단된 명령: $CMD

우회:
  1. 기존 자식 pane 정리: \${CLAUDE_PLUGIN_ROOT}/scripts/tmux-pane.sh list 후 kill / \${CLAUDE_PLUGIN_ROOT}/scripts/cmux-pane.sh cleanup / \${CLAUDE_PLUGIN_ROOT}/scripts/orca-pane.sh cleanup
  2. 한도 상향: CLAUDE_MAX_CHILD_PANES=N 으로 재실행
  3. hook 영구 비활성: export DISABLE_PANE_LIMIT_HOOK=1
EOF
  exit 2
fi

exit 0
