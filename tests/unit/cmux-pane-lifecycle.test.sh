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

# state file for surface kill tests
STATE_LIFECYCLE="/tmp/test-A2-lifecycle-$$.state"
# state file for A3 send/capture/list/cleanup tests
STATE_A3="/tmp/test-A3-$$.state"
trap 'rm -f "$STATE_LIFECYCLE" "$STATE_A3"' EXIT

total=21

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

# ----------------------------------------------------------------
# 11. kill --pane=surface:9 (FORCE_SELF_KILL=1) → close-surface --surface surface:9
result=$(CMUX_BIN=echo FORCE_SELF_KILL=1 \
  CBP_STATE_FILE="$STATE_LIFECYCLE" \
  bash "$SCRIPT" kill --pane=surface:9 2>/dev/null)
check_contains "kill surface ref: close-surface --surface surface:9" \
  "close-surface --surface surface:9" "$result"

# 12. kill surface ref 는 close-workspace 호출 안 함
check_not_contains "kill surface ref: close-workspace 미호출" \
  "close-workspace" "$result"

# 13. kill surface ref → self surface 거부 (CMUX_SURFACE_ID match, FORCE_SELF_KILL 미설정)
exit_code=0
CMUX_BIN=echo CMUX_SURFACE_ID="surface:7" \
  bash "$SCRIPT" kill --pane=surface:7 2>/dev/null || exit_code=$?
check "kill self surface (CMUX_SURFACE_ID match) → exit 2 거부" "2" "$exit_code"

# ----------------------------------------------------------------
# A3: send --pane=surface:N → --surface dispatch
# CMUX_BIN=echo 이므로 echo 가 인자를 그대로 출력 → stdout 에 "send --surface surface:9" 포함
result=$(CMUX_BIN=echo bash "$SCRIPT" send "hello" --pane=surface:9 2>/dev/null)
check_contains "A3 send surface: --surface surface:9 포함" \
  "send --surface surface:9" "$result"

# 15. send --pane=workspace:N → 기존 --workspace (회귀)
result=$(CMUX_BIN=echo bash "$SCRIPT" send "hello" --pane=workspace:1 2>/dev/null)
check_contains "A3 send workspace: --workspace workspace:1 포함 (회귀)" \
  "send --workspace workspace:1" "$result"

# ----------------------------------------------------------------
# A3: capture --pane=surface:N → --surface dispatch
result=$(CMUX_BIN=echo bash "$SCRIPT" capture --pane=surface:9 2>/dev/null)
check_contains "A3 capture surface: read-screen --surface surface:9 포함" \
  "read-screen --surface surface:9" "$result"

# 17. capture --pane=workspace:N → 기존 --workspace (회귀)
result=$(CMUX_BIN=echo bash "$SCRIPT" capture --pane=workspace:1 2>/dev/null)
check_contains "A3 capture workspace: read-screen --workspace workspace:1 포함 (회귀)" \
  "read-screen --workspace workspace:1" "$result"

# ----------------------------------------------------------------
# A3: list state-aware — state file 에 두 surface → JSON 에 둘 다 포함
# CBP_STATE_FILE 에 surface:1, surface:2 등록 후 list
printf 'surface=surface:1|name=cbp-aaa|ts=1000|ws=workspace:1\n' > "$STATE_A3"
printf 'surface=surface:2|name=cbp-bbb|ts=1001|ws=workspace:1\n' >> "$STATE_A3"
result=$(CMUX_BIN=echo \
  CMUX_WORKSPACE_ID="workspace:1" \
  CBP_STATE_FILE="$STATE_A3" \
  bash "$SCRIPT" list 2>/dev/null)
check_contains "A3 list state-aware: surface:1 포함" '"id":"surface:1"' "$result"
check_contains "A3 list state-aware: surface:2 포함" '"id":"surface:2"' "$result"

# ----------------------------------------------------------------
# A3: cleanup state-aware — state 에 surface:1, CMUX_FAKE_SELF_SURFACE 미설정
# close-surface --surface surface:1 호출 + state 비워짐
printf 'surface=surface:1|name=cbp-ccc|ts=1000|ws=workspace:1\n' > "$STATE_A3"
result=$(CMUX_BIN=echo \
  CMUX_WORKSPACE_ID="workspace:1" \
  CBP_STATE_FILE="$STATE_A3" \
  CMUX_SURFACE_ID="" \
  bash "$SCRIPT" cleanup 2>/dev/null)
check_contains "A3 cleanup state-aware: close-surface surface:1 호출" \
  "close-surface --surface surface:1" "$result"
# state 비워졌는지 확인
state_lines=$(wc -l < "$STATE_A3" 2>/dev/null | tr -d ' ')
check "A3 cleanup state-aware: state 파일 비워짐" "0" "$state_lines"

echo ""
echo "ok: $pass/$total passed"
[ "$fail_count" -gt 0 ] && exit 1
exit 0
