#!/usr/bin/env bash
# Slice D — settings.json 의 좁힌 tmux permission + kill-server deny 검증.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SETTINGS="$REPO/.claude/settings.json"

step() { echo "[$1] $2"; }
fail() { echo "❌ FAIL: $1" >&2; exit 1; }

if ! command -v python3 > /dev/null 2>&1; then
  echo "SKIP: python3 not available"
  exit 0
fi

step 1 "광역 Bash(tmux*) 없음"
python3 -c "
import json,sys
d=json.load(open('$SETTINGS'))
allow=d.get('permissions',{}).get('allow',[])
assert 'Bash(tmux*)' not in allow, 'broad tmux allow present'
" || fail "broad tmux* allow detected"

step 2 "좁힌 패턴 6개 + wrapper allow"
python3 -c "
import json,sys
d=json.load(open('$SETTINGS'))
allow=set(d.get('permissions',{}).get('allow',[]))
expected={'Bash(tmux new-window*)','Bash(tmux send-keys*)','Bash(tmux capture-pane*)','Bash(tmux display-message*)','Bash(tmux list-panes*)','Bash(tmux kill-pane*)','Bash(tmux-cli*)'}
missing=expected - allow
assert not missing, f'missing narrow perms: {missing}'
" || fail "narrow perms incomplete"

step 3 "kill-server deny"
python3 -c "
import json,sys
d=json.load(open('$SETTINGS'))
deny=d.get('permissions',{}).get('deny',[])
assert 'Bash(tmux kill-server*)' in deny, 'kill-server not denied'
" || fail "kill-server deny missing"

step 4 "cmux notify/set-status/set-progress/clear-status/clear-progress allow"
grep -qF '"Bash(cmux notify*)"' "$SETTINGS" || fail "cmux notify allow missing"
grep -qF '"Bash(cmux set-status*)"' "$SETTINGS" || fail "cmux set-status allow missing"
grep -qF '"Bash(cmux set-progress*)"' "$SETTINGS" || fail "cmux set-progress allow missing"
grep -qF '"Bash(cmux clear-status*)"' "$SETTINGS" || fail "cmux clear-status allow missing"
grep -qF '"Bash(cmux clear-progress*)"' "$SETTINGS" || fail "cmux clear-progress allow missing"

step 5 "plan-dev scripts allow"
grep -qF '"Bash(*/scripts/finish-plan-dev.sh*)"' "$SETTINGS" || fail "finish-plan-dev allow missing"
grep -qF '"Bash(*/scripts/plan-dev-progress.sh*)"' "$SETTINGS" || fail "plan-dev-progress allow missing"

echo "OK"
