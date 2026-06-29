#!/usr/bin/env bash
# tests/enforce_dispatch_gate.sh
# S1 — enforce-dispatch-gate.sh 재설계 테스트.
# 결함1: dispatch-slice-pane.sh 만 있으면 오탐 (--slice 없으면 관심 없음)
# 결함2: approved marker 의존 제거 → plan-file mtime 기반 판정으로 교체
#
# 케이스:
#   C1: 세션활성 + Bash dispatch-slice-pane.sh --slice=x --mode=cmux + plan 파일 없음 → exit 2
#   C2: 동일 + start_ts 이후 plan 파일 존재 → exit 0 (plan mode 거침)
#   C3: command=grep dispatch-slice-pane.sh scripts/ (--slice 없음) → exit 0 (결함1 회귀가드)
#   C4: command=echo hi → exit 0 (dispatch 무관)
#   C5: 세션 marker 없음 → exit 0 (비-plan-dev)
#   C6: permission_mode=bypassPermissions + --slice + plan 없음 → exit 0 (dispatch 자식 우회)
#   C7: SKIP_DISPATCH_GATE=1 + 차단 조건 → exit 0 (1회 우회)

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENFORCE_HOOK="$REPO/hooks/enforce-dispatch-gate.sh"

step() { echo ""; echo "[$1] $2"; }
fail() { echo "FAIL: $1" >&2; exit 1; }

[ -x "$ENFORCE_HOOK" ] || fail "enforce-dispatch-gate.sh not executable: $ENFORCE_HOOK"

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
  # 세션 marker 생성 (start_ts: 2026-01-01 → 이후 plan 파일은 mtime > this)
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

# ── C1: 세션활성 + dispatch --slice + plan 파일 없음 → exit 2 ────────

step C1 "세션활성 + Bash dispatch-slice-pane.sh --slice=x + plan 파일 없음 → exit 2"
{
  TMP=$(setup_fixture)
  REPO_DIR="$TMP/repo"
  SESSION_FILE="$REPO_DIR/.git/plan-dev-session.json"
  PLANS_DIR="$TMP/plans"
  mkdir -p "$PLANS_DIR"
  # plan 파일 없음

  PAYLOAD=$(make_payload "Bash" "/path/to/dispatch-slice-pane.sh --slice=feat-x --mode=cmux" "sess-001")

  set +e
  RC=$(echo "$PAYLOAD" | \
    DISPATCH_GATE_SESSION_FILE="$SESSION_FILE" \
    PLAN_MODE_PLANS_DIR="$PLANS_DIR" \
    "$ENFORCE_HOOK" 2>/dev/null; echo $?)
  set -e

  [ "$RC" = "2" ] || fail "C1: exit code should be 2, got $RC"
  rm -rf "$TMP"
  echo "  C1 OK"
}

# ── C2: 동일 + start_ts 이후 plan 파일 존재 → exit 0 ────────────────

step C2 "세션활성 + --slice + start_ts 이후 plan 파일 존재 → exit 0"
{
  TMP=$(setup_fixture)
  REPO_DIR="$TMP/repo"
  SESSION_FILE="$REPO_DIR/.git/plan-dev-session.json"
  PLANS_DIR="$TMP/plans"
  mkdir -p "$PLANS_DIR"
  # start_ts 이후 mtime 인 plan 파일 생성 (touch 로 현재 시간 = 2026-01-01보다 최신)
  touch "$PLANS_DIR/my-plan.md"

  PAYLOAD=$(make_payload "Bash" "/path/to/dispatch-slice-pane.sh --slice=feat-x --mode=cmux" "sess-002")

  RC=$(echo "$PAYLOAD" | \
    DISPATCH_GATE_SESSION_FILE="$SESSION_FILE" \
    PLAN_MODE_PLANS_DIR="$PLANS_DIR" \
    "$ENFORCE_HOOK" 2>/dev/null; echo $?)

  [ "$RC" = "0" ] || fail "C2: exit code should be 0, got $RC"
  rm -rf "$TMP"
  echo "  C2 OK"
}

# ── C3: --slice 없는 명령 → exit 0 (결함1 회귀가드) ─────────────────

step C3 "command=grep dispatch-slice-pane.sh scripts/ (--slice 없음) → exit 0"
{
  TMP=$(setup_fixture)
  REPO_DIR="$TMP/repo"
  SESSION_FILE="$REPO_DIR/.git/plan-dev-session.json"
  PLANS_DIR="$TMP/plans"
  mkdir -p "$PLANS_DIR"
  # plan 없음이어도 exit 0 이어야 함 (매처 미일치)

  PAYLOAD=$(make_payload "Bash" "grep dispatch-slice-pane.sh scripts/" "sess-003")

  RC=$(echo "$PAYLOAD" | \
    DISPATCH_GATE_SESSION_FILE="$SESSION_FILE" \
    PLAN_MODE_PLANS_DIR="$PLANS_DIR" \
    "$ENFORCE_HOOK" 2>/dev/null; echo $?)

  [ "$RC" = "0" ] || fail "C3: exit code should be 0, got $RC"
  rm -rf "$TMP"
  echo "  C3 OK"
}

# ── C4: dispatch 무관 명령 → exit 0 ─────────────────────────────────

step C4 "command=echo hi → exit 0 (dispatch 무관)"
{
  TMP=$(setup_fixture)
  REPO_DIR="$TMP/repo"
  SESSION_FILE="$REPO_DIR/.git/plan-dev-session.json"
  PLANS_DIR="$TMP/plans"
  mkdir -p "$PLANS_DIR"

  PAYLOAD=$(make_payload "Bash" "echo hi" "sess-004")

  RC=$(echo "$PAYLOAD" | \
    DISPATCH_GATE_SESSION_FILE="$SESSION_FILE" \
    PLAN_MODE_PLANS_DIR="$PLANS_DIR" \
    "$ENFORCE_HOOK" 2>/dev/null; echo $?)

  [ "$RC" = "0" ] || fail "C4: exit code should be 0, got $RC"
  rm -rf "$TMP"
  echo "  C4 OK"
}

# ── C5: 세션 marker 없음 → exit 0 ───────────────────────────────────

step C5 "세션 marker 없음 → exit 0 (비-plan-dev)"
{
  TMP=$(mktemp -d)
  REPO_DIR="$TMP/repo"
  mkdir -p "$REPO_DIR"
  git_init_main "$REPO_DIR"
  git -C "$REPO_DIR" config user.email "t@e.local"
  git -C "$REPO_DIR" config user.name "tester"
  git -C "$REPO_DIR" -c commit.gpgsign=false commit --allow-empty -q -m "init"
  # 세션 marker 생성 안 함
  SESSION_FILE="$REPO_DIR/.git/plan-dev-session.json"
  PLANS_DIR="$TMP/plans"
  mkdir -p "$PLANS_DIR"

  PAYLOAD=$(make_payload "Bash" "/path/to/dispatch-slice-pane.sh --slice=feat-x --mode=cmux" "sess-005")

  RC=$(echo "$PAYLOAD" | \
    DISPATCH_GATE_SESSION_FILE="$SESSION_FILE" \
    PLAN_MODE_PLANS_DIR="$PLANS_DIR" \
    "$ENFORCE_HOOK" 2>/dev/null; echo $?)

  [ "$RC" = "0" ] || fail "C5: exit code should be 0, got $RC"
  rm -rf "$TMP"
  echo "  C5 OK"
}

# ── C6: bypassPermissions + --slice + plan 없음 → exit 0 ─────────────

step C6 "permission_mode=bypassPermissions + --slice + plan 없음 → exit 0 (dispatch 자식 우회)"
{
  TMP=$(setup_fixture)
  REPO_DIR="$TMP/repo"
  SESSION_FILE="$REPO_DIR/.git/plan-dev-session.json"
  PLANS_DIR="$TMP/plans"
  mkdir -p "$PLANS_DIR"
  # plan 없음이어도 bypassPermissions 면 pass

  PAYLOAD=$(make_payload "Bash" "/path/to/dispatch-slice-pane.sh --slice=feat-x --mode=cmux" "sess-006" "bypassPermissions")

  RC=$(echo "$PAYLOAD" | \
    DISPATCH_GATE_SESSION_FILE="$SESSION_FILE" \
    PLAN_MODE_PLANS_DIR="$PLANS_DIR" \
    "$ENFORCE_HOOK" 2>/dev/null; echo $?)

  [ "$RC" = "0" ] || fail "C6: exit code should be 0, got $RC"
  rm -rf "$TMP"
  echo "  C6 OK"
}

# ── C7: SKIP_DISPATCH_GATE=1 + 차단 조건 → exit 0 ───────────────────

step C7 "SKIP_DISPATCH_GATE=1 + 차단 조건 → exit 0 (1회 우회)"
{
  TMP=$(setup_fixture)
  REPO_DIR="$TMP/repo"
  SESSION_FILE="$REPO_DIR/.git/plan-dev-session.json"
  PLANS_DIR="$TMP/plans"
  mkdir -p "$PLANS_DIR"
  # plan 없음 → 차단 조건이지만 SKIP 으로 우회

  PAYLOAD=$(make_payload "Bash" "/path/to/dispatch-slice-pane.sh --slice=feat-x --mode=cmux" "sess-007")

  RC=$(echo "$PAYLOAD" | \
    SKIP_DISPATCH_GATE=1 \
    DISPATCH_GATE_SESSION_FILE="$SESSION_FILE" \
    PLAN_MODE_PLANS_DIR="$PLANS_DIR" \
    "$ENFORCE_HOOK" 2>/dev/null; echo $?)

  [ "$RC" = "0" ] || fail "C7: exit code should be 0, got $RC"
  rm -rf "$TMP"
  echo "  C7 OK"
}

echo ""
echo "PASS"
