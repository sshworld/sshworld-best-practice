#!/usr/bin/env bash
# detect_pane_env.sh — scripts/detect-pane-env.sh 회귀 테스트 (cmux/tmux 경로)
# 우선순위 검증: TMUX → CMUX_*ID/SOCKET → SOCKET_PASSWORD → orca 신호 → cmux ping → orca status → default
# orca 경로 자체의 케이스는 tests/detect_pane_env_orca.sh 참조.
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
# Case Default: TMUX / CMUX_* 모두 unset, 두 probe(cmux ping / orca status) 모두
# 실패하도록 CMUX_BIN=/bin/false + ORCA_BIN=/bin/false → default
#
# env -i 로 클린 환경이라 ORCA_TERMINAL_HANDLE / ORCA_WORKSPACE_ID / TERM_PROGRAM
# 은 이미 안 새어 들어온다 — 남는 구멍은 ORCA_BIN 미지정 시 PATH 의 실제 orca
# 바이너리가 "orca status" 에 성공해버리는 것뿐이라 ORCA_BIN 도 함께 차단한다.
# ---------------------------------------------------------------------------

step "Default" "all unset, CMUX_BIN/ORCA_BIN=/bin/false → expect 'default'"

got=$(
  env -i \
    HOME="${HOME:-/tmp}" \
    PATH="$PATH" \
    CMUX_BIN=/bin/false \
    ORCA_BIN=/bin/false \
    bash "$SCRIPT"
)
assert_eq "Default" "default" "$got"

# ---------------------------------------------------------------------------
# 전체 통과
# ---------------------------------------------------------------------------

echo "PASS"
