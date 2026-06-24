#!/usr/bin/env bash
# Slice D — limit-child-panes.sh hook 의 차단/우회 동작 검증.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$REPO/hooks/limit-child-panes.sh"

step() { echo "[$1] $2"; }
fail() { echo "❌ FAIL: $1" >&2; exit 1; }

[ -x "$HOOK" ] || fail "hook not executable"

# PreToolUse Bash hook 은 stdin 으로 JSON 을 받는다.
# {"tool_name": "Bash", "tool_input": {"command": "..."}}
make_payload() {
  local cmd="$1"
  printf '{"tool_name":"Bash","tool_input":{"command":%s}}' "$(python3 -c "import json,sys; print(json.dumps(sys.argv[1]))" "$cmd")"
}

step 1 "관계없는 명령은 통과 (exit 0)"
echo "$(make_payload 'ls -la')" | "$HOOK" >/dev/null 2>&1
RC=$?
[ "$RC" = "0" ] || fail "irrelevant command should pass, got $RC"

step 2 "launch 명령 + CLAUDE_MAX_CHILD_PANES=0 → 차단 (exit 2)"
OUT=$(echo "$(make_payload './scripts/tmux-pane.sh launch zsh')" | CLAUDE_MAX_CHILD_PANES=0 "$HOOK" 2>&1)
RC=$?
[ "$RC" = "2" ] || fail "limit=0 launch should block (exit 2), got $RC; out=$OUT"
echo "$OUT" | grep -q "한도 초과" || fail "stderr missing 한도 초과: $OUT"
echo "$OUT" | grep -q "CLAUDE_MAX_CHILD_PANES" || fail "stderr missing bypass hint: $OUT"

step 3 "DISABLE_PANE_LIMIT_HOOK=1 → 우회 (exit 0)"
echo "$(make_payload './scripts/tmux-pane.sh launch zsh')" | CLAUDE_MAX_CHILD_PANES=0 DISABLE_PANE_LIMIT_HOOK=1 "$HOOK" >/dev/null 2>&1
RC=$?
[ "$RC" = "0" ] || fail "DISABLE bypass failed, got $RC"

step 4 "tmux-cli launch 도 같은 패턴 차단"
echo "$(make_payload 'tmux-cli launch zsh')" | CLAUDE_MAX_CHILD_PANES=0 "$HOOK" >/dev/null 2>&1
RC=$?
[ "$RC" = "2" ] || fail "tmux-cli launch limit=0 should block, got $RC"

step 5 "dispatch-slice-pane 도 launch 와 같이 카운트 대상"
echo "$(make_payload './scripts/dispatch-slice-pane.sh --slice=x --spec-file=y')" | CLAUDE_MAX_CHILD_PANES=0 "$HOOK" >/dev/null 2>&1
RC=$?
[ "$RC" = "2" ] || fail "dispatcher limit=0 should block, got $RC"

echo "OK"
