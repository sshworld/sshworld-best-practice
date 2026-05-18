#!/usr/bin/env bash
# detect-pane-env.test.sh — detect_pane_env 순수 함수 4분면 검증

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO/scripts/detect-pane-env.sh"

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

[ -f "$SCRIPT" ] || { echo "FAIL: $SCRIPT 없음" >&2; exit 1; }

total=5

# 1. TMUX set → tmux
result=$(env -i TMUX="/tmp/tmux.sock" bash "$SCRIPT")
check "TMUX=set → tmux" "tmux" "$result"

# 2. CMUX_SOCKET_PASSWORD set → cmux
result=$(env -i CMUX_SOCKET_PASSWORD="secret" bash "$SCRIPT")
check "CMUX_SOCKET_PASSWORD=set → cmux" "cmux" "$result"

# 3. 둘 다 set → tmux 우선
result=$(env -i TMUX="/tmp/tmux.sock" CMUX_SOCKET_PASSWORD="secret" bash "$SCRIPT")
check "TMUX+CMUX_SOCKET_PASSWORD → tmux 우선" "tmux" "$result"

# 4. CMUX_BIN=$(which true) — ping 성공 mock → cmux
TRUE_BIN="$(which true)"
result=$(env -i CMUX_BIN="$TRUE_BIN" bash "$SCRIPT")
check "CMUX_BIN=true (ping 성공) → cmux" "cmux" "$result"

# 5. CMUX_BIN=$(which false) — ping 실패 → default
FALSE_BIN="$(which false)"
result=$(env -i CMUX_BIN="$FALSE_BIN" bash "$SCRIPT")
check "CMUX_BIN=false (ping 실패) → default" "default" "$result"

echo ""
echo "ok: $pass/$total passed"
[ "$fail_count" -gt 0 ] && exit 1
exit 0
