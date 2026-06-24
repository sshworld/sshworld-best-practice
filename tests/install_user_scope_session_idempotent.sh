#!/usr/bin/env bash
# install user scope deprecated → hooks/hooks.json 안정성 검증 (idempotent 대체).

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0; FAILED=()
run() { local name="$1"; shift; if "$@" >/dev/null 2>&1; then echo "✔ $name"; PASS=$((PASS+1)); else echo "✘ $name"; FAIL=$((FAIL+1)); FAILED+=("$name"); fi; }

t_hooks_json_valid() {
  python3 -c "import json; json.load(open('$REPO/hooks/hooks.json'))"
}

t_hooks_json_has_session_start() {
  python3 -c "
import json, sys
d = json.load(open('$REPO/hooks/hooks.json'))
hooks = d.get('hooks', {})
ss = hooks.get('SessionStart', [])
if not ss or not ss[0].get('hooks'):
    sys.exit(1)
"
}

t_hooks_json_plugin_root_form() {
  # SessionStart inline command 에 \${CLAUDE_PLUGIN_ROOT} 형태
  python3 -c "
import json, sys
d = json.load(open('$REPO/hooks/hooks.json'))
cmds = [h['command'] for ev in d['hooks'].values() for m in ev for h in m.get('hooks', [])]
if not any('CLAUDE_PLUGIN_ROOT' in c for c in cmds):
    sys.exit(1)
"
}

run "hooks.json valid JSON" t_hooks_json_valid
run "SessionStart hooks 존재" t_hooks_json_has_session_start
run "hook command 에 CLAUDE_PLUGIN_ROOT 형태" t_hooks_json_plugin_root_form

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && echo "✅ all pass" || { echo "❌ FAILED: ${FAILED[*]}"; exit 1; }
