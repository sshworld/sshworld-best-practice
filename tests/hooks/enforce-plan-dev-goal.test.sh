#!/usr/bin/env bash
set -e

HOOK="$(cd "$(dirname "$0")/../.." && pwd)/.claude/hooks/enforce-plan-dev-goal.sh"
TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

# Scenario 1: marker 없음 → exit 0
PLAN_DEV_GOAL_SESSION_FILE="$TMP/no-such.json" "$HOOK" < /dev/null
echo "1: marker 없음 → exit 0 ✓"

# Scenario 2: marker 있고 plan 없음 → exit 0
echo '{}' > "$TMP/session.json"
PLAN_DEV_GOAL_SESSION_FILE="$TMP/session.json" PLAN_DEV_GOAL_PLAN_PATH="$TMP/no-such.md" "$HOOK" < /dev/null
echo "2: plan 없음 → exit 0 ✓"

# Scenario 3: machine-checks 전부 PASS → exit 0
cat > "$TMP/plan.md" <<EOF
## Goal Statement
<!-- machine-checks -->
\`\`\`bash
true
[ 1 -eq 1 ]
\`\`\`
<!-- /machine-checks -->
EOF
PLAN_DEV_GOAL_SESSION_FILE="$TMP/session.json" PLAN_DEV_GOAL_PLAN_PATH="$TMP/plan.md" "$HOOK" < /dev/null
echo "3: 전부 PASS → exit 0 ✓"

# Scenario 4: 하나 fail → exit 2 + stderr 매치
cat > "$TMP/plan.md" <<EOF
## Goal Statement
<!-- machine-checks -->
\`\`\`bash
true
false
\`\`\`
<!-- /machine-checks -->
EOF
out=$(PLAN_DEV_GOAL_SESSION_FILE="$TMP/session.json" PLAN_DEV_GOAL_PLAN_PATH="$TMP/plan.md" "$HOOK" < /dev/null 2>&1 || echo "EXIT=$?")
echo "$out" | grep -q "EXIT=2"
echo "$out" | grep -q "FAIL"
echo "4: 한 줄 fail → exit 2 + stderr FAIL ✓"

# Scenario 5: SKIP env → exit 0
SKIP_PLAN_DEV_GOAL=1 "$HOOK" < /dev/null
echo "5: SKIP env → exit 0 ✓"

# Scenario 6: DISABLE env → exit 0
DISABLE_PLAN_DEV_GOAL_HOOK=1 "$HOOK" < /dev/null
echo "6: DISABLE env → exit 0 ✓"

echo "✅ all 6 scenarios passed"
