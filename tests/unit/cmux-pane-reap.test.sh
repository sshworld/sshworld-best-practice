#!/usr/bin/env bash
# cmux-pane-reap.test.sh — do_reap 완료 자식 자동 회수 검증

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO/scripts/cmux-pane.sh"

pass=0
fail_count=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

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

total=16

# fake cmux: read-screen → CMUX_SCREEN_FILE 출력, 그 외 → CMUX_CALLS_LOG 에 append
cat > "$TMP/cmux" << 'EOF'
#!/usr/bin/env bash
cmd="$1"; shift
if [ "$cmd" = "read-screen" ]; then
  cat "${CMUX_SCREEN_FILE:-/dev/null}" 2>/dev/null || true
else
  echo "$cmd $*" >> "${CMUX_CALLS_LOG:-/dev/null}"
fi
EOF
chmod +x "$TMP/cmux"

STATE_FILE="$TMP/reap.state"

# ----------------------------------------------------------------
# TC (a): ✅ done 마커 → close-surface 호출 + "reaped" 출력 + exit 0
printf '✅ done\nsome output\n' > "$TMP/screen.txt"
> "$TMP/calls.log"
> "$STATE_FILE"
exit_code=99
stdout_out=$(CMUX_BIN="$TMP/cmux" \
  CMUX_SCREEN_FILE="$TMP/screen.txt" \
  CMUX_CALLS_LOG="$TMP/calls.log" \
  CBP_STATE_FILE="$STATE_FILE" \
  bash "$SCRIPT" reap --pane=surface:5 --idle=0 --timeout=5 2>/dev/null) && exit_code=0 || exit_code=$?
check "TC-a: done 화면 → exit 0" "0" "$exit_code"
close_called=$(grep -c "close-surface --surface surface:5" "$TMP/calls.log" 2>/dev/null || echo 0)
check "TC-a: close-surface surface:5 호출됨" "1" "$close_called"
check_contains "TC-a: 'reaped' 출력 포함" "reaped" "$stdout_out"

# ----------------------------------------------------------------
# TC (b): 마커 없음(일반 prompt) → close-surface 미호출 + "not done" 출력 + exit 0
printf '❯\nsome regular output\n' > "$TMP/screen.txt"
> "$TMP/calls.log"
exit_code=99
stdout_out=$(CMUX_BIN="$TMP/cmux" \
  CMUX_SCREEN_FILE="$TMP/screen.txt" \
  CMUX_CALLS_LOG="$TMP/calls.log" \
  CBP_STATE_FILE="$STATE_FILE" \
  bash "$SCRIPT" reap --pane=surface:5 --idle=0 --timeout=5 2>/dev/null) && exit_code=0 || exit_code=$?
check "TC-b: 마커 없음 → exit 0" "0" "$exit_code"
close_called=$(grep -c "close-surface" "$TMP/calls.log" 2>/dev/null || true)
check "TC-b: close-surface 미호출" "0" "$close_called"
check_contains "TC-b: 'not done' 출력 포함" "not done" "$stdout_out"

# ----------------------------------------------------------------
# TC (c): CMUX_SURFACE_ID=surface:5 + reap --pane=surface:5 → 자기 surface 거부 (exit 2)
printf '✅ done\n' > "$TMP/screen.txt"
> "$TMP/calls.log"
exit_code=0
CMUX_BIN="$TMP/cmux" \
  CMUX_SCREEN_FILE="$TMP/screen.txt" \
  CMUX_SURFACE_ID="surface:5" \
  CBP_STATE_FILE="$STATE_FILE" \
  bash "$SCRIPT" reap --pane=surface:5 --idle=0 --timeout=5 2>/dev/null || exit_code=$?
check "TC-c: 자기 surface reap → exit 2 거부" "2" "$exit_code"

# ----------------------------------------------------------------
# TC (d): CBP_REAP_DRY_RUN=1 + done 화면 → close 안 함 + "would reap" 출력 + exit 0
printf '✅ done\n' > "$TMP/screen.txt"
> "$TMP/calls.log"
exit_code=99
stdout_out=$(CMUX_BIN="$TMP/cmux" \
  CMUX_SCREEN_FILE="$TMP/screen.txt" \
  CMUX_CALLS_LOG="$TMP/calls.log" \
  CBP_STATE_FILE="$STATE_FILE" \
  CBP_REAP_DRY_RUN=1 \
  bash "$SCRIPT" reap --pane=surface:5 --idle=0 --timeout=5 2>/dev/null) && exit_code=0 || exit_code=$?
check "TC-d: dry-run → exit 0" "0" "$exit_code"
close_called=$(grep -c "close-surface" "$TMP/calls.log" 2>/dev/null || true)
check "TC-d: dry-run → close-surface 미호출" "0" "$close_called"
check_contains "TC-d: dry-run → 'would reap' 출력" "would reap" "$stdout_out"

# ----------------------------------------------------------------
# TC (a2): ⏺ ✅ prefix (Claude TUI 렌더 형식) → reaped
printf '⏺ ✅ reap-done-pattern\n' > "$TMP/screen.txt"
> "$TMP/calls.log"
exit_code=99
stdout_out=$(CMUX_BIN="$TMP/cmux" \
  CMUX_SCREEN_FILE="$TMP/screen.txt" \
  CMUX_CALLS_LOG="$TMP/calls.log" \
  CBP_STATE_FILE="$STATE_FILE" \
  bash "$SCRIPT" reap --pane=surface:5 --idle=0 --timeout=5 2>/dev/null) && exit_code=0 || exit_code=$?
check "TC-a2: ⏺ ✅ prefix → exit 0" "0" "$exit_code"
close_called=$(grep -c "close-surface --surface surface:5" "$TMP/calls.log" 2>/dev/null || echo 0)
check "TC-a2: ⏺ ✅ prefix → close-surface 호출" "1" "$close_called"
check_contains "TC-a2: ⏺ ✅ prefix → 'reaped' 출력" "reaped" "$stdout_out"

# ----------------------------------------------------------------
# TC (a3): 선두 공백 2칸 ✅ (들여쓰기) → reaped
printf '  ✅ reap-done-pattern\n' > "$TMP/screen.txt"
> "$TMP/calls.log"
exit_code=99
stdout_out=$(CMUX_BIN="$TMP/cmux" \
  CMUX_SCREEN_FILE="$TMP/screen.txt" \
  CMUX_CALLS_LOG="$TMP/calls.log" \
  CBP_STATE_FILE="$STATE_FILE" \
  bash "$SCRIPT" reap --pane=surface:5 --idle=0 --timeout=5 2>/dev/null) && exit_code=0 || exit_code=$?
check "TC-a3: 들여쓰기 ✅ → exit 0" "0" "$exit_code"
close_called=$(grep -c "close-surface --surface surface:5" "$TMP/calls.log" 2>/dev/null || echo 0)
check "TC-a3: 들여쓰기 ✅ → close-surface 호출" "1" "$close_called"
check_contains "TC-a3: 들여쓰기 ✅ → 'reaped' 출력" "reaped" "$stdout_out"

echo ""
echo "ok: $pass/$total passed"
[ "$fail_count" -gt 0 ] && exit 1
exit 0
