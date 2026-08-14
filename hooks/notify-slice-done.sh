#!/usr/bin/env bash
# Stop hook — cmux dispatch 자식(별도 claude 인스턴스) 작업 완료 시
# (a) cmux notify 패널로 즉시 알리고 (b) done-marker 파일을 남겨
# 부모 reap 이 fast-path 신호로 쓰게 한다.
#
# done-marker 계약 (reap fast-path / reap-on-stop 과 공유 — 경로 변경 금지):
#   경로: <git-common-dir>/cbp-slice-done-<branch sanitized: / → _>
#   line1: surface ref — dispatch 가 자식 셸에 주입한 $CBP_SELF_PANE(surface:N, 정확한
#          wrapper-namespace ref) 우선, 없으면 $CMUX_SURFACE_ID 폴백(cmux 실측 UUID 일 수
#          있음 — wrapper 의 UUID --surface 라우팅이 belt 로 커버). 둘 다 unset 이면 빈 줄.
#   line2: $CMUX_WORKSPACE_ID — 타 cmux workspace 의 부모가 같은 marker 를
#          오사용(reap)하는 것을 막는 가드. 소비 측(_cbp_find_done_marker)이
#          line2 존재 && 자기 CMUX_WORKSPACE_ID 와 다르면 skip.
#
# 우회: SKIP_SLICE_DONE_NOTIFY=1 (1회) / DISABLE_SLICE_DONE_NOTIFY=1 (영구)
# 비-dispatch worktree 오발화 차단 escape: CBP_NOTIFY_ANY_WORKTREE=1
#
# 어떤 실패도 세션을 막지 않음 — 모든 경로 exit 0.
set -u

[ "${DISABLE_SLICE_DONE_NOTIFY:-0}" = "1" ] && exit 0
[ "${SKIP_SLICE_DONE_NOTIFY:-0}" = "1" ] && exit 0

# 게이트 1 — 비-cmux 는 통지 대상이 없다. 이것만 남긴다.
if [ -z "${CMUX_WORKSPACE_ID:-}" ]; then
  [ "${CBP_NOTIFY_DEBUG:-0}" = "1" ] && echo "notify-slice-done: skip — CMUX_WORKSPACE_ID 없음" >&2
  exit 0
fi

# ⚠️ 여기 있던 git 게이트 3개(비-git / GIT_DIR==GIT_COMMON / TOPLEVEL 이
# */.worktrees/* 아님)를 제거했다. 그 셋 때문에 marker 가 **linked worktree
# 안에서만** 기록됐고, 비-git·일반 체크아웃에서는 조용히 아무것도 안 남아
# reap fast-path·reap-on-stop·wait-idle 폴백이 동시에 죽었다.
# 경로 계산은 writer/reader 공용 리졸버로 단일화한다.
# dirname 등 외부 명령을 쓰지 않는다 — PATH 가 최소화된 환경(jq 부재 테스트 등)에서
# 경로 계산이 깨져 훅 전체가 조용히 죽는다.
_RESOLVER="${BASH_SOURCE[0]%/*}/../scripts/cbp-marker-path.sh"
if [ -r "$_RESOLVER" ]; then
  # shellcheck source=/dev/null
  . "$_RESOLVER"
else
  [ "${CBP_NOTIFY_DEBUG:-0}" = "1" ] && echo "notify-slice-done: skip — 리졸버 없음: $_RESOLVER" >&2
  exit 0
fi

payload=$(cat)

JQ_OK=1
command -v jq >/dev/null 2>&1 || JQ_OK=0

verdict=""
if [ "$JQ_OK" = "1" ]; then
  transcript=$(printf '%s' "$payload" | jq -r '.transcript_path // empty' 2>/dev/null)
  if [ -n "$transcript" ] && [ -f "$transcript" ]; then
    # 마지막 비-tool_result user 줄 (token-stats.sh 와 동일 패턴) 이후 assistant 텍스트만 판정 대상.
    last_user_line=$(grep -n '"type":"user"' "$transcript" 2>/dev/null | grep -v 'tool_use_id' | tail -1 | cut -d: -f1)
    last_user_line=${last_user_line:-1}
    texts=$(tail -n +"$((last_user_line + 1))" "$transcript" 2>/dev/null \
      | jq -r 'select(.type=="assistant") | (.message.content // [])[]? | select(.type=="text") | .text' 2>/dev/null)
    if [ -n "$texts" ]; then
      # 마지막 매치 우선 — ✅/❌ 가 둘 다 등장하면 텍스트 상 더 늦게 나온 쪽 채택.
      verdict=$(printf '%s\n' "$texts" | grep -o '[✅❌]' | tail -1)
    fi
  fi
fi

branch=$(git branch --show-current 2>/dev/null)

case "$verdict" in
  '✅') title="✅ ${branch} 완료" ;;
  '❌') title="❌ ${branch} 실패" ;;
  *)    title="🔔 ${branch} turn 종료" ;;
esac

if ! "${CMUX_BIN:-cmux}" notify --title "$title" --workspace "$CMUX_WORKSPACE_ID" >/dev/null 2>&1; then
  echo "notify-slice-done: cmux notify 실패 (우회: DISABLE_SLICE_DONE_NOTIFY=1)" >&2
fi

if [ "$verdict" = "✅" ] || [ "$verdict" = "❌" ]; then
  marker_dir=$(cbp_marker_dir)
  if [ -n "$marker_dir" ] && [ -d "$marker_dir" ]; then
    # 접미사 키: git 이면 branch, 비-git 이면 surface ref 폴백 (비-git 엔 branch 가 없다)
    marker_key=$(cbp_marker_key)
    marker="${marker_dir}/cbp-slice-done-${marker_key}"
    printf '%s\n%s\n' "${CBP_SELF_PANE:-${CMUX_SURFACE_ID:-}}" "${CMUX_WORKSPACE_ID}" > "$marker" 2>/dev/null || true
    [ "${CBP_NOTIFY_DEBUG:-0}" = "1" ] && echo "notify-slice-done: marker=$marker" >&2
  else
    [ "${CBP_NOTIFY_DEBUG:-0}" = "1" ] && echo "notify-slice-done: marker dir 해석 실패" >&2
  fi
fi

exit 0
