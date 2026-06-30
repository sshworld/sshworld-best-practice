#!/usr/bin/env bash
# S2 — cmux-pane.sh reap-orphans 를 plan-dev 흐름에 자동 연결 검증.
#
# 케이스:
#   W1: plan-dev-session.sh start (cmux 환경 mock, CMUX_WORKSPACE_ID set) → 로그에 reap-orphans 기록됨.
#   W2: SKIP_CMUX_REAP=1 + start → reap-orphans 미호출.
#   W3: 비-cmux (CMUX_WORKSPACE_ID unset) + start → reap-orphans 미호출.
#   W4: finish-plan-dev.sh (push mock=true, marker fixture) → 로그에 reap-orphans 기록(backstop).
#   W5: start 본동작(marker 기록)은 reap mock 이 실패(exit 1)해도 정상 완료(exit 0, marker 존재).

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SESSION_SCRIPT="$REPO/scripts/plan-dev-session.sh"
FINISH_SCRIPT="$REPO/scripts/finish-plan-dev.sh"

step() { echo ""; echo "[$1] $2"; }
fail() { echo "FAIL: $1" >&2; exit 1; }

[ -x "$SESSION_SCRIPT" ] || fail "plan-dev-session.sh not executable: $SESSION_SCRIPT"
[ -x "$FINISH_SCRIPT" ]  || fail "finish-plan-dev.sh not executable: $FINISH_SCRIPT"

# ── helpers ────────────────────────────────────────────────────────

git_init_main() {
  local dir="$1"
  git -c init.defaultBranch=main init "$dir" -q 2>/dev/null \
    || git init "$dir" -q
  if [ "$(git -C "$dir" symbolic-ref --short HEAD 2>/dev/null)" != "main" ]; then
    git -C "$dir" checkout -b main -q 2>/dev/null || true
  fi
}

setup_tmp_repo() {
  local tmp
  tmp=$(mktemp -d)
  local repo="$tmp/repo"
  mkdir -p "$repo"
  git_init_main "$repo"
  git -C "$repo" config user.email "test@example.com"
  git -C "$repo" config user.name "Test"
  git -C "$repo" -c commit.gpgsign=false commit --allow-empty -q -m "init"
  echo "$tmp"
}

# cmux-pane mock — 호출 인자를 LOG_FILE 에 기록 후 exit 0
make_mock_cmux_pane_ok() {
  local tmp="$1"
  local mock="$tmp/mock-cmux-pane.sh"
  local log="$tmp/cmux-pane.log"
  cat > "$mock" <<MEOF
#!/usr/bin/env bash
echo "called with: \$*" >> "$log"
exit 0
MEOF
  chmod +x "$mock"
  printf '%s:%s' "$mock" "$log"
}

# cmux-pane mock — 호출 인자를 기록 후 exit 1 (실패 mock)
make_mock_cmux_pane_fail() {
  local tmp="$1"
  local mock="$tmp/mock-cmux-pane-fail.sh"
  local log="$tmp/cmux-pane-fail.log"
  cat > "$mock" <<MEOF
#!/usr/bin/env bash
echo "called with: \$*" >> "$log"
exit 1
MEOF
  chmod +x "$mock"
  printf '%s:%s' "$mock" "$log"
}

# finish-plan-dev.sh 용 fixture 생성 (commit-advised marker 포함)
setup_finish_fixture() {
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
  START_TS=$(python3 -c "from datetime import datetime,timezone,timedelta; print((datetime.now(timezone.utc)-timedelta(hours=1)).strftime('%Y-%m-%dT%H:%M:%SZ'))")
  cat > "$repo/.git/plan-dev-session.json" <<JEOF
{
  "start_ref": "$start_ref",
  "base_branch": "main",
  "work_branch": "main",
  "start_ts": "$START_TS",
  "start_pid": 1,
  "auto_branch": false
}
JEOF
  git -C "$repo" -c commit.gpgsign=false commit --allow-empty -q -m "test commit"
  # commit-advisor gate 통과
  touch "$repo/.git/plan-dev-commit-advised"
  echo "$tmp"
}

# ─────────────────────────────────────────
# W1: CMUX_WORKSPACE_ID set + start → reap-orphans 호출됨
# ─────────────────────────────────────────
step W1 "CMUX_WORKSPACE_ID set + start → reap-orphans 호출됨"
{
  TMP=$(setup_tmp_repo)
  REPO_DIR="$TMP/repo"
  MOCK_INFO=$(make_mock_cmux_pane_ok "$TMP")
  MOCK="${MOCK_INFO%%:*}"
  LOG="${MOCK_INFO##*:}"

  RC=0
  ( cd "$REPO_DIR" && \
    CMUX_WORKSPACE_ID="test-ws-w1" \
    CMUX_PANE_BIN="$MOCK" \
    "$SESSION_SCRIPT" start --quiet 2>/dev/null ) || RC=$?

  [ "$RC" = "0" ] || fail "W1: exit code should be 0, got $RC"
  [ -f "$LOG" ] || fail "W1: reap-orphans never called (log not created)"
  grep -q "reap-orphans" "$LOG" || fail "W1: 'reap-orphans' not found in log. log: $(cat "$LOG")"

  rm -rf "$TMP"
  echo "  W1 OK"
}

# ─────────────────────────────────────────
# W2: SKIP_CMUX_REAP=1 → reap-orphans 미호출
# ─────────────────────────────────────────
step W2 "SKIP_CMUX_REAP=1 → reap-orphans 미호출"
{
  TMP=$(setup_tmp_repo)
  REPO_DIR="$TMP/repo"
  MOCK_INFO=$(make_mock_cmux_pane_ok "$TMP")
  MOCK="${MOCK_INFO%%:*}"
  LOG="${MOCK_INFO##*:}"

  RC=0
  ( cd "$REPO_DIR" && \
    CMUX_WORKSPACE_ID="test-ws-w2" \
    SKIP_CMUX_REAP=1 \
    CMUX_PANE_BIN="$MOCK" \
    "$SESSION_SCRIPT" start --quiet 2>/dev/null ) || RC=$?

  [ "$RC" = "0" ] || fail "W2: exit code should be 0, got $RC"
  # log 파일이 없거나 reap-orphans 가 기록 안 됐어야 함
  if [ -f "$LOG" ]; then
    grep -q "reap-orphans" "$LOG" && fail "W2: reap-orphans called despite SKIP_CMUX_REAP=1. log: $(cat "$LOG")"
  fi

  rm -rf "$TMP"
  echo "  W2 OK"
}

# ─────────────────────────────────────────
# W3: CMUX_WORKSPACE_ID unset → reap-orphans 미호출
# ─────────────────────────────────────────
step W3 "CMUX_WORKSPACE_ID unset → reap-orphans 미호출"
{
  TMP=$(setup_tmp_repo)
  REPO_DIR="$TMP/repo"
  MOCK_INFO=$(make_mock_cmux_pane_ok "$TMP")
  MOCK="${MOCK_INFO%%:*}"
  LOG="${MOCK_INFO##*:}"

  RC=0
  ( cd "$REPO_DIR" && \
    env -u CMUX_WORKSPACE_ID \
    CMUX_PANE_BIN="$MOCK" \
    "$SESSION_SCRIPT" start --quiet 2>/dev/null ) || RC=$?

  [ "$RC" = "0" ] || fail "W3: exit code should be 0, got $RC"
  if [ -f "$LOG" ]; then
    grep -q "reap-orphans" "$LOG" && fail "W3: reap-orphans called despite unset CMUX_WORKSPACE_ID. log: $(cat "$LOG")"
  fi

  rm -rf "$TMP"
  echo "  W3 OK"
}

# ─────────────────────────────────────────
# W4: finish-plan-dev.sh (push=true, marker fixture, CMUX_WORKSPACE_ID set)
#     → cleanup 이후 reap-orphans backstop 호출됨
# ─────────────────────────────────────────
step W4 "finish-plan-dev.sh push success → reap-orphans backstop 호출됨"
{
  TMP=$(setup_finish_fixture)
  REPO_DIR="$TMP/repo"
  MOCK_INFO=$(make_mock_cmux_pane_ok "$TMP")
  MOCK="${MOCK_INFO%%:*}"
  LOG="${MOCK_INFO##*:}"

  RC=0
  ( cd "$REPO_DIR" && \
    CMUX_WORKSPACE_ID="test-ws-w4" \
    CMUX_PANE_BIN="$MOCK" \
    GIT_PUSH_CMD="true" \
    PLAN_DEV_SESSION_BIN=/bin/false \
    "$FINISH_SCRIPT" 2>/dev/null ) || RC=$?

  [ "$RC" = "0" ] || fail "W4: exit code should be 0, got $RC"
  [ -f "$LOG" ] || fail "W4: cmux-pane mock log not found — not called at all"
  grep -q "reap-orphans" "$LOG" || fail "W4: 'reap-orphans' not in log. log: $(cat "$LOG")"

  rm -rf "$TMP"
  echo "  W4 OK"
}

# ─────────────────────────────────────────
# W5: reap mock 실패(exit 1)해도 start 본동작 정상 완료
#     marker 파일 존재 + exit 0
# ─────────────────────────────────────────
step W5 "reap mock exit 1 → start still succeeds (exit 0, marker exists)"
{
  TMP=$(setup_tmp_repo)
  REPO_DIR="$TMP/repo"
  MOCK_INFO=$(make_mock_cmux_pane_fail "$TMP")
  MOCK="${MOCK_INFO%%:*}"
  LOG="${MOCK_INFO##*:}"

  RC=0
  ( cd "$REPO_DIR" && \
    CMUX_WORKSPACE_ID="test-ws-w5" \
    CMUX_PANE_BIN="$MOCK" \
    "$SESSION_SCRIPT" start --quiet 2>/dev/null ) || RC=$?

  [ "$RC" = "0" ] || fail "W5: exit code should be 0 even if reap fails, got $RC"
  [ -f "$REPO_DIR/.git/plan-dev-session.json" ] || fail "W5: marker not created when reap fails"

  rm -rf "$TMP"
  echo "  W5 OK"
}

echo ""
echo "PASS"
