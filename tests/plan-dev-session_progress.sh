#!/usr/bin/env bash
# plan-dev-session_progress.sh — progress subcommand 테스트.
# TDD: 이 파일을 먼저 작성 (Red). scripts/plan-dev-session.sh 구현 후 Green.

set -uo pipefail

# ⚠️ 이 스위트는 plan-dev-session.sh start 를 실제 실행한다. start 는 cmux 환경
# (CMUX_WORKSPACE_ID set)이면 best-effort 로 실제 `cmux-pane.sh reap-orphans` 를
# 호출한다 — 전 workspace 의 자식 state 를 훑어 dead 판정 surface 를 닫는다.
# plan-dev 세션 중 이 테스트를 돌리면 살아있는 자식 surface 가 회수될 수 있다.
export SKIP_CMUX_REAP=1

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO/scripts/plan-dev-session.sh"

step() { echo "[$1] $2"; }
fail() { echo "FAIL: $1" >&2; exit 1; }

[ -x "$SCRIPT" ] || fail "script not executable or missing: $SCRIPT"

setup_tmp_repo() {
  local dir
  dir="$(mktemp -d)"
  git -C "$dir" init -q
  git -C "$dir" config user.email "test@example.com"
  git -C "$dir" config user.name "Test"
  git -C "$dir" commit --allow-empty -m "init" -q
  echo "$dir"
}

cleanup_tmp() {
  [ -n "${1:-}" ] && rm -rf "$1"
}

# ─────────────────────────────────────────
# TC1: start --total=5 → total_slices==5, done_slices==0
# ─────────────────────────────────────────
step 1 "start --total=5 → total_slices=5, done_slices=0"
TMPDIR1="$(setup_tmp_repo)"
trap 'cleanup_tmp "$TMPDIR1"' EXIT

(
  cd "$TMPDIR1"
  "$SCRIPT" start --total=5 --quiet 2>/dev/null || true
)

MARKER1="$TMPDIR1/.git/plan-dev-session.json"
[ -f "$MARKER1" ] || fail "TC1: marker 파일 없음"

TOTAL1=$(
  cd "$TMPDIR1"
  "$SCRIPT" query --key=total_slices 2>/dev/null
)
DONE1=$(
  cd "$TMPDIR1"
  "$SCRIPT" query --key=done_slices 2>/dev/null
)

[ "$TOTAL1" = "5" ] || fail "TC1: total_slices 기대=5, 실제='$TOTAL1'"
[ "$DONE1" = "0" ] || fail "TC1: done_slices 기대=0, 실제='$DONE1'"
echo "  TC1 OK"
trap - EXIT
cleanup_tmp "$TMPDIR1"

# ─────────────────────────────────────────
# TC2: progress --inc × 3 → stdout "3/5 (60%)", done_slices==3
# ─────────────────────────────────────────
step 2 "progress --inc × 3 → 3/5 (60%)"
TMPDIR2="$(setup_tmp_repo)"
trap 'cleanup_tmp "$TMPDIR2"' EXIT

(
  cd "$TMPDIR2"
  "$SCRIPT" start --total=5 --quiet 2>/dev/null || true
)

MARKER2="$TMPDIR2/.git/plan-dev-session.json"
[ -f "$MARKER2" ] || fail "TC2: marker 없음"

OUT2=""
for i in 1 2 3; do
  OUT2=$(
    cd "$TMPDIR2"
    "$SCRIPT" progress --inc
  )
done

[ "$OUT2" = "3/5 (60%)" ] || fail "TC2: 기대='3/5 (60%)', 실제='$OUT2'"

DONE2=$(
  cd "$TMPDIR2"
  "$SCRIPT" query --key=done_slices 2>/dev/null
)
[ "$DONE2" = "3" ] || fail "TC2: done_slices 기대=3, 실제='$DONE2'"
echo "  TC2 OK"
trap - EXIT
cleanup_tmp "$TMPDIR2"

# ─────────────────────────────────────────
# TC3: progress --set-done=5 → "5/5 (100%)"
# ─────────────────────────────────────────
step 3 "progress --set-done=5 → 5/5 (100%)"
TMPDIR3="$(setup_tmp_repo)"
trap 'cleanup_tmp "$TMPDIR3"' EXIT

(
  cd "$TMPDIR3"
  "$SCRIPT" start --total=5 --quiet 2>/dev/null || true
)

MARKER3="$TMPDIR3/.git/plan-dev-session.json"
[ -f "$MARKER3" ] || fail "TC3: marker 없음"

OUT3=$(
  cd "$TMPDIR3"
  "$SCRIPT" progress --set-done=5
)

[ "$OUT3" = "5/5 (100%)" ] || fail "TC3: 기대='5/5 (100%)', 실제='$OUT3'"
echo "  TC3 OK"
trap - EXIT
cleanup_tmp "$TMPDIR3"

# ─────────────────────────────────────────
# TC4: progress --set-total=10 --set-done=1 → "1/10 (10%)"
# ─────────────────────────────────────────
step 4 "progress --set-total=10 --set-done=1 → 1/10 (10%)"
TMPDIR4="$(setup_tmp_repo)"
trap 'cleanup_tmp "$TMPDIR4"' EXIT

(
  cd "$TMPDIR4"
  "$SCRIPT" start --quiet 2>/dev/null || true
)

MARKER4="$TMPDIR4/.git/plan-dev-session.json"
[ -f "$MARKER4" ] || fail "TC4: marker 없음"

OUT4=$(
  cd "$TMPDIR4"
  "$SCRIPT" progress --set-total=10 --set-done=1
)

[ "$OUT4" = "1/10 (10%)" ] || fail "TC4: 기대='1/10 (10%)', 실제='$OUT4'"
echo "  TC4 OK"
trap - EXIT
cleanup_tmp "$TMPDIR4"

# ─────────────────────────────────────────
# TC5: start (no --total) → progress --inc → "1" (pct 없음)
# ─────────────────────────────────────────
step 5 "start (no --total) → progress --inc → 1 (pct 없음)"
TMPDIR5="$(setup_tmp_repo)"
trap 'cleanup_tmp "$TMPDIR5"' EXIT

(
  cd "$TMPDIR5"
  "$SCRIPT" start --quiet 2>/dev/null || true
)

MARKER5="$TMPDIR5/.git/plan-dev-session.json"
[ -f "$MARKER5" ] || fail "TC5: marker 없음"

OUT5=$(
  cd "$TMPDIR5"
  "$SCRIPT" progress --inc
)

[ "$OUT5" = "1" ] || fail "TC5: 기대='1', 실제='$OUT5'"
echo "  TC5 OK"
trap - EXIT
cleanup_tmp "$TMPDIR5"

# ─────────────────────────────────────────
# TC6: marker 미존재 상태 progress → exit 1
# ─────────────────────────────────────────
step 6 "marker 없음 → progress → exit 1"
TMPDIR6="$(setup_tmp_repo)"
trap 'cleanup_tmp "$TMPDIR6"' EXIT

RC6=0
(
  cd "$TMPDIR6"
  "$SCRIPT" progress 2>/dev/null
) && RC6=$? || RC6=$?

[ "$RC6" = "1" ] || fail "TC6: exit 1 기대, 실제=$RC6"
echo "  TC6 OK"
trap - EXIT
cleanup_tmp "$TMPDIR6"

echo ""
echo "PASS"
