#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PASS=0; FAIL=0
ok() { echo "  ok: $1"; PASS=$((PASS+1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

# 1. core ≤200 lines
lines=$(wc -l < "$REPO_ROOT/commands/plan-dev.md")
[ "$lines" -le 200 ] && ok "core ≤200 lines ($lines)" || fail "core is $lines lines (>200)"

# 2. 3 reference files exist
for f in \
  "$REPO_ROOT/commands/plan-dev/cmux-dispatch.md" \
  "$REPO_ROOT/commands/plan-dev/workflow-integration.md" \
  "$REPO_ROOT/commands/plan-dev/antipatterns.md"; do
  [ -f "$f" ] && ok "exists: $(basename $f)" || fail "missing: $f"
done

# 3. core links to each reference
for ref in cmux-dispatch workflow-integration antipatterns; do
  grep -q "plan-dev/$ref" "$REPO_ROOT/commands/plan-dev.md" \
    && ok "core links $ref" || fail "core missing link to plan-dev/$ref"
done

# 4. key keywords present across core+refs combined
COMBINED=$(cat \
  "$REPO_ROOT/commands/plan-dev.md" \
  "$REPO_ROOT/commands/plan-dev/cmux-dispatch.md" \
  "$REPO_ROOT/commands/plan-dev/workflow-integration.md" \
  "$REPO_ROOT/commands/plan-dev/antipatterns.md" \
  2>/dev/null || true)
for kw in "Phase 0" "Phase 1" "Phase 2" "Phase 3" "Phase 4" "Phase 5" "Phase 6" \
          "Goal Statement" "machine-checks" "Slice File Map" "AskUserQuestion"; do
  echo "$COMBINED" | grep -q "$kw" \
    && ok "keyword: $kw" || fail "keyword missing: $kw"
done

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
