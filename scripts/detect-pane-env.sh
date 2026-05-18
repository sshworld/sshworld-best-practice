#!/usr/bin/env bash
# detect-pane-env.sh — 터미널 멀티플렉서 환경 감지.
# stdout 한 줄: tmux | cmux | default
#
# 우선순위:
#   1. TMUX env 가 set           → tmux
#   2. CMUX_SOCKET_PASSWORD set  → cmux
#   3. "$CMUX_BIN" ping 성공     → cmux
#   4. 그 외                     → default
#
# 환경변수:
#   CMUX_BIN  — cmux 바이너리 경로 (미지정 시 PATH 의 cmux)

set -uo pipefail

detect_pane_env() {
  local cmux_bin="${CMUX_BIN:-cmux}"

  # 1. tmux 세션 내부
  if [ -n "${TMUX:-}" ]; then
    echo "tmux"
    return 0
  fi

  # 2. cmux 소켓 password 환경변수
  if [ -n "${CMUX_SOCKET_PASSWORD:-}" ]; then
    echo "cmux"
    return 0
  fi

  # 3. cmux ping 성공
  if "$cmux_bin" ping >/dev/null 2>&1; then
    echo "cmux"
    return 0
  fi

  echo "default"
}

# Sourcing guard — source 시 함수만 노출, 직접 실행 시 main
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  detect_pane_env
fi
