#!/usr/bin/env bash
# Stop hook (부모 세션 전용) — turn 경계마다 done-marker(cbp-slice-done-*) 를 소비해
# 완료된 cmux 자식 surface 를 자동 reap. notify-slice-done 이 남긴 신호를 부모가
# 감시 루프 없이도 소비하게 한다.
#
# marker 계약 (fast-path 와 공유 — 경로/내용 변경 금지):
#   경로: <git-common-dir>/cbp-slice-done-<branch sanitized: / → _>
#   line1: 자식 $CMUX_SURFACE_ID (빈 값이면 skip)
#   line2: 자식 $CMUX_WORKSPACE_ID (있으면 자기 ws 와 다를 때 skip — 타 workspace 오사용 방지,
#          없으면(구버전 1줄 marker) 기존 동작 유지)
#
# 우회: SKIP_REAP_ON_STOP=1 (1회) / DISABLE_REAP_ON_STOP=1 (영구)
# 어떤 실패도 세션을 막지 않음 — 모든 경로 exit 0.
set -u

[ "${DISABLE_REAP_ON_STOP:-0}" = "1" ] && exit 0
[ "${SKIP_REAP_ON_STOP:-0}" = "1" ] && exit 0

[ -z "${CMUX_WORKSPACE_ID:-}" ] && exit 0

GIT_DIR=$(git rev-parse --git-dir 2>/dev/null) || exit 0
GIT_COMMON=$(git rev-parse --git-common-dir 2>/dev/null) || exit 0
# 자식 worktree 세션은 제외 — 이 hook 은 부모(원본 repo dir)에서만 동작한다.
[ "$GIT_DIR" != "$GIT_COMMON" ] && exit 0

COMMON_ABS=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
[ -n "$COMMON_ABS" ] || COMMON_ABS=$(cd "$GIT_COMMON" 2>/dev/null && pwd)
[ -n "$COMMON_ABS" ] || exit 0

shopt -s nullglob
markers=("$COMMON_ABS"/cbp-slice-done-*)
shopt -u nullglob
[ "${#markers[@]}" -eq 0 ] && exit 0

PANE_BIN="${CBP_PANE_BIN:-$(dirname "${BASH_SOURCE[0]}")/../scripts/cmux-pane.sh}"

reaped_list=()
pending_list=()
count=0

for marker in "${markers[@]}"; do
  [ -f "$marker" ] || continue
  [ "$count" -ge 5 ] && break

  ref=$(sed -n '1p' "$marker" 2>/dev/null)
  [ -z "$ref" ] && continue

  ws=$(sed -n '2p' "$marker" 2>/dev/null)
  if [ -n "$ws" ] && [ "$ws" != "${CMUX_WORKSPACE_ID:-}" ]; then
    continue
  fi

  [ "$ref" = "${CMUX_SURFACE_ID:-}" ] && continue

  count=$((count + 1))

  # stdout/stderr 전량 캡처 필수 — reap 은 화면 덤프를 stdout 에 찍으므로 캡처 없이
  # 두면 hook stdout 이 오염돼 아래 systemMessage JSON 출력이 깨진다.
  out=$(CBP_REAP_FAST_CHECK=1 "$PANE_BIN" reap --pane="$ref" --idle=2 --timeout=15 2>&1)

  # "^reaped " 매치 우선 — done-marker 가 pending 을 trump 한 경우
  # ("reaped ... (pending-input 무시: <텍스트>)") 가 아래 input-pending 검사에
  # 오분류(보류로 잘못 판정)되는 것을 방지. annotation 이 있으면 추출해 그대로 병기.
  reaped_line=$(printf '%s\n' "$out" | grep '^reaped ' | tail -1)
  if [ -n "$reaped_line" ]; then
    annot=$(printf '%s\n' "$reaped_line" | grep -oE '\(pending-input 무시:[^)]*\)')
    if [ -n "$annot" ]; then
      reaped_list+=("$ref $annot")
    else
      reaped_list+=("$ref")
    fi
  elif printf '%s\n' "$out" | grep -q 'input-pending'; then
    pending_list+=("$ref")
  elif printf '%s\n' "$out" | grep -qE '(^|[^[:alnum:]])(reaped|died) '; then
    reaped_list+=("$ref")
  fi
  # not done — kept: 무동작, marker 는 다음 turn 재시도 대상으로 남는다.
done

command -v jq >/dev/null 2>&1 || exit 0
[ "${#reaped_list[@]}" -eq 0 ] && [ "${#pending_list[@]}" -eq 0 ] && exit 0

parts=()
for r in "${reaped_list[@]:-}"; do
  [ -z "$r" ] && continue
  parts+=("reaped $r")
done
for p in "${pending_list[@]:-}"; do
  [ -z "$p" ] && continue
  parts+=("⏸ input-pending — $p 보류 (CBP_REAP_IGNORE_PENDING=1 로 강제 회수)")
done

joined=$(IFS=', '; echo "${parts[*]}")
msg="♻️ reap-on-stop: ${joined}"

jq -nc --arg m "$msg" '{systemMessage: $m}'

exit 0
