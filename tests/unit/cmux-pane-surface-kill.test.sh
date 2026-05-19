#!/usr/bin/env bash
# cmux-pane-surface-kill.test.sh — do_kill の surface ref 분기 검증 (S2)
#
# TDD 명세 (Slice S2):
#   1. self-surface 거부: CMUX_SURFACE_ID=surface:99 → exit 2, stderr "자기 surface kill 거부"
#   2. child-surface 허용: CMUX_SURFACE_ID=surface:99, kill surface:0 → exit 0, close-surface 호출
#   3. child-surface 허용 (FORCE_SELF_KILL 무관): unset FORCE_SELF_KILL 시도 동일하게 허용
#   4. workspace self 거부 (기존 회귀): FORCE_SELF_KILL=0 → exit 2, =1 → 허용

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO/scripts/cmux-pane.sh"

pass=0
fail_count=0

check() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then
    echo "ok: $desc"
    pass=$((pass + 1))
  else
    echo "FAIL: $desc — expected='$expected' got='$actual'" >&2
    fail_count=$((fail_count + 1))
  fi
}

check_contains() {
  local desc="$1" expected="$2" actual="$3"
  if printf '%s' "$actual" | grep -qF -- "$expected"; then
    echo "ok: $desc"
    pass=$((pass + 1))
  else
    echo "FAIL: $desc — expected substring='$expected' in output='$actual'" >&2
    fail_count=$((fail_count + 1))
  fi
}

check_not_contains() {
  local desc="$1" not_expected="$2" actual="$3"
  if printf '%s' "$actual" | grep -qF -- "$not_expected"; then
    echo "FAIL: $desc — unexpected substring='$not_expected' found in output='$actual'" >&2
    fail_count=$((fail_count + 1))
  else
    echo "ok: $desc"
    pass=$((pass + 1))
  fi
}

[ -f "$SCRIPT" ] || { echo "FAIL: $SCRIPT 없음" >&2; exit 1; }

STATE_FILE="/tmp/test-s2-surface-kill-$$.state"
trap 'rm -f "$STATE_FILE"' EXIT

total=9

# ----------------------------------------------------------------
# TC1: self-surface 거부 — CMUX_SURFACE_ID=surface:99, kill --pane=surface:99 → exit 2
# ----------------------------------------------------------------
exit_code=0
CMUX_BIN=echo CMUX_SURFACE_ID="surface:99" \
  bash "$SCRIPT" kill --pane=surface:99 2>/dev/null || exit_code=$?
check "TC1: self-surface kill → exit 2" "2" "$exit_code"

# stderr 에 "자기 surface kill 거부" 포함
stderr_out=$(CMUX_BIN=echo CMUX_SURFACE_ID="surface:99" \
  bash "$SCRIPT" kill --pane=surface:99 2>&1 >/dev/null || true)
check_contains "TC1: stderr '자기 surface kill 거부' 포함" "자기 surface kill 거부" "$stderr_out"

# 새 에러 메시지에 FORCE_SELF_KILL=1 우회 안내가 없어야 함
check_not_contains "TC1: 에러 메시지에 FORCE_SELF_KILL=1 없음" "FORCE_SELF_KILL=1" "$stderr_out"

# ----------------------------------------------------------------
# TC2: child-surface 허용 — CMUX_SURFACE_ID=surface:99, kill --pane=surface:0 → exit 0
# ----------------------------------------------------------------
exit_code=99
stdout_out=$(CMUX_BIN=echo CMUX_SURFACE_ID="surface:99" \
  CBP_STATE_FILE="$STATE_FILE" \
  bash "$SCRIPT" kill --pane=surface:0 2>/dev/null) && exit_code=0 || exit_code=$?
check "TC2: child-surface kill → exit 0" "0" "$exit_code"
check_contains "TC2: close-surface --surface surface:0 호출" "close-surface --surface surface:0" "$stdout_out"

# ----------------------------------------------------------------
# TC3: child-surface 허용 — FORCE_SELF_KILL 영향 없음 (unset 상태에서도 허용)
# ----------------------------------------------------------------
exit_code=99
stdout_out=$(CMUX_BIN=echo CMUX_SURFACE_ID="surface:99" \
  CBP_STATE_FILE="$STATE_FILE" \
  bash "$SCRIPT" kill --pane=surface:0 2>/dev/null) && exit_code=0 || exit_code=$?
check "TC3: child-surface kill (FORCE_SELF_KILL unset) → exit 0" "0" "$exit_code"
check_contains "TC3: close-surface --surface surface:0 호출" "close-surface --surface surface:0" "$stdout_out"

# ----------------------------------------------------------------
# TC4: workspace self 거부 (기존 동작 회귀)
# CMUX_FAKE_SELF_CMUX_WS=ws-1, kill --pane=workspace:ws-1, FORCE_SELF_KILL 미설정 → exit 2
# ----------------------------------------------------------------
exit_code=0
CMUX_BIN=echo CLAUDE_FAKE_SELF_CMUX_WS="workspace:ws-1" \
  bash "$SCRIPT" kill --pane=workspace:ws-1 2>/dev/null || exit_code=$?
check "TC4: workspace self (FORCE_SELF_KILL unset) → exit 2" "2" "$exit_code"

# FORCE_SELF_KILL=1 시 허용
exit_code=99
CMUX_BIN=echo CLAUDE_FAKE_SELF_CMUX_WS="workspace:ws-1" \
  FORCE_SELF_KILL=1 \
  bash "$SCRIPT" kill --pane=workspace:ws-1 2>/dev/null && exit_code=0 || exit_code=$?
check "TC4: workspace self (FORCE_SELF_KILL=1) → exit 0" "0" "$exit_code"

echo ""
echo "ok: $pass/$total passed"
[ "$fail_count" -gt 0 ] && exit 1
exit 0
