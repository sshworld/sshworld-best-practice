#!/usr/bin/env bash
# cmux-pane-send-confirm.test.sh — do_send confirm 재시도 동작 검증

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

[ -f "$SCRIPT" ] || { echo "FAIL: $SCRIPT 없음" >&2; exit 1; }

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

total=5

# ----------------------------------------------------------------
# TC1: 미제출(❯ pending text) → TRIES=3 회 추가 Enter → base+TRIES=4
printf '❯ some pending text\n' > "$TMP/screen.txt"
> "$TMP/calls.log"
CMUX_BIN="$TMP/cmux" \
  CMUX_SCREEN_FILE="$TMP/screen.txt" \
  CMUX_CALLS_LOG="$TMP/calls.log" \
  CBP_SEND_CONFIRM_TRIES=3 \
  CBP_SEND_CONFIRM_SLEEP=0 \
  bash "$SCRIPT" send "hello" --pane=surface:1 --enter-count=1 --delay=0 2>/dev/null || true

sendkey_count=$(grep -c "^send-key" "$TMP/calls.log" 2>/dev/null || echo 0)
check "TC1: 미제출 TRIES=3 → send-key 4회 (base 1 + 3)" "4" "$sendkey_count"

# ----------------------------------------------------------------
# TC2: 이미 제출됨(❯ 빈 프롬프트) → 추가 없음 → send-key == ENTER_COUNT
printf '❯\n' > "$TMP/screen.txt"
> "$TMP/calls.log"
CMUX_BIN="$TMP/cmux" \
  CMUX_SCREEN_FILE="$TMP/screen.txt" \
  CMUX_CALLS_LOG="$TMP/calls.log" \
  CBP_SEND_CONFIRM_TRIES=3 \
  CBP_SEND_CONFIRM_SLEEP=0 \
  bash "$SCRIPT" send "hello" --pane=surface:1 --enter-count=1 --delay=0 2>/dev/null || true

sendkey_count=$(grep -c "^send-key" "$TMP/calls.log" 2>/dev/null || echo 0)
check "TC2: 이미 제출됨 → send-key 1회 (base 만)" "1" "$sendkey_count"

# ----------------------------------------------------------------
# TC3: read-screen 빈값 → 판정 불가 → 0회 추가 (보수적)
printf '' > "$TMP/screen.txt"
> "$TMP/calls.log"
CMUX_BIN="$TMP/cmux" \
  CMUX_SCREEN_FILE="$TMP/screen.txt" \
  CMUX_CALLS_LOG="$TMP/calls.log" \
  CBP_SEND_CONFIRM_TRIES=3 \
  CBP_SEND_CONFIRM_SLEEP=0 \
  bash "$SCRIPT" send "hello" --pane=surface:1 --enter-count=1 --delay=0 2>/dev/null || true

sendkey_count=$(grep -c "^send-key" "$TMP/calls.log" 2>/dev/null || echo 0)
# PTY detached 의심(rc2) → Enter 재전송으로 attach 강제: base 1 + TRIES 3 = 4
check "TC3: read-screen 빈값(detached 의심) → send-key 4회 (base 1 + detached 3)" "4" "$sendkey_count"

# ----------------------------------------------------------------
# TC5: read-screen "Terminal surface not found" → PTY detached 의심 → Enter 재전송 ≥2
printf 'Terminal surface not found\n' > "$TMP/screen.txt"
> "$TMP/calls.log"
CMUX_BIN="$TMP/cmux" \
  CMUX_SCREEN_FILE="$TMP/screen.txt" \
  CMUX_CALLS_LOG="$TMP/calls.log" \
  CBP_SEND_CONFIRM_TRIES=3 \
  CBP_SEND_CONFIRM_SLEEP=0 \
  bash "$SCRIPT" send "hello" --pane=surface:1 --enter-count=1 --delay=0 2>/dev/null || true

sendkey_count=$(grep -c "^send-key" "$TMP/calls.log" 2>/dev/null || echo 0)
# "Terminal surface not found" → no prompt → rc2 → detached 재시도: base 1 + TRIES 3 = 4
check "TC5: 'Terminal surface not found' → send-key 4회 (detached 재시도)" "4" "$sendkey_count"

# ----------------------------------------------------------------
# 회귀: CBP_SEND_CONFIRM=0 → confirm 루프 스킵, 기존 동작 유지
printf '❯ pending text\n' > "$TMP/screen.txt"
> "$TMP/calls.log"
CMUX_BIN="$TMP/cmux" \
  CMUX_SCREEN_FILE="$TMP/screen.txt" \
  CMUX_CALLS_LOG="$TMP/calls.log" \
  CBP_SEND_CONFIRM=0 \
  CBP_SEND_CONFIRM_SLEEP=0 \
  bash "$SCRIPT" send "hello" --pane=surface:1 --enter-count=1 --delay=0 2>/dev/null || true

sendkey_count=$(grep -c "^send-key" "$TMP/calls.log" 2>/dev/null || echo 0)
check "회귀: CBP_SEND_CONFIRM=0 → send-key 1회 (기존 동작)" "1" "$sendkey_count"

echo ""
echo "ok: $pass/$total passed"
[ "$fail_count" -gt 0 ] && exit 1
exit 0
