#!/usr/bin/env bash
# plan_dev_session_setplan.sh — set-plan 서브커맨드 테스트.
# TDD Red: 먼저 작성 후 scripts/plan-dev-session.sh 수정으로 Green.
#
# 케이스:
#   T1: set-plan 이 기존 필드(start_ts/start_ref/done_slices) 보존하며 plan_file 만 추가
#   T2 (C-1 회귀): set-plan 후 do_start 재진입(dead pid + within_24h) → plan_file 잔존
#   T3: marker 부재 시 set-plan no-op + exit 0

set -uo pipefail

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
# T1: 기존 필드 보존 + plan_file 추가
# ─────────────────────────────────────────
step T1 "set-plan 이 기존 필드 보존하며 plan_file 만 추가"
TMPDIR1="$(setup_tmp_repo)"
trap 'cleanup_tmp "$TMPDIR1"' EXIT

(
  cd "$TMPDIR1"
  "$SCRIPT" start --quiet --total=3 2>/dev/null || true
)

MARKER1="$TMPDIR1/.git/plan-dev-session.json"
[ -f "$MARKER1" ] || fail "T1: start 후 marker 없음"

TS_BEFORE=$(cd "$TMPDIR1" && "$SCRIPT" query --key=start_ts 2>/dev/null)
REF_BEFORE=$(cd "$TMPDIR1" && "$SCRIPT" query --key=start_ref 2>/dev/null)
TOTAL_BEFORE=$(cd "$TMPDIR1" && "$SCRIPT" query --key=total_slices 2>/dev/null)

PLAN_FILE1="$TMPDIR1/my-plan.md"
echo "# plan" > "$PLAN_FILE1"

(
  cd "$TMPDIR1"
  "$SCRIPT" set-plan "$PLAN_FILE1" 2>/dev/null
) || fail "T1: set-plan 실패"

TS_AFTER=$(cd "$TMPDIR1" && "$SCRIPT" query --key=start_ts 2>/dev/null)
REF_AFTER=$(cd "$TMPDIR1" && "$SCRIPT" query --key=start_ref 2>/dev/null)
TOTAL_AFTER=$(cd "$TMPDIR1" && "$SCRIPT" query --key=total_slices 2>/dev/null)
PLAN_FIELD=$(cd "$TMPDIR1" && "$SCRIPT" query --key=plan_file 2>/dev/null)

[ "$TS_BEFORE" = "$TS_AFTER" ] || fail "T1: start_ts 변경됨. before='$TS_BEFORE' after='$TS_AFTER'"
[ "$REF_BEFORE" = "$REF_AFTER" ] || fail "T1: start_ref 변경됨. before='$REF_BEFORE' after='$REF_AFTER'"
[ "$TOTAL_BEFORE" = "$TOTAL_AFTER" ] || fail "T1: total_slices 변경됨. before='$TOTAL_BEFORE' after='$TOTAL_AFTER'"
[ "$PLAN_FIELD" = "$PLAN_FILE1" ] || fail "T1: plan_file 미기록. got='$PLAN_FIELD' expected='$PLAN_FILE1'"
echo "  T1 OK"
trap - EXIT
cleanup_tmp "$TMPDIR1"

# ─────────────────────────────────────────
# T2 (C-1 회귀): set-plan 후 do_start 재진입 → plan_file 잔존
# ─────────────────────────────────────────
step T2 "set-plan 후 do_start 재진입(dead pid + within_24h) → plan_file 잔존"
TMPDIR2="$(setup_tmp_repo)"
trap 'cleanup_tmp "$TMPDIR2"' EXIT

(
  cd "$TMPDIR2"
  "$SCRIPT" start --quiet 2>/dev/null || true
)

MARKER2="$TMPDIR2/.git/plan-dev-session.json"
[ -f "$MARKER2" ] || fail "T2: start 후 marker 없음"

PLAN_FILE2="$TMPDIR2/my-plan.md"
echo "# plan" > "$PLAN_FILE2"
(
  cd "$TMPDIR2"
  "$SCRIPT" set-plan "$PLAN_FILE2" 2>/dev/null
) || fail "T2: set-plan 실패"

# start_pid 를 죽은 PID 로 교체 (recent ts 유지 — within_24h 재진입 유도)
python3 -c "
import json
f = '$MARKER2'
d = json.load(open(f))
d['start_pid'] = 9999999
open(f, 'w').write(json.dumps(d, indent=2) + '\n')
"

sleep 1

(
  cd "$TMPDIR2"
  "$SCRIPT" start --quiet 2>/dev/null || true
)

PLAN_FIELD2=$(cd "$TMPDIR2" && "$SCRIPT" query --key=plan_file 2>/dev/null)
[ "$PLAN_FIELD2" = "$PLAN_FILE2" ] || fail "T2: 재진입 후 plan_file 소멸. got='$PLAN_FIELD2' expected='$PLAN_FILE2'"
echo "  T2 OK"
trap - EXIT
cleanup_tmp "$TMPDIR2"

# ─────────────────────────────────────────
# T3: marker 부재 시 set-plan no-op + exit 0
# ─────────────────────────────────────────
step T3 "marker 부재 시 set-plan no-op + exit 0"
TMPDIR3="$(setup_tmp_repo)"
trap 'cleanup_tmp "$TMPDIR3"' EXIT

# start 를 호출하지 않음 → marker 없음
RC=$(
  cd "$TMPDIR3"
  "$SCRIPT" set-plan "$TMPDIR3/no-marker-plan.md" >/dev/null 2>&1
  echo $?
)
[ "$RC" = "0" ] || fail "T3: exit code should be 0, got $RC"
[ ! -f "$TMPDIR3/.git/plan-dev-session.json" ] || fail "T3: marker 가 생성되면 안 됨"
echo "  T3 OK"
trap - EXIT
cleanup_tmp "$TMPDIR3"

echo ""
echo "OK"
