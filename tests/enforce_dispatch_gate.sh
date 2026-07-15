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
#   C10: marker plan_file latch, mtime 이 start_ts 이전 이지만 GRACE(600s) 내 → exit 0
#   C11: 동일하되 GRACE 밖 → exit 2 (음경계 고정 — GRACE=∞ 회귀 방지)
#   C12: plan_file 지정인데 그 파일 삭제/부재 + 무관 전역 plan 만 fresh → 폴백 allow
#   C13: plan_file 가 상대경로 → stat miss → 폴백

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
  # 세션 marker 생성 (start_ts(=now-1h) → 이후 plan 파일은 mtime > this)
  local session_file="$repo/.git/plan-dev-session.json"
  START_TS=$(python3 -c "from datetime import datetime,timezone,timedelta; print((datetime.now(timezone.utc)-timedelta(hours=1)).strftime('%Y-%m-%dT%H:%M:%SZ'))")
  cat > "$session_file" <<JEOF
{
  "start_ref": "abc123",
  "base_branch": "main",
  "work_branch": "main",
  "start_ts": "$START_TS",
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
    sh -c "cd \"$REPO_DIR\" && \"$ENFORCE_HOOK\"" 2>/dev/null; echo $?)
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
  # start_ts(=now-1h) 이후 mtime 인 plan 파일 생성 (touch 로 현재 시간 = start_ts 이후)
  touch "$PLANS_DIR/my-plan.md"

  PAYLOAD=$(make_payload "Bash" "/path/to/dispatch-slice-pane.sh --slice=feat-x --mode=cmux" "sess-002")

  RC=$(echo "$PAYLOAD" | \
    DISPATCH_GATE_SESSION_FILE="$SESSION_FILE" \
    PLAN_MODE_PLANS_DIR="$PLANS_DIR" \
    sh -c "cd \"$REPO_DIR\" && \"$ENFORCE_HOOK\"" 2>/dev/null; echo $?)

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
    sh -c "cd \"$REPO_DIR\" && \"$ENFORCE_HOOK\"" 2>/dev/null; echo $?)

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
    sh -c "cd \"$REPO_DIR\" && \"$ENFORCE_HOOK\"" 2>/dev/null; echo $?)

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
    sh -c "cd \"$REPO_DIR\" && \"$ENFORCE_HOOK\"" 2>/dev/null; echo $?)

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
    sh -c "cd \"$REPO_DIR\" && \"$ENFORCE_HOOK\"" 2>/dev/null; echo $?)

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
    sh -c "cd \"$REPO_DIR\" && \"$ENFORCE_HOOK\"" 2>/dev/null; echo $?)

  [ "$RC" = "0" ] || fail "C7: exit code should be 0, got $RC"
  rm -rf "$TMP"
  echo "  C7 OK"
}

# ── C8: stale 24h(start_ts now-25h) + --slice + plan 없음 → exit 0 ─────

step C8 "stale marker(start_ts now-25h) + --slice + plan 없음 → exit 0"
{
  TMP=$(mktemp -d)
  REPO_DIR="$TMP/repo"
  mkdir -p "$REPO_DIR"
  git_init_main "$REPO_DIR"
  git -C "$REPO_DIR" config user.email "t@e.local"
  git -C "$REPO_DIR" config user.name "tester"
  git -C "$REPO_DIR" -c commit.gpgsign=false commit --allow-empty -q -m "init"
  SESSION_FILE="$REPO_DIR/.git/plan-dev-session.json"
  OLD_TS=$(python3 -c "from datetime import datetime,timezone,timedelta; print((datetime.now(timezone.utc)-timedelta(hours=25)).strftime('%Y-%m-%dT%H:%M:%SZ'))")
  cat > "$SESSION_FILE" <<JEOF
{"start_ts": "$OLD_TS"}
JEOF
  PLANS_DIR="$TMP/plans"
  mkdir -p "$PLANS_DIR"

  PAYLOAD=$(make_payload "Bash" "/path/to/dispatch-slice-pane.sh --slice=feat-x --mode=cmux" "sess-008")

  RC=$(echo "$PAYLOAD" | \
    DISPATCH_GATE_SESSION_FILE="$SESSION_FILE" \
    PLAN_MODE_PLANS_DIR="$PLANS_DIR" \
    sh -c "cd \"$REPO_DIR\" && \"$ENFORCE_HOOK\"" 2>/dev/null; echo $?)

  [ "$RC" = "0" ] || fail "C8: exit code should be 0, got $RC"
  rm -rf "$TMP"
  echo "  C8 OK"
}

# ── C9: skip-once marker-file — git-common-dir 에 cbp-skip-once-dispatch-gate → 1회 소비, 2번째는 block ──

step C9 "skip-once(git-common-dir) 1회 소비 — 2번째는 다시 block"
{
  TMP=$(setup_fixture)
  REPO_DIR="$TMP/repo"
  SESSION_FILE="$REPO_DIR/.git/plan-dev-session.json"
  PLANS_DIR="$TMP/plans"
  mkdir -p "$PLANS_DIR"
  touch "$REPO_DIR/.git/cbp-skip-once-dispatch-gate"

  PAYLOAD=$(make_payload "Bash" "/path/to/dispatch-slice-pane.sh --slice=feat-x --mode=cmux" "sess-009")

  RC1=$(echo "$PAYLOAD" | \
    DISPATCH_GATE_SESSION_FILE="$SESSION_FILE" \
    PLAN_MODE_PLANS_DIR="$PLANS_DIR" \
    sh -c "cd \"$REPO_DIR\" && \"$ENFORCE_HOOK\"" 2>/dev/null; echo $?)
  RC2=$(echo "$PAYLOAD" | \
    DISPATCH_GATE_SESSION_FILE="$SESSION_FILE" \
    PLAN_MODE_PLANS_DIR="$PLANS_DIR" \
    sh -c "cd \"$REPO_DIR\" && \"$ENFORCE_HOOK\"" 2>/dev/null; echo $?)

  [ "$RC1" = "0" ] || fail "C9: first call exit code should be 0, got $RC1"
  [ "$RC2" = "2" ] || fail "C9: second call exit code should be 2, got $RC2"
  rm -rf "$TMP"
  echo "  C9 OK"
}

# ── plan_file latch helpers ──────────────────────────────────────────

# marker 에 plan_file 필드 주입
inject_plan_file() {
  local session_file="$1" plan_file="$2"
  python3 -c "
import json
f = '$session_file'
d = json.load(open(f))
d['plan_file'] = '$plan_file'
open(f, 'w').write(json.dumps(d, indent=2) + '\n')
"
}

# 파일 mtime 을 start_ts 기준 offset(초) 으로 설정 (음수 = 과거)
set_mtime_offset() {
  local file="$1" start_ts="$2" offset_seconds="$3"
  START_TS="$start_ts" OFFSET="$offset_seconds" FILE="$file" python3 -c "
import os, datetime
st = datetime.datetime.fromisoformat(os.environ['START_TS'].replace('Z', '+00:00'))
target = st.timestamp() + float(os.environ['OFFSET'])
os.utime(os.environ['FILE'], (target, target))
"
}

# ── C10: plan_file latch, mtime start_ts 이전 + GRACE 내 → exit 0 ────

step C10 "plan_file latch, mtime 이 start_ts 이전이지만 GRACE(600s) 내 → exit 0"
{
  TMP=$(setup_fixture)
  REPO_DIR="$TMP/repo"
  SESSION_FILE="$REPO_DIR/.git/plan-dev-session.json"
  PLANS_DIR="$TMP/plans"
  mkdir -p "$PLANS_DIR"
  START_TS=$(python3 -c "import json; print(json.load(open('$SESSION_FILE'))['start_ts'])")

  LATCHED="$PLANS_DIR/latched-plan.md"
  touch "$LATCHED"
  set_mtime_offset "$LATCHED" "$START_TS" "-300"
  inject_plan_file "$SESSION_FILE" "$LATCHED"

  PAYLOAD=$(make_payload "Bash" "/path/to/dispatch-slice-pane.sh --slice=feat-x --mode=cmux" "sess-010")

  RC=$(echo "$PAYLOAD" | \
    DISPATCH_GATE_SESSION_FILE="$SESSION_FILE" \
    PLAN_MODE_PLANS_DIR="$PLANS_DIR" \
    sh -c "cd \"$REPO_DIR\" && \"$ENFORCE_HOOK\"" 2>/dev/null; echo $?)

  [ "$RC" = "0" ] || fail "C10: exit code should be 0, got $RC"
  rm -rf "$TMP"
  echo "  C10 OK"
}

# ── C11: 동일하되 GRACE 밖 → exit 2 ──────────────────────────────────

step C11 "plan_file latch, mtime 이 start_ts 이전 + GRACE 밖 → exit 2"
{
  TMP=$(setup_fixture)
  REPO_DIR="$TMP/repo"
  SESSION_FILE="$REPO_DIR/.git/plan-dev-session.json"
  PLANS_DIR="$TMP/plans"
  mkdir -p "$PLANS_DIR"
  START_TS=$(python3 -c "import json; print(json.load(open('$SESSION_FILE'))['start_ts'])")

  LATCHED="$PLANS_DIR/latched-plan.md"
  touch "$LATCHED"
  set_mtime_offset "$LATCHED" "$START_TS" "-700"
  inject_plan_file "$SESSION_FILE" "$LATCHED"

  PAYLOAD=$(make_payload "Bash" "/path/to/dispatch-slice-pane.sh --slice=feat-x --mode=cmux" "sess-011")

  RC=$(echo "$PAYLOAD" | \
    DISPATCH_GATE_SESSION_FILE="$SESSION_FILE" \
    PLAN_MODE_PLANS_DIR="$PLANS_DIR" \
    sh -c "cd \"$REPO_DIR\" && \"$ENFORCE_HOOK\"" 2>/dev/null; echo $?)

  [ "$RC" = "2" ] || fail "C11: exit code should be 2, got $RC"
  rm -rf "$TMP"
  echo "  C11 OK"
}

# ── C12: plan_file 삭제/부재 + 무관 전역 plan fresh → 폴백 allow ─────

step C12 "plan_file 삭제/부재 + 무관 전역 plan 만 fresh → 폴백 allow"
{
  TMP=$(setup_fixture)
  REPO_DIR="$TMP/repo"
  SESSION_FILE="$REPO_DIR/.git/plan-dev-session.json"
  PLANS_DIR="$TMP/plans"
  mkdir -p "$PLANS_DIR"

  # plan_file 필드는 존재하나 실제 파일 부재
  inject_plan_file "$SESSION_FILE" "$PLANS_DIR/deleted-plan.md"
  # 무관 전역 plan (fresh, mtime=now → start_ts(now-1h) 이후)
  touch "$PLANS_DIR/other-fresh-plan.md"

  PAYLOAD=$(make_payload "Bash" "/path/to/dispatch-slice-pane.sh --slice=feat-x --mode=cmux" "sess-012")

  RC=$(echo "$PAYLOAD" | \
    DISPATCH_GATE_SESSION_FILE="$SESSION_FILE" \
    PLAN_MODE_PLANS_DIR="$PLANS_DIR" \
    sh -c "cd \"$REPO_DIR\" && \"$ENFORCE_HOOK\"" 2>/dev/null; echo $?)

  [ "$RC" = "0" ] || fail "C12: exit code should be 0, got $RC"
  rm -rf "$TMP"
  echo "  C12 OK"
}

# ── C13: plan_file 상대경로 → stat miss → 폴백 ───────────────────────

step C13 "plan_file 가 상대경로 → stat miss → 폴백"
{
  TMP=$(setup_fixture)
  REPO_DIR="$TMP/repo"
  SESSION_FILE="$REPO_DIR/.git/plan-dev-session.json"
  PLANS_DIR="$TMP/plans"
  mkdir -p "$PLANS_DIR"

  inject_plan_file "$SESSION_FILE" "nonexistent-relative-plan.md"
  touch "$PLANS_DIR/other-fresh-plan.md"

  PAYLOAD=$(make_payload "Bash" "/path/to/dispatch-slice-pane.sh --slice=feat-x --mode=cmux" "sess-013")

  RC=$(echo "$PAYLOAD" | \
    DISPATCH_GATE_SESSION_FILE="$SESSION_FILE" \
    PLAN_MODE_PLANS_DIR="$PLANS_DIR" \
    sh -c "cd \"$REPO_DIR\" && \"$ENFORCE_HOOK\"" 2>/dev/null; echo $?)

  [ "$RC" = "0" ] || fail "C13: exit code should be 0, got $RC"
  rm -rf "$TMP"
  echo "  C13 OK"
}

echo ""
echo "PASS"
