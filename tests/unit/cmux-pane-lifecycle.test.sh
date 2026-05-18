#!/usr/bin/env bash
# cmux-pane-lifecycle.test.sh — cmux-pane.sh kill/list/cleanup/status 명령 검증
#
# 환경변수 mock:
#   CMUX_BIN=echo          — cmux CLI mock (서브커맨드를 echo 로 출력)
#   CBP_LIST_LINES         — list 명령의 입력 mock (테스트용 hook)
#   CLAUDE_FAKE_SELF_CMUX_WS — cleanup 에서 "자기 workspace" 를 mock

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
  if echo "$actual" | grep -qF -- "$expected"; then
    echo "ok: $desc"
    pass=$((pass + 1))
  else
    echo "FAIL: $desc — expected substring='$expected' in output='$actual'" >&2
    fail_count=$((fail_count + 1))
  fi
}

check_not_contains() {
  local desc="$1" not_expected="$2" actual="$3"
  if echo "$actual" | grep -qF -- "$not_expected"; then
    echo "FAIL: $desc — unexpected substring='$not_expected' found in output='$actual'" >&2
    fail_count=$((fail_count + 1))
  else
    echo "ok: $desc"
    pass=$((pass + 1))
  fi
}

[ -f "$SCRIPT" ] || { echo "FAIL: $SCRIPT 없음" >&2; exit 1; }

total=10

# ----------------------------------------------------------------
# 1. kill --pane=workspace:9 (FORCE_SELF_KILL=1) → close-workspace --workspace workspace:9 호출
# CMUX_BIN=echo 이므로 echo 가 인자를 그대로 출력 → stdout 에 close-workspace 포함
result=$(CMUX_BIN=echo FORCE_SELF_KILL=1 bash "$SCRIPT" kill --pane=workspace:9 2>/dev/null)
check_contains "kill FORCE_SELF_KILL: close-workspace --workspace workspace:9" \
  "close-workspace --workspace workspace:9" "$result"

# ----------------------------------------------------------------
# 2. kill --pane= 없음 → exit 2
exit_code=0
CMUX_BIN=echo bash "$SCRIPT" kill 2>/dev/null || exit_code=$?
check "kill without --pane → exit 2" "2" "$exit_code"

# ----------------------------------------------------------------
# 3. list (CBP_LIST_LINES mock) → cbp- prefix 만 JSON 출력
# mock 입력: "cbp-foo workspace:1\nother workspace:2\ncbp-bar workspace:3"
# 기대: cbp-foo 와 cbp-bar 만 JSON 에 포함, other 는 제외
LIST_MOCK="cbp-foo workspace:1
other workspace:2
cbp-bar workspace:3"

result=$(CMUX_BIN=echo CBP_LIST_LINES="$LIST_MOCK" bash "$SCRIPT" list 2>/dev/null)
check_contains "list: cbp-foo 포함" '"name":"cbp-foo"' "$result"
check_contains "list: cbp-bar 포함" '"name":"cbp-bar"' "$result"
check_not_contains "list: other 제외" '"name":"other"' "$result"

# ----------------------------------------------------------------
# 4. cleanup (mock list 동일, CLAUDE_FAKE_SELF_CMUX_WS=workspace:1)
# close-workspace 호출이 cbp-bar (workspace:3) 에 대해 발생해야 함
# cbp-foo (workspace:1) 는 자기 workspace 로 mock → 보존 (close 안 됨)
result=$(CMUX_BIN=echo CBP_LIST_LINES="$LIST_MOCK" \
  CLAUDE_FAKE_SELF_CMUX_WS="workspace:1" \
  bash "$SCRIPT" cleanup 2>/dev/null)
check_contains "cleanup: cbp-bar close-workspace 호출" "close-workspace --workspace workspace:3" "$result"
check_not_contains "cleanup: cbp-foo (self) 는 close 안 함" "close-workspace --workspace workspace:1" "$result"

# ----------------------------------------------------------------
# 5. cleanup stderr → "cleaning N cmux workspace(s)" 메시지 포함
stderr_msg=$(CMUX_BIN=echo CBP_LIST_LINES="$LIST_MOCK" \
  CLAUDE_FAKE_SELF_CMUX_WS="workspace:1" \
  bash "$SCRIPT" cleanup 2>&1 >/dev/null)
check_contains "cleanup: stderr 'cleaning' 메시지" "cleaning" "$stderr_msg"

# ----------------------------------------------------------------
# 6. status — 실행 후 0 exit (CMUX_BIN=echo 환경)
exit_code=99
CMUX_BIN=echo bash "$SCRIPT" status 2>/dev/null && exit_code=0 || exit_code=$?
check "status → exit 0" "0" "$exit_code"

# ----------------------------------------------------------------
# 7. self-kill 거부: FORCE_SELF_KILL 미설정 + 자기 workspace 와 동일 ref
# identify 가 "workspace:42" 를 반환하고 kill --pane=workspace:42 시도 → exit 2 + stderr 안내
# CMUX_FAKE_IDENTIFY env 로 identify 결과 mock (없으면 echo identify 출력 사용)
stderr_out=$(CMUX_BIN=echo CLAUDE_FAKE_SELF_CMUX_WS="" \
  bash "$SCRIPT" kill --pane=workspace:42 2>&1 >/dev/null || true)
# CMUX_BIN=echo 환경에서 identify 는 "identify" 를 출력하므로 자기 식별 비교는 실패
# → self-kill 거부 발동 안 함. 이 테스트는 exit code 0 허용
# 실제 자기 kill 거부는 CLAUDE_FAKE_SELF_CMUX_WS 이용하는 kill 함수 내 로직으로 검증
exit_code=0
CMUX_BIN=echo CLAUDE_FAKE_SELF_CMUX_WS="workspace:99" \
  bash "$SCRIPT" kill --pane=workspace:99 2>/dev/null || exit_code=$?
check "kill self (CLAUDE_FAKE_SELF_CMUX_WS match) → exit 2 거부" "2" "$exit_code"

echo ""
echo "ok: $pass/$total passed"
[ "$fail_count" -gt 0 ] && exit 1
exit 0
