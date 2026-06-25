#!/usr/bin/env bash
# tests/enforce_dispatch_gate.sh
# S2 — dispatch-approval-gate 테스트.
# 더미 git repo fixture + JSON payload stdin 파이프로 두 hook 검증.
#
# 케이스:
#   C1: 세션 marker 활성 + approved marker 부재 + dispatch 명령 → exit 2
#   C2: approved marker 존재(session_id 일치) → exit 0
#   C3: dispatch 무관 명령(echo hi) → exit 0
#   C4: SKIP_DISPATCH_GATE=1 + 차단 조건 → exit 0
#   C5: 세션 marker 없음 → exit 0
#   C6: mark-plan-approved.sh 에 ExitPlanMode payload 파이프 → approved marker 생성 확인

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENFORCE_HOOK="$REPO/hooks/enforce-dispatch-gate.sh"
MARK_HOOK="$REPO/hooks/mark-plan-approved.sh"

step() { echo ""; echo "[$1] $2"; }
fail() { echo "FAIL: $1" >&2; exit 1; }

[ -x "$ENFORCE_HOOK" ] || fail "enforce-dispatch-gate.sh not executable: $ENFORCE_HOOK"
[ -x "$MARK_HOOK" ]   || fail "mark-plan-approved.sh not executable: $MARK_HOOK"

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
  # 세션 marker 생성
  local session_file="$repo/.git/plan-dev-session.json"
  cat > "$session_file" <<JEOF
{
  "start_ref": "abc123",
  "base_branch": "main",
  "work_branch": "main",
  "start_ts": "2026-01-01T00:00:00Z",
  "start_pid": 1,
  "auto_branch": false
}
JEOF
  echo "$tmp"
}

make_payload() {
  local tool_name="$1"
  local command="${2:-}"
  local session_id="${3:-test-session-id}"
  local permission_mode="${4:-default}"
  python3 -c "
import json, sys
d = {
    'tool_name': '$tool_name',
    'tool_input': {'command': '$command'},
    'session_id': '$session_id',
    'permission_mode': '$permission_mode',
}
print(json.dumps(d))
"
}

# ── C1: 세션 marker 활성 + approved marker 부재 + dispatch 명령 → exit 2 ─

step C1 "세션 marker 활성 + approved marker 부재 + dispatch 명령 → exit 2"
{
  TMP=$(setup_fixture)
  REPO_DIR="$TMP/repo"
  SESSION_FILE="$REPO_DIR/.git/plan-dev-session.json"
  APPROVED_MARKER="$REPO_DIR/.git/plan-dev-plan-approved"

  PAYLOAD=$(make_payload "Bash" "bash scripts/dispatch-slice-pane.sh --mode=cmux slug" "sess-001")

  set +e
  RC=$(echo "$PAYLOAD" | \
    DISPATCH_GATE_SESSION_FILE="$SESSION_FILE" \
    PLAN_APPROVED_MARKER="$APPROVED_MARKER" \
    "$ENFORCE_HOOK" 2>/dev/null; echo $?)
  set -e

  [ "$RC" = "2" ] || fail "C1: exit code should be 2, got $RC"
  rm -rf "$TMP"
  echo "  C1 OK"
}

# ── C2: approved marker 존재(session_id 일치) → exit 0 ─────────────

step C2 "approved marker 존재(session_id 일치) → exit 0"
{
  TMP=$(setup_fixture)
  REPO_DIR="$TMP/repo"
  SESSION_FILE="$REPO_DIR/.git/plan-dev-session.json"
  APPROVED_MARKER="$REPO_DIR/.git/plan-dev-plan-approved"

  SESSION_ID="sess-002"
  echo "$SESSION_ID" > "$APPROVED_MARKER"

  PAYLOAD=$(make_payload "Bash" "bash scripts/dispatch-slice-pane.sh --mode=cmux slug" "$SESSION_ID")

  RC=$(echo "$PAYLOAD" | \
    DISPATCH_GATE_SESSION_FILE="$SESSION_FILE" \
    PLAN_APPROVED_MARKER="$APPROVED_MARKER" \
    "$ENFORCE_HOOK" 2>/dev/null; echo $?)

  [ "$RC" = "0" ] || fail "C2: exit code should be 0, got $RC"
  rm -rf "$TMP"
  echo "  C2 OK"
}

# ── C3: dispatch 무관 명령(echo hi) → exit 0 ───────────────────────

step C3 "dispatch 무관 명령(echo hi) → exit 0"
{
  TMP=$(setup_fixture)
  REPO_DIR="$TMP/repo"
  SESSION_FILE="$REPO_DIR/.git/plan-dev-session.json"
  APPROVED_MARKER="$REPO_DIR/.git/plan-dev-plan-approved"

  PAYLOAD=$(make_payload "Bash" "echo hi" "sess-003")

  RC=$(echo "$PAYLOAD" | \
    DISPATCH_GATE_SESSION_FILE="$SESSION_FILE" \
    PLAN_APPROVED_MARKER="$APPROVED_MARKER" \
    "$ENFORCE_HOOK" 2>/dev/null; echo $?)

  [ "$RC" = "0" ] || fail "C3: exit code should be 0, got $RC"
  rm -rf "$TMP"
  echo "  C3 OK"
}

# ── C4: SKIP_DISPATCH_GATE=1 + 차단 조건 → exit 0 ──────────────────

step C4 "SKIP_DISPATCH_GATE=1 + 차단 조건 → exit 0 (1회 우회)"
{
  TMP=$(setup_fixture)
  REPO_DIR="$TMP/repo"
  SESSION_FILE="$REPO_DIR/.git/plan-dev-session.json"
  APPROVED_MARKER="$REPO_DIR/.git/plan-dev-plan-approved"
  # approved marker 없음 → 원래 차단 조건

  PAYLOAD=$(make_payload "Bash" "bash scripts/dispatch-slice-pane.sh --mode=cmux slug" "sess-004")

  RC=$(echo "$PAYLOAD" | \
    SKIP_DISPATCH_GATE=1 \
    DISPATCH_GATE_SESSION_FILE="$SESSION_FILE" \
    PLAN_APPROVED_MARKER="$APPROVED_MARKER" \
    "$ENFORCE_HOOK" 2>/dev/null; echo $?)

  [ "$RC" = "0" ] || fail "C4: exit code should be 0, got $RC"
  rm -rf "$TMP"
  echo "  C4 OK"
}

# ── C5: 세션 marker 없음 → exit 0 ──────────────────────────────────

step C5 "세션 marker 없음 → exit 0 (비-plan-dev)"
{
  TMP=$(mktemp -d)
  REPO_DIR="$TMP/repo"
  mkdir -p "$REPO_DIR/.git"
  git_init_main "$REPO_DIR"
  git -C "$REPO_DIR" config user.email "t@e.local"
  git -C "$REPO_DIR" config user.name "tester"
  git -C "$REPO_DIR" -c commit.gpgsign=false commit --allow-empty -q -m "init"
  # 세션 marker 생성 안 함
  SESSION_FILE="$REPO_DIR/.git/plan-dev-session.json"
  APPROVED_MARKER="$REPO_DIR/.git/plan-dev-plan-approved"

  PAYLOAD=$(make_payload "Bash" "bash scripts/dispatch-slice-pane.sh --mode=cmux slug" "sess-005")

  RC=$(echo "$PAYLOAD" | \
    DISPATCH_GATE_SESSION_FILE="$SESSION_FILE" \
    PLAN_APPROVED_MARKER="$APPROVED_MARKER" \
    "$ENFORCE_HOOK" 2>/dev/null; echo $?)

  [ "$RC" = "0" ] || fail "C5: exit code should be 0, got $RC"
  rm -rf "$TMP"
  echo "  C5 OK"
}

# ── C6: mark-plan-approved.sh → ExitPlanMode payload → approved marker 생성 ─

step C6 "mark-plan-approved.sh: ExitPlanMode payload → approved marker 생성 + 내용 일치"
{
  TMP=$(setup_fixture)
  REPO_DIR="$TMP/repo"
  SESSION_FILE="$REPO_DIR/.git/plan-dev-session.json"
  APPROVED_MARKER="$REPO_DIR/.git/plan-dev-plan-approved"

  SESSION_ID="sess-mark-006"
  PAYLOAD=$(python3 -c "
import json
d = {
    'tool_name': 'ExitPlanMode',
    'tool_input': {'plan': 'some plan text'},
    'session_id': '$SESSION_ID',
    'permission_mode': 'default',
}
print(json.dumps(d))
")

  echo "$PAYLOAD" | \
    PLAN_APPROVED_MARKER="$APPROVED_MARKER" \
    DISPATCH_GATE_SESSION_FILE="$SESSION_FILE" \
    "$MARK_HOOK" 2>/dev/null

  [ -f "$APPROVED_MARKER" ] || fail "C6: approved marker not created"
  CONTENT=$(cat "$APPROVED_MARKER")
  [ "$CONTENT" = "$SESSION_ID" ] || fail "C6: marker content mismatch. expected='$SESSION_ID', got='$CONTENT'"
  rm -rf "$TMP"
  echo "  C6 OK"
}

echo ""
echo "PASS"
