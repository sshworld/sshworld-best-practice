#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PASS=0; FAIL=0
ok()  { echo "  ok: $1"; PASS=$((PASS+1)); }
fail(){ echo "FAIL: $1"; FAIL=$((FAIL+1)); }

# 1. plugin.json mcpServers.codegraph 존재 + JSON valid
PLUGIN="$REPO_ROOT/.claude-plugin/plugin.json"
if python3 -c "import json,sys; d=json.load(open('$PLUGIN')); assert 'mcpServers' in d, 'no mcpServers'; assert 'codegraph' in d['mcpServers'], 'no codegraph'" 2>/dev/null; then
  ok "plugin.json has mcpServers.codegraph (JSON valid)"
else
  fail "plugin.json missing mcpServers.codegraph or invalid JSON"
fi

# 2. codegraph command is npx or codegraph (graceful, not a hard path)
CMD=$(python3 -c "import json; d=json.load(open('$PLUGIN')); print(d['mcpServers']['codegraph']['command'])" 2>/dev/null || echo "")
if [[ "$CMD" == "npx" || "$CMD" == "codegraph" ]]; then
  ok "codegraph command is graceful ($CMD)"
else
  fail "codegraph command is not graceful: '$CMD'"
fi

# 3. docs/infra-setup.md exists + mentions codegraph init + headroom
DOCS="$REPO_ROOT/docs/infra-setup.md"
if [[ -f "$DOCS" ]]; then
  ok "docs/infra-setup.md exists"
else
  fail "docs/infra-setup.md missing"
fi

if grep -q "codegraph init" "$DOCS" 2>/dev/null; then
  ok "docs/infra-setup.md mentions codegraph init"
else
  fail "docs/infra-setup.md missing 'codegraph init'"
fi

if grep -q "headroom" "$DOCS" 2>/dev/null; then
  ok "docs/infra-setup.md mentions headroom"
else
  fail "docs/infra-setup.md missing 'headroom'"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
