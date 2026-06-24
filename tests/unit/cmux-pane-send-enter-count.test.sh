#!/usr/bin/env bash
# cmux-pane-send-enter-count.test.sh — do_send 의 --enter-count 옵션 검증
#
# 환경변수 mock:
#   CMUX_BIN=echo  — cmux CLI mock (서브커맨드를 echo 로 출력)

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

[ -f "$SCRIPT" ] || { echo "FAIL: $SCRIPT 없음" >&2; exit 1; }

total=3

# ----------------------------------------------------------------
# 1. --enter-count=3 → echo 호출 4번 (1 send + 3 send-key Enter)
# CMUX_BIN=echo 이면 각 cmux 호출이 인자를 stdout 에 한 줄씩 출력
# CBP_SEND_CONFIRM=0: confirm 재시도 loop 비활성화 (enter-count 만 집계)
result=$(CMUX_BIN=echo CBP_SEND_CONFIRM=0 bash "$SCRIPT" send "hello" --pane=workspace:1 --enter-count=3 2>/dev/null)
line_count=$(echo "$result" | wc -l | tr -d ' ')
check "--enter-count=3: echo 호출 4회" "4" "$line_count"

# ----------------------------------------------------------------
# 2. --enter-count=0 → echo 호출 1번 (send 만, send-key 없음)
result=$(CMUX_BIN=echo CBP_SEND_CONFIRM=0 bash "$SCRIPT" send "hello" --pane=workspace:1 --enter-count=0 2>/dev/null)
line_count=$(echo "$result" | wc -l | tr -d ' ')
check "--enter-count=0: echo 호출 1회 (send-key 없음)" "1" "$line_count"

# ----------------------------------------------------------------
# 3. --enter-count 미지정 → echo 호출 2번 (1 send + 1 Enter, 기존 동작)
result=$(CMUX_BIN=echo CBP_SEND_CONFIRM=0 bash "$SCRIPT" send "hello" --pane=workspace:1 2>/dev/null)
line_count=$(echo "$result" | wc -l | tr -d ' ')
check "--enter-count 미지정: echo 호출 2회 (기존 동작)" "2" "$line_count"

echo ""
echo "ok: $pass/$total passed"
[ "$fail_count" -gt 0 ] && exit 1
exit 0
