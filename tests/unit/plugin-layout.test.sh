#!/usr/bin/env bash
set -euo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
PASS=0; FAIL=0

ok()   { echo "  PASS: $*"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $*"; FAIL=$((FAIL+1)); }

echo "=== plugin-layout tests ==="

# 1. .claude-plugin/plugin.json 존재 + valid JSON + name == "sshworld"
if [ -f "$REPO/.claude-plugin/plugin.json" ]; then
  ok ".claude-plugin/plugin.json 존재"
  if python3 -c "import json,sys; d=json.load(open('$REPO/.claude-plugin/plugin.json')); sys.exit(0 if d.get('name')=='sshworld' else 1)" 2>/dev/null; then
    ok "plugin.json valid JSON + name==sshworld"
  else
    fail "plugin.json invalid JSON 또는 name!=sshworld"
  fi
else
  fail ".claude-plugin/plugin.json 없음"
  fail "plugin.json valid JSON + name==sshworld (skip)"
fi

# 2. .claude-plugin/marketplace.json 존재 + valid JSON
if [ -f "$REPO/.claude-plugin/marketplace.json" ]; then
  ok ".claude-plugin/marketplace.json 존재"
  if python3 -c "import json; json.load(open('$REPO/.claude-plugin/marketplace.json'))" 2>/dev/null; then
    ok "marketplace.json valid JSON"
  else
    fail "marketplace.json invalid JSON"
  fi
else
  fail ".claude-plugin/marketplace.json 없음"
  fail "marketplace.json valid JSON (skip)"
fi

# 3. 루트에 commands/ agents/ skills/ hooks/ 존재
for d in commands agents skills hooks; do
  if [ -d "$REPO/$d" ]; then
    ok "루트 $d/ 존재"
  else
    fail "루트 $d/ 없음"
  fi
done

# 4. hooks/hooks.json 존재 + valid JSON + ${CLAUDE_PLUGIN_ROOT} 포함
if [ -f "$REPO/hooks/hooks.json" ]; then
  ok "hooks/hooks.json 존재"
  if python3 -c "import json; json.load(open('$REPO/hooks/hooks.json'))" 2>/dev/null; then
    ok "hooks/hooks.json valid JSON"
  else
    fail "hooks/hooks.json invalid JSON"
  fi
  if grep -q 'CLAUDE_PLUGIN_ROOT' "$REPO/hooks/hooks.json"; then
    ok "hooks/hooks.json CLAUDE_PLUGIN_ROOT 포함"
  else
    fail "hooks/hooks.json CLAUDE_PLUGIN_ROOT 없음"
  fi
else
  fail "hooks/hooks.json 없음"
  fail "hooks/hooks.json valid JSON (skip)"
  fail "hooks/hooks.json CLAUDE_PLUGIN_ROOT 없음 (skip)"
fi

# 5. /Users/sshworld/scripts 잔존 0 (commands/ agents/ hooks/ skills/)
residuals=$(grep -rln "/Users/sshworld/scripts" \
  "$REPO/commands" "$REPO/agents" "$REPO/hooks" "$REPO/skills" 2>/dev/null || true)
if [ -z "$residuals" ]; then
  ok "잔존 /Users/sshworld/scripts 없음"
else
  fail "잔존 /Users/sshworld/scripts: $residuals"
fi

# 6. hooks/ 내 CLAUDE_PLUGIN_ROOT 존재
if grep -rq "CLAUDE_PLUGIN_ROOT" "$REPO/hooks" 2>/dev/null; then
  ok "hooks/ CLAUDE_PLUGIN_ROOT 사용"
else
  fail "hooks/ CLAUDE_PLUGIN_ROOT 없음"
fi

echo ""
echo "결과: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
