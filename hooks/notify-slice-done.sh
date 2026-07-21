#!/usr/bin/env bash
# Stop hook — cmux dispatch 자식(별도 claude 인스턴스) 작업 완료 시
# (a) cmux notify 패널로 즉시 알리고 (b) done-marker 파일을 남겨
# 부모 reap 이 fast-path 신호로 쓰게 한다.
#
# done-marker 계약 (reap fast-path / reap-on-stop 과 공유 — 경로 변경 금지):
#   경로: <git-common-dir>/cbp-slice-done-<branch sanitized: / → _>
#   line1: $CMUX_SURFACE_ID (unset 이면 빈 줄)
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

[ -z "${CMUX_WORKSPACE_ID:-}" ] && exit 0

GIT_DIR=$(git rev-parse --git-dir 2>/dev/null) || exit 0
GIT_COMMON=$(git rev-parse --git-common-dir 2>/dev/null) || exit 0
[ "$GIT_DIR" = "$GIT_COMMON" ] && exit 0

TOPLEVEL=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
case "$TOPLEVEL" in
  */.worktrees/*) ;;
  *)
    [ "${CBP_NOTIFY_ANY_WORKTREE:-0}" = "1" ] || exit 0
    ;;
esac

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
  common_abs=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
  [ -n "$common_abs" ] || common_abs=$(cd "$GIT_COMMON" 2>/dev/null && pwd)
  if [ -n "$common_abs" ]; then
    branch_sanitized=$(printf '%s' "$branch" | tr '/' '_')
    marker="${common_abs}/cbp-slice-done-${branch_sanitized}"
    printf '%s\n%s\n' "${CMUX_SURFACE_ID:-}" "${CMUX_WORKSPACE_ID}" > "$marker" 2>/dev/null || true
  fi
fi

exit 0
