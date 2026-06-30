#!/usr/bin/env bash
# finish-plan-dev.sh commit-advisor gate 테스트 (S1)
# commit-advised marker (.git/plan-dev-commit-advised) 기반 push 게이트 검증.

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
  echo "$tmp"
}

# ── Case 1: 세션 marker 활성 + 커밋 존재 + commit-advised marker 부재 → exit 2 ─

step 1 "commit-advised marker 부재 → exit 2, stderr 에 commit-advisor 문자열"
{
  TMP=$(setup_fixture)
  REPO_DIR="$TMP/repo"

  # commit-advised marker 없음 (setup_fixture 가 생성 안 함)
  set +e
  ERR=$(cd "$REPO_DIR" && \
    GIT_PUSH_CMD="true" \
    PLAN_DEV_SESSION_BIN=/bin/false \
    "$FINISH" 2>&1 >/dev/null)
  RC=$?
  set -e

  [ "$RC" = "2" ] || fail "Case 1: exit code should be 2, got $RC"
  echo "$ERR" | grep -q "commit-advisor" \
    || fail "Case 1: stderr should contain 'commit-advisor', got: $ERR"

  rm -rf "$TMP"
  echo "  Case 1 OK"
}

# ── Case 2: commit-advised marker 존재 → push 진행 → exit 0, stdout 'pushed' ─

step 2 "commit-advised marker 존재 → push 진행 → exit 0"
{
  TMP=$(setup_fixture)
  REPO_DIR="$TMP/repo"

  # commit-advised marker touch
  touch "$REPO_DIR/.git/plan-dev-commit-advised"

  OUT=$(cd "$REPO_DIR" && \
    GIT_PUSH_CMD="true" \
    PLAN_DEV_SESSION_BIN=/bin/false \
    "$FINISH" 2>/dev/null)
  RC=$?

  [ "$RC" = "0" ] || fail "Case 2: exit code should be 0, got $RC (stdout: $OUT)"
  echo "$OUT" | grep -q "pushed" || fail "Case 2: stdout should contain 'pushed', got: $OUT"

  rm -rf "$TMP"
  echo "  Case 2 OK"
}

# ── Case 3: marker 부재 + SKIP_COMMIT_ADVISOR_GATE=1 → exit 0 (1회 우회) ─────

step 3 "SKIP_COMMIT_ADVISOR_GATE=1 → exit 0 (1회 우회)"
{
  TMP=$(setup_fixture)
  REPO_DIR="$TMP/repo"

  # commit-advised marker 없음
  OUT=$(cd "$REPO_DIR" && \
    SKIP_COMMIT_ADVISOR_GATE=1 \
    GIT_PUSH_CMD="true" \
    PLAN_DEV_SESSION_BIN=/bin/false \
    "$FINISH" 2>/dev/null)
  RC=$?

  [ "$RC" = "0" ] || fail "Case 3: exit code should be 0, got $RC (stdout: $OUT)"

  rm -rf "$TMP"
  echo "  Case 3 OK"
}

# ── Case 4: marker 부재 + DISABLE_COMMIT_ADVISOR_GATE=1 → exit 0 (영구 우회) ─

step 4 "DISABLE_COMMIT_ADVISOR_GATE=1 → exit 0 (영구 우회)"
{
  TMP=$(setup_fixture)
  REPO_DIR="$TMP/repo"

  # commit-advised marker 없음
  OUT=$(cd "$REPO_DIR" && \
    DISABLE_COMMIT_ADVISOR_GATE=1 \
    GIT_PUSH_CMD="true" \
    PLAN_DEV_SESSION_BIN=/bin/false \
    "$FINISH" 2>/dev/null)
  RC=$?

  [ "$RC" = "0" ] || fail "Case 4: exit code should be 0, got $RC (stdout: $OUT)"

  rm -rf "$TMP"
  echo "  Case 4 OK"
}

# ── Case 5: push 성공 후 commit-advised marker 삭제 확인 (clear_marker 연동) ──

step 5 "push 성공 후 commit-advised marker 삭제됨 (clear_marker 연동)"
{
  TMP=$(setup_fixture)
  REPO_DIR="$TMP/repo"

  # commit-advised marker touch
  touch "$REPO_DIR/.git/plan-dev-commit-advised"

  OUT=$(cd "$REPO_DIR" && \
    GIT_PUSH_CMD="true" \
    PLAN_DEV_SESSION_BIN=/bin/false \
    "$FINISH" 2>/dev/null)
  RC=$?

  [ "$RC" = "0" ] || fail "Case 5: exit code should be 0, got $RC (stdout: $OUT)"
  [ ! -f "$REPO_DIR/.git/plan-dev-commit-advised" ] \
    || fail "Case 5: commit-advised marker should be deleted after successful push"

  rm -rf "$TMP"
  echo "  Case 5 OK"
}

echo ""
echo "PASS"
