#!/usr/bin/env bash
# cmux-title-chpwd.sh — cd 할 때마다 cmux title 을 cwd basename 으로 자동 설정.
#
# 목적: cmux 왼쪽 사이드바(workspace 목록) + tab 에서 각 작업이 어느 디렉토리인지
#       이름만 보고 식별. cmux 자체엔 cwd→title 자동 기능 없음 → zsh chpwd hook 으로 구현.
#
# 사용 (zsh ~/.zshrc):
#   source ~/scripts/cmux-title-chpwd.sh
#   → cd 마다:
#       cmux rename-tab --surface $CMUX_SURFACE_ID <basename PWD>   (항상 — tab/surface 식별)
#       single-surface workspace 면 추가로
#       cmux workspace-action --action rename --workspace $CMUX_WORKSPACE_ID --title <basename>
#
# 동작:
#   - cmux 환경(CMUX_SURFACE_ID set)일 때만 동작. 비-cmux 셸(tmux/일반 터미널) no-op.
#   - workspace rename 은 **single-surface workspace** 에서만 — surface 가 여러 개면
#     (cmux dispatch grid 등) 각 surface 의 cd 가 부모 workspace title 을 서로 덮어쓰는
#     clobber 방지. multi-surface 면 tab rename 만.
#   - 모든 cmux 호출 실패는 무시 (cd 흐름 절대 안 깨짐). surface 수 판정 실패(≠1) 시
#     workspace rename skip (conservative).
#
# 환경변수:
#   CMUX_BIN  — cmux 바이너리 경로 (미지정 시 PATH 의 cmux). 테스트 mock 용.

# chpwd hook 본체 — 현재 tab(+single-surface 면 workspace) title 을 cwd basename 으로.
_cmux_title_chpwd() {
  [ -n "${CMUX_SURFACE_ID:-}" ] || return 0
  local bin="${CMUX_BIN:-cmux}"
  local title; title="$(basename "$PWD")"
  # tab/surface title 은 항상 갱신.
  "$bin" rename-tab --surface "$CMUX_SURFACE_ID" "$title" >/dev/null 2>&1 || true
  # workspace title 은 single-surface workspace 일 때만 (multi=clobber 방지).
  [ -n "${CMUX_WORKSPACE_ID:-}" ] || return 0
  local n
  n="$("$bin" list-pane-surfaces --workspace "$CMUX_WORKSPACE_ID" 2>/dev/null | grep -c .)"
  [ "$n" = "1" ] || return 0
  "$bin" workspace-action --action rename --workspace "$CMUX_WORKSPACE_ID" --title "$title" >/dev/null 2>&1 || true
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
