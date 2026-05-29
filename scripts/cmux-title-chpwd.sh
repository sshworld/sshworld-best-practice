#!/usr/bin/env bash
# cmux-title-chpwd.sh — cd 할 때마다 cmux surface title 을 cwd basename 으로 자동 설정.
#
# 목적: cmux 사이드바 workspace 목록에서 각 surface 가 어느 디렉토리에서 작업 중인지
#       title 만 보고 식별. cmux 자체엔 cwd→title 자동 기능 없음 → zsh chpwd hook 으로 구현.
#
# 사용 (zsh ~/.zshrc):
#   source ~/scripts/cmux-title-chpwd.sh
#   → cd 마다 cmux rename-tab --surface $CMUX_SURFACE_ID <basename PWD>
#
# 동작:
#   - cmux 환경(CMUX_SURFACE_ID set)일 때만 rename. 비-cmux 셸(tmux/일반 터미널) no-op.
#   - rename-tab 실패는 무시 (cd 흐름 절대 안 깨짐).
#
# 환경변수:
#   CMUX_BIN  — cmux 바이너리 경로 (미지정 시 PATH 의 cmux). 테스트 mock 용.

# chpwd hook 본체 — 현재 surface title 을 cwd basename 으로.
_cmux_title_chpwd() {
  [ -n "${CMUX_SURFACE_ID:-}" ] || return 0
  "${CMUX_BIN:-cmux}" rename-tab --surface "$CMUX_SURFACE_ID" "$(basename "$PWD")" >/dev/null 2>&1 || true
}

# zsh 인터랙티브 셸에서 source 시: chpwd hook 등록 + 초기 1회 반영.
# 직접 실행(bash script.sh) 시: 1회 rename 후 종료 (manual/테스트).
if [ -n "${ZSH_VERSION:-}" ]; then
  # zsh — source 된 경우 hook 등록
  autoload -Uz add-zsh-hook 2>/dev/null
  add-zsh-hook chpwd _cmux_title_chpwd 2>/dev/null
  # 셸 시작 시점 현재 cwd 즉시 반영
  _cmux_title_chpwd
else
  # bash/sh 직접 실행 — 1회 rename (sourcing guard)
  if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
    _cmux_title_chpwd
  fi
fi
