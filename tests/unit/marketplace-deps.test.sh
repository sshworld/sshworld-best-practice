#!/usr/bin/env bash
set -uo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PASS=0; FAIL=0

ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
fail(){ echo "FAIL: $1"; FAIL=$((FAIL+1)); }

MARKET="$REPO_ROOT/.claude-plugin/marketplace.json"
PLUGIN="$REPO_ROOT/.claude-plugin/plugin.json"

# marketplace.json valid JSON
if python3 -c "import json; json.load(open('$MARKET'))" 2>/dev/null; then
  ok "marketplace.json valid JSON"
else
  fail "marketplace.json not valid JSON"
fi

# name == sshworld-best-practice
NAME=$(python3 -c "import json; print(json.load(open('$MARKET'))['name'])" 2>/dev/null || echo "")
if [[ "$NAME" == "sshworld-best-practice" ]]; then
  ok "name==sshworld-best-practice"
else
  fail "name=$NAME (expected sshworld-best-practice)"
fi

# 4 entries: sshworld, taste-skill, andrej-karpathy-skills, caveman
for p in sshworld taste-skill andrej-karpathy-skills caveman; do
  FOUND=$(python3 -c "import json; plugins=json.load(open('$MARKET'))['plugins']; print(any(pl['name']=='$p' for pl in plugins))" 2>/dev/null || echo "False")
  if [[ "$FOUND" == "True" ]]; then
    ok "marketplace has $p"
  else
    fail "marketplace missing $p"
  fi
done

# caveman defaultEnabled == false
CAVEMAN_DE=$(python3 -c "
import json
plugins=json.load(open('$MARKET'))['plugins']
c=[pl for pl in plugins if pl['name']=='caveman']
print(c[0].get('defaultEnabled','MISSING') if c else 'MISSING')
" 2>/dev/null || echo "MISSING")
if [[ "$CAVEMAN_DE" == "False" ]]; then
  ok "caveman defaultEnabled==false"
else
  fail "caveman defaultEnabled=$CAVEMAN_DE (expected False)"
fi

# allowCrossMarketplaceDependenciesOn exists
HAS_FIELD=$(python3 -c "import json; d=json.load(open('$MARKET')); print('allowCrossMarketplaceDependenciesOn' in d)" 2>/dev/null || echo "False")
if [[ "$HAS_FIELD" == "True" ]]; then
  ok "allowCrossMarketplaceDependenciesOn field exists"
else
  fail "allowCrossMarketplaceDependenciesOn missing"
fi

# plugin.json valid JSON
if python3 -c "import json; json.load(open('$PLUGIN'))" 2>/dev/null; then
  ok "plugin.json valid JSON"
else
  fail "plugin.json not valid JSON"
fi

# dependencies has taste-skill and andrej-karpathy-skills
for p in taste-skill andrej-karpathy-skills; do
  IN_DEPS=$(python3 -c "import json; d=json.load(open('$PLUGIN')); print('$p' in d.get('dependencies',[]))" 2>/dev/null || echo "False")
  if [[ "$IN_DEPS" == "True" ]]; then
    ok "plugin.json deps has $p"
  else
    fail "plugin.json deps missing $p"
  fi
done

# caveman NOT in dependencies
CAVEMAN_DEP=$(python3 -c "import json; d=json.load(open('$PLUGIN')); print('caveman' in d.get('dependencies',[]))" 2>/dev/null || echo "False")
if [[ "$CAVEMAN_DEP" == "False" ]]; then
  ok "caveman NOT in plugin deps (opt-in)"
else
  fail "caveman found in plugin deps (must be opt-in)"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
