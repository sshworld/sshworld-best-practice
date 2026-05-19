#!/usr/bin/env bash
# detect_pane_env.sh — scripts/detect-pane-env.sh 회귀 테스트
# 우선순위 검증: TMUX → CMUX_*ID/SOCKET → SOCKET_PASSWORD → cmux ping → default
#
# 사용: bash tests/detect_pane_env.sh
# 종료: 모두 PASS → exit 0 (stdout: PASS), 1건 이상 FAIL → exit 1 (stderr: FAIL 상세)

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO/scripts/detect-pane-env.sh"

# ---------------------------------------------------------------------------
# 헬퍼
# ---------------------------------------------------------------------------

step() { printf "[%s] %s\n" "$1" "$2"; }

fail() {
  local case_name="$1" expected="$2" got="$3"
  printf "FAIL: case=%s, expected=%s, got=%s\n" "$case_name" "$expected" "$got" >&2
  exit 1
}

run_case() {
  # run_case <env_pairs...> -- <script>
  # 아래와 같이 env 배열을 받아 clean 환경에서 실행 후 stdout 반환
  local result
  result="$("$@")"
  printf "%s" "$result"
}

assert_eq() {
  local case_name="$1" expected="$2" got="$3"
  if [ "$got" != "$expected" ]; then
    fail "$case_name" "$expected" "$got"
  fi
}

# ---------------------------------------------------------------------------
# 사전 조건
# ---------------------------------------------------------------------------

[ -f "$SCRIPT" ] || { echo "FAIL: script not found: $SCRIPT" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Case TMUX: TMUX 환경변수 set → tmux 출력
# ---------------------------------------------------------------------------

step "TMUX" "TMUX set → expect 'tmux'"

got=$(
  env -i \
    HOME="${HOME:-/tmp}" \
    PATH="$PATH" \
    TMUX=/tmp/tmux-mock-socket \
    CMUX_BIN=/bin/false \
    bash "$SCRIPT"
)
assert_eq "TMUX" "tmux" "$got"

# ---------------------------------------------------------------------------
# Case CMUX: CMUX_WORKSPACE_ID set (TMUX unset) → cmux 출력
# ---------------------------------------------------------------------------

step "CMUX" "CMUX_WORKSPACE_ID set, TMUX unset → expect 'cmux'"

got=$(
  env -i \
    HOME="${HOME:-/tmp}" \
    PATH="$PATH" \
    CMUX_WORKSPACE_ID=ws-1 \
    CMUX_BIN=/bin/false \
    bash "$SCRIPT"
)
assert_eq "CMUX" "cmux" "$got"

# ---------------------------------------------------------------------------
# Case Default: TMUX / CMUX_* 모두 unset, CMUX_BIN=/bin/false(ping 실패) → default
# ---------------------------------------------------------------------------

step "Default" "all unset, CMUX_BIN=/bin/false → expect 'default'"

got=$(
  env -i \
    HOME="${HOME:-/tmp}" \
    PATH="$PATH" \
    CMUX_BIN=/bin/false \
    bash "$SCRIPT"
)
assert_eq "Default" "default" "$got"

# ---------------------------------------------------------------------------
# 전체 통과
# ---------------------------------------------------------------------------

echo "PASS"
