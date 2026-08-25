#!/usr/bin/env bash
# detect-pane-env.sh — 터미널 멀티플렉서 환경 감지.
# stdout 한 줄: tmux | cmux | orca | default
#
# 우선순위:
#   1. TMUX env 가 set                                              → tmux
#   2. CMUX_WORKSPACE_ID || CMUX_SURFACE_ID || CMUX_SOCKET set      → cmux  (실제 cmux surface 안 신호)
#   3. CMUX_SOCKET_PASSWORD set                                     → cmux  (구버전 호환)
#   4. ORCA_TERMINAL_HANDLE || ORCA_WORKSPACE_ID set,
#      또는 TERM_PROGRAM 이 정확히 "Orca"                            → orca  (실제 orca surface 안 신호)
#   5. "$CMUX_BIN" ping 성공                                        → cmux
#   6. "$ORCA_BIN" status 성공                                      → orca
#   7. 그 외                                                        → default
#
# 환경변수:
#   CMUX_BIN  — cmux 바이너리 경로 (미지정 시 PATH 의 cmux)
#   ORCA_BIN  — orca 바이너리 경로 (미지정 시 PATH 의 orca)
#
# 참고: CMUX_WORKSPACE_ID / CMUX_SURFACE_ID / CMUX_SOCKET 은 cmux 가 셸에 주입하는 변수.
#       CMUX_SOCKET_PASSWORD 는 구버전 cmux 또는 특정 환경에서만 주입 → 후순위.
#       ORCA_TERMINAL_HANDLE / ORCA_WORKSPACE_ID 는 orca 가 셸에 주입하는 변수 —
#       cmux 주입 변수와 동급의 직접 증거이므로 cmux 바로 다음, 두 ping/status
#       probe 보다 앞에 온다. TERM_PROGRAM 은 다른 터미널도 설정하므로 정확히
#       "Orca" 값일 때만 인정 (substring 매치 금지).
#       두 probe(ping/status) 는 외부 셸에서도 성공하므로 가장 후순위 — cmux 가
#       먼저인 이유는 기존 동작을 그대로 보존하기 위함.

set -uo pipefail

detect_pane_env() {
  local cmux_bin="${CMUX_BIN:-cmux}"
  local orca_bin="${ORCA_BIN:-orca}"

  # 1. tmux 세션 내부
  if [ -n "${TMUX:-}" ]; then
    echo "tmux"
    return 0
  fi

  # 2. cmux 가 주입하는 surface 식별 변수 — 셸이 실제로 cmux surface 안에 있다는 신호
  if [ -n "${CMUX_WORKSPACE_ID:-}" ] || [ -n "${CMUX_SURFACE_ID:-}" ] || [ -n "${CMUX_SOCKET:-}" ]; then
    echo "cmux"
    return 0
  fi

  # 3. cmux 소켓 password 환경변수 (구버전 호환)
  if [ -n "${CMUX_SOCKET_PASSWORD:-}" ]; then
    echo "cmux"
    return 0
  fi

  # 4. orca 가 주입하는 surface 식별 변수 — 셸이 실제로 orca surface 안에 있다는 신호
  if [ -n "${ORCA_TERMINAL_HANDLE:-}" ] || [ -n "${ORCA_WORKSPACE_ID:-}" ] || [ "${TERM_PROGRAM:-}" = "Orca" ]; then
    echo "orca"
    return 0
  fi

  # 5. cmux ping 성공
  if "$cmux_bin" ping >/dev/null 2>&1; then
    echo "cmux"
    return 0
  fi

  # 6. orca status 성공
  if "$orca_bin" status >/dev/null 2>&1; then
    echo "orca"
    return 0
  fi

  echo "default"
}

# Sourcing guard — source 시 함수만 노출, 직접 실행 시 main
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  detect_pane_env
fi
