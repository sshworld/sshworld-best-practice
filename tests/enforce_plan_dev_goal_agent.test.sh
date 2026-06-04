#!/usr/bin/env bash
set -e

HOOK="$(cd "$(dirname "$0")/.." && pwd)/.claude/hooks/enforce-plan-dev-goal.sh"
TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

MOCK_BIN="$TMP/mock_bin"
mkdir -p "$MOCK_BIN"

# ── Fixture: mock git repo (no active worktrees) ──────────────────────
REPO="$TMP/repo"
mkdir -p "$REPO"
git -C "$REPO" init -q
git -C "$REPO" config user.email "test@test.com"
git -C "$REPO" config user.name "test"
git -C "$REPO" commit --allow-empty -q -m "init"
START_REF=$(git -C "$REPO" rev-parse HEAD)

# ── Fixture: session file with start_ref ─────────────────────────────
SESSION="$TMP/session.json"
printf '{"start_ref": "%s"}' "$START_REF" > "$SESSION"

# ── Fixture: plan with machine-checks PASS + Semantic goal ───────────
PLAN="$TMP/plan.md"
cat > "$PLAN" <<'PLANEOF'
## Goal Statement
<!-- machine-checks -->
```bash
true
```
<!-- /machine-checks -->

**Semantic goal**: Agent layer added to hook.
PLANEOF

# ── Helper to build PATH without any real claude ─────────────────────
no_claude_path() {
  local clean="$1"
  while IFS= read -r dir; do
    [[ -z "$dir" ]] && continue
    [[ -f "$dir/claude" ]] && continue  # skip any dir that has a claude binary
    clean="$clean:$dir"
  done <<< "$(echo "$PATH" | tr ':' '\n')"
  echo "$clean"
}

# ── Scenario 1: bash PASS + agent PASS → exit 0 ──────────────────────
cat > "$MOCK_BIN/claude" <<'EOF'
#!/bin/bash
echo '{"pass": true}'
EOF
chmod +x "$MOCK_BIN/claude"

PATH="$MOCK_BIN:$PATH" \
  CLAUDE_PROJECT_DIR="$REPO" \
  PLAN_DEV_GOAL_SESSION_FILE="$SESSION" \
  PLAN_DEV_GOAL_PLAN_PATH="$PLAN" \
  "$HOOK" < /dev/null
echo "1: bash PASS + agent PASS → exit 0 ✓"

# ── Scenario 2: bash PASS + agent FAIL → exit 2 + missing item ───────
cat > "$MOCK_BIN/claude" <<'EOF'
#!/bin/bash
echo '{"pass": false, "missing": ["agent layer not implemented"]}'
EOF
chmod +x "$MOCK_BIN/claude"

out=$(PATH="$MOCK_BIN:$PATH" \
  CLAUDE_PROJECT_DIR="$REPO" \
  PLAN_DEV_GOAL_SESSION_FILE="$SESSION" \
  PLAN_DEV_GOAL_PLAN_PATH="$PLAN" \
  "$HOOK" < /dev/null 2>&1 || echo "EXIT=$?")
echo "$out" | grep -q "EXIT=2"
echo "$out" | grep -q "agent layer not implemented"
echo "2: bash PASS + agent FAIL → exit 2 + missing item ✓"

# ── Scenario 3: SKIP_GOAL_AGENT=1 → bash only (exit 0) ───────────────
cat > "$MOCK_BIN/claude" <<'EOF'
#!/bin/bash
echo '{"pass": false, "missing": ["must not be called"]}'
EOF
chmod +x "$MOCK_BIN/claude"

PATH="$MOCK_BIN:$PATH" \
  SKIP_GOAL_AGENT=1 \
  CLAUDE_PROJECT_DIR="$REPO" \
  PLAN_DEV_GOAL_SESSION_FILE="$SESSION" \
  PLAN_DEV_GOAL_PLAN_PATH="$PLAN" \
  "$HOOK" < /dev/null
echo "3: SKIP_GOAL_AGENT → exit 0 ✓"

# ── Scenario 4: DISABLE_GOAL_AGENT=1 → bash only (exit 0) ────────────
PATH="$MOCK_BIN:$PATH" \
  DISABLE_GOAL_AGENT=1 \
  CLAUDE_PROJECT_DIR="$REPO" \
  PLAN_DEV_GOAL_SESSION_FILE="$SESSION" \
  PLAN_DEV_GOAL_PLAN_PATH="$PLAN" \
  "$HOOK" < /dev/null
echo "4: DISABLE_GOAL_AGENT → exit 0 ✓"

# ── Scenario 5: claude binary unavailable → graceful exit 0 ──────────
NO_CLAUDE_PATH=$(no_claude_path "$TMP/empty_bin")
mkdir -p "$TMP/empty_bin"

PATH="$NO_CLAUDE_PATH" \
  CLAUDE_PROJECT_DIR="$REPO" \
  PLAN_DEV_GOAL_SESSION_FILE="$SESSION" \
  PLAN_DEV_GOAL_PLAN_PATH="$PLAN" \
  "$HOOK" < /dev/null
echo "5: claude unavailable → exit 0 ✓"

# ── Scenario 6: agent parse-fail (non-JSON) → bash-only PASS (exit 0) ─
cat > "$MOCK_BIN/claude" <<'EOF'
#!/bin/bash
echo 'This is definitely not JSON at all!'
EOF
chmod +x "$MOCK_BIN/claude"

PATH="$MOCK_BIN:$PATH" \
  CLAUDE_PROJECT_DIR="$REPO" \
  PLAN_DEV_GOAL_SESSION_FILE="$SESSION" \
  PLAN_DEV_GOAL_PLAN_PATH="$PLAN" \
  "$HOOK" < /dev/null
echo "6: agent parse-fail → bash-only PASS exit 0 ✓"

echo "✅ all 6 scenarios passed"
