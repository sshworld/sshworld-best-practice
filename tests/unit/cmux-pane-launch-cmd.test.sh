#!/usr/bin/env bash
# cmux-pane-launch-cmd.test.sh — _do_launch_grid 이 launch cmd 인자를 do_send 로 전달하는지 검증.
#
# TC-1: launch "echo HELLO" → send 호출 로그에 "echo HELLO" 포함 (grid 경로, warmup on)
# TC-2: launch (no cmd)    → cmd send 호출 없음 (send-key Enter / rename-tab 만 허용)
# TC-3: CBP_DISABLE_WARMUP=1 + cmd → send 호출에 cmd 포함 (early-return 경로에서도 cmd 전달)
# TC-4: CBP_DISABLE_WARMUP=1 + no cmd → cmd send 없음

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

total=4

# ----------------------------------------------------------------
# Mock cmux:
#   new-pane  → "OK surface:42" + CMUX_CALLS 기록
#   new-split → "OK surface:43" + CMUX_CALLS 기록
#   read-screen → exit 0 (PTY alive)
#   send      → CMUX_CALLS 기록
#   send-key  → CMUX_CALLS 기록
#   rename-tab → exit 0
#   그 외      → CMUX_CALLS 기록 + exit 0
cat > "$TMP/cmux" << 'EOF'
#!/usr/bin/env bash
cmd="$1"; shift
log="${CMUX_CALLS:-/dev/null}"
case "$cmd" in
  new-pane)
    echo "new-pane $*" >> "$log"
    echo "OK surface:42"
    exit 0
    ;;
  new-split)
    echo "new-split $*" >> "$log"
    echo "OK surface:43"
    exit 0
    ;;
  read-screen)
    # alive
    echo "prompt ❯"
    exit 0
    ;;
  send)
    echo "send $*" >> "$log"
    exit 0
    ;;
  send-key)
    echo "send-key $*" >> "$log"
    exit 0
    ;;
  rename-tab)
    exit 0
    ;;
  *)
    echo "$cmd $*" >> "$log"
    exit 0
    ;;
esac
EOF
chmod +x "$TMP/cmux"

# ----------------------------------------------------------------
# TC-1: launch "echo HELLO" (warmup 활성) → send 로그에 "echo HELLO" 포함
STATE_FILE="$TMP/state1.json"
> "$STATE_FILE"
CALLS="$TMP/calls1.log"
> "$CALLS"

CMUX_BIN="$TMP/cmux" \
  CMUX_WORKSPACE_ID="ws:test" \
  CBP_STATE_FILE="$STATE_FILE" \
  CMUX_CALLS="$CALLS" \
  CBP_WARMUP_SLEEP=0 \
  CBP_LAUNCH_VERIFY_TRIES=1 \
  bash "$SCRIPT" launch "echo HELLO" 2>/dev/null

send_log=$(grep "^send " "$CALLS" 2>/dev/null || true)
check_contains "TC-1: launch cmd → send 로그에 cmd 포함" "echo HELLO" "$send_log"

# ----------------------------------------------------------------
# TC-2: launch (no cmd, warmup 활성) → cmd send 호출 없음
# send-key Enter (warmup) 은 허용 — "send " 로그만 확인
STATE_FILE="$TMP/state2.json"
> "$STATE_FILE"
CALLS="$TMP/calls2.log"
> "$CALLS"

CMUX_BIN="$TMP/cmux" \
  CMUX_WORKSPACE_ID="ws:test" \
  CBP_STATE_FILE="$STATE_FILE" \
  CMUX_CALLS="$CALLS" \
  CBP_WARMUP_SLEEP=0 \
  CBP_LAUNCH_VERIFY_TRIES=1 \
  bash "$SCRIPT" launch 2>/dev/null

send_log=$(grep "^send " "$CALLS" 2>/dev/null || true)
# cmd send 가 없으므로 "send " 라인 자체가 없어야 함
check "TC-2: launch no-cmd → send 호출 없음" "" "$send_log"

# ----------------------------------------------------------------
# TC-3: CBP_DISABLE_WARMUP=1 + cmd → early-return 경로에서도 send 에 cmd 포함
STATE_FILE="$TMP/state3.json"
> "$STATE_FILE"
CALLS="$TMP/calls3.log"
> "$CALLS"

CMUX_BIN="$TMP/cmux" \
  CMUX_WORKSPACE_ID="ws:test" \
  CBP_STATE_FILE="$STATE_FILE" \
  CMUX_CALLS="$CALLS" \
  CBP_DISABLE_WARMUP=1 \
  bash "$SCRIPT" launch "echo HELLO" 2>/dev/null

send_log=$(grep "^send " "$CALLS" 2>/dev/null || true)
check_contains "TC-3: DISABLE_WARMUP + cmd → send 에 cmd 포함" "echo HELLO" "$send_log"

# ----------------------------------------------------------------
# TC-4: CBP_DISABLE_WARMUP=1 + no cmd → send 없음
STATE_FILE="$TMP/state4.json"
> "$STATE_FILE"
CALLS="$TMP/calls4.log"
> "$CALLS"

CMUX_BIN="$TMP/cmux" \
  CMUX_WORKSPACE_ID="ws:test" \
  CBP_STATE_FILE="$STATE_FILE" \
  CMUX_CALLS="$CALLS" \
  CBP_DISABLE_WARMUP=1 \
  bash "$SCRIPT" launch 2>/dev/null

send_log=$(grep "^send " "$CALLS" 2>/dev/null || true)
check "TC-4: DISABLE_WARMUP + no-cmd → send 없음" "" "$send_log"

echo ""
echo "ok: $pass/$total passed"
[ "$fail_count" -gt 0 ] && exit 1
exit 0
