#!/usr/bin/env bash
# finish-plan-dev.sh cmux cleanup 자동화 테스트 (S3)

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FINISH="$REPO/scripts/finish-plan-dev.sh"

step() { echo ""; echo "[$1] $2"; }
fail() { echo "FAIL: $1" >&2; exit 1; }

[ -x "$FINISH" ] || fail "finish-plan-dev.sh not executable: $FINISH"

# ── helpers ────────────────────────────────────────────────────────

git_init_main() {
  local dir="$1"
  git -c init.defaultBranch=main init "$dir" -q 2>/dev/null \
    || git init "$dir" -q
  if [ "$(git -C "$dir" symbolic-ref --short HEAD 2>/dev/null)" != "main" ]; then
    git -C "$dir" checkout -b main -q 2>/dev/null || true
  fi
}

setup_fixture() {
  local tmp
  tmp=$(mktemp -d)
  local repo="$tmp/repo"
  mkdir -p "$repo"
  git_init_main "$repo"
  git -C "$repo" config user.email "t@e.local"
  git -C "$repo" config user.name "tester"
  git -C "$repo" -c commit.gpgsign=false commit --allow-empty -q -m "init"
  local start_ref
  start_ref=$(git -C "$repo" rev-parse HEAD)
  cat > "$repo/.git/plan-dev-session.json" <<JEOF
{
  "start_ref": "$start_ref",
  "base_branch": "main",
  "work_branch": "main",
  "start_ts": "2026-05-28T00:00:00Z",
  "start_pid": 1,
  "auto_branch": false
}
JEOF
  git -C "$repo" -c commit.gpgsign=false commit --allow-empty -q -m "test commit"
  # commit-advisor gate 통과를 위해 marker 미리 touch
  touch "$repo/.git/plan-dev-commit-advised"
  echo "$tmp"
}

mock_cmux_pane() {
  local tmp="$1"
  local mock="$tmp/cmux-pane-mock.sh"
  local log="$tmp/cmux-pane.log"
  cat > "$mock" <<'MEOF'
#!/bin/bash
echo "called with: $*" >> "$LOG_FILE"
exit 0
MEOF
  # embed log path into mock
  sed -i.bak "s|\"\$LOG_FILE\"|\"$log\"|g" "$mock"
  rm -f "$mock.bak"
  chmod +x "$mock"
  echo "$mock:$log"
}

# ── Case 1: CMUX_WORKSPACE_ID set + 우회 없음 → cleanup 호출됨 ────

step 1 "CMUX_WORKSPACE_ID set + bypass unset → mock cleanup called"
{
  TMP=$(setup_fixture)
  REPO_DIR="$TMP/repo"

  MOCK_INFO=$(mock_cmux_pane "$TMP")
  MOCK="${MOCK_INFO%%:*}"
  LOG="${MOCK_INFO##*:}"

  OUT=$(cd "$REPO_DIR" && \
    CMUX_WORKSPACE_ID="test-ws" \
    CMUX_PANE_BIN="$MOCK" \
    GIT_PUSH_CMD="true" \
    PLAN_DEV_SESSION_BIN=/bin/false \
    "$FINISH" 2>/dev/null)
  RC=$?

  [ "$RC" = "0" ] || fail "Case 1: exit code should be 0, got $RC (stdout: $OUT)"
  [ -f "$LOG" ] || fail "Case 1: cmux-pane mock log not found — cleanup was not called"
  grep -q "cleanup" "$LOG" || fail "Case 1: 'cleanup' not in log. log: $(cat "$LOG")"

  rm -rf "$TMP"
  echo "  Case 1 OK"
}

# ── Case 2: CMUX_WORKSPACE_ID unset → cleanup 호출 안 됨 ─────────

step 2 "CMUX_WORKSPACE_ID unset → cleanup NOT called"
{
  TMP=$(setup_fixture)
  REPO_DIR="$TMP/repo"

  MOCK_INFO=$(mock_cmux_pane "$TMP")
  MOCK="${MOCK_INFO%%:*}"
  LOG="${MOCK_INFO##*:}"

  # unset CMUX_WORKSPACE_ID (ensure it's not inherited)
  OUT=$(cd "$REPO_DIR" && \
    env -u CMUX_WORKSPACE_ID \
    CMUX_PANE_BIN="$MOCK" \
    GIT_PUSH_CMD="true" \
    PLAN_DEV_SESSION_BIN=/bin/false \
    "$FINISH" 2>/dev/null)
  RC=$?

  [ "$RC" = "0" ] || fail "Case 2: exit code should be 0, got $RC"
  [ ! -f "$LOG" ] || fail "Case 2: log should NOT exist when CMUX_WORKSPACE_ID unset. log: $(cat "$LOG")"

  rm -rf "$TMP"
  echo "  Case 2 OK"
}

# ── Case 3: SKIP_PLAN_DEV_CMUX_CLEANUP=1 → 호출 안 됨 ──────────

step 3 "SKIP_PLAN_DEV_CMUX_CLEANUP=1 → cleanup NOT called"
{
  TMP=$(setup_fixture)
  REPO_DIR="$TMP/repo"

  MOCK_INFO=$(mock_cmux_pane "$TMP")
  MOCK="${MOCK_INFO%%:*}"
  LOG="${MOCK_INFO##*:}"

  OUT=$(cd "$REPO_DIR" && \
    CMUX_WORKSPACE_ID="test-ws" \
    SKIP_PLAN_DEV_CMUX_CLEANUP=1 \
    CMUX_PANE_BIN="$MOCK" \
    GIT_PUSH_CMD="true" \
    PLAN_DEV_SESSION_BIN=/bin/false \
    "$FINISH" 2>/dev/null)
  RC=$?

  [ "$RC" = "0" ] || fail "Case 3: exit code should be 0, got $RC"
  [ ! -f "$LOG" ] || fail "Case 3: log should NOT exist when SKIP_PLAN_DEV_CMUX_CLEANUP=1. log: $(cat "$LOG")"

  rm -rf "$TMP"
  echo "  Case 3 OK"
}

# ── Case 4: DISABLE_PLAN_DEV_CMUX_CLEANUP=1 → 호출 안 됨 ────────

step 4 "DISABLE_PLAN_DEV_CMUX_CLEANUP=1 → cleanup NOT called"
{
  TMP=$(setup_fixture)
  REPO_DIR="$TMP/repo"

  MOCK_INFO=$(mock_cmux_pane "$TMP")
  MOCK="${MOCK_INFO%%:*}"
  LOG="${MOCK_INFO##*:}"

  OUT=$(cd "$REPO_DIR" && \
    CMUX_WORKSPACE_ID="test-ws" \
    DISABLE_PLAN_DEV_CMUX_CLEANUP=1 \
    CMUX_PANE_BIN="$MOCK" \
    GIT_PUSH_CMD="true" \
    PLAN_DEV_SESSION_BIN=/bin/false \
    "$FINISH" 2>/dev/null)
  RC=$?

  [ "$RC" = "0" ] || fail "Case 4: exit code should be 0, got $RC"
  [ ! -f "$LOG" ] || fail "Case 4: log should NOT exist when DISABLE_PLAN_DEV_CMUX_CLEANUP=1. log: $(cat "$LOG")"

  rm -rf "$TMP"
  echo "  Case 4 OK"
}

# ── Case 5: CMUX_PANE_BIN 부재 → graceful skip + push 성공 ───────

step 5 "CMUX_PANE_BIN missing → graceful skip + push success"
{
  TMP=$(setup_fixture)
  REPO_DIR="$TMP/repo"

  OUT=$(cd "$REPO_DIR" && \
    CMUX_WORKSPACE_ID="test-ws" \
    CMUX_PANE_BIN="$TMP/nonexistent-bin.sh" \
    GIT_PUSH_CMD="true" \
    PLAN_DEV_SESSION_BIN=/bin/false \
    "$FINISH" 2>/dev/null)
  RC=$?

  [ "$RC" = "0" ] || fail "Case 5: exit code should be 0, got $RC (stdout: $OUT)"
  echo "$OUT" | grep -q "pushed" || fail "Case 5: stdout should contain 'pushed', got: $OUT"

  rm -rf "$TMP"
  echo "  Case 5 OK"
}

# ── Case 6: push 실패 → cleanup 호출 안 됨 ───────────────────────

step 6 "push failure → cleanup NOT called"
{
  TMP=$(setup_fixture)
  REPO_DIR="$TMP/repo"

  MOCK_INFO=$(mock_cmux_pane "$TMP")
  MOCK="${MOCK_INFO%%:*}"
  LOG="${MOCK_INFO##*:}"

  set +e
  OUT=$(cd "$REPO_DIR" && \
    CMUX_WORKSPACE_ID="test-ws" \
    CMUX_PANE_BIN="$MOCK" \
    GIT_PUSH_CMD="false" \
    PLAN_DEV_SESSION_BIN=/bin/false \
    "$FINISH" 2>&1 >/dev/null)
  RC=$?
  set -e

  [ "$RC" = "2" ] || fail "Case 6: exit code should be 2, got $RC"
  [ ! -f "$LOG" ] || fail "Case 6: log should NOT exist on push failure. log: $(cat "$LOG")"

  rm -rf "$TMP"
  echo "  Case 6 OK"
}

echo ""
echo "PASS"
