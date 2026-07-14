#!/usr/bin/env bash
# plan-dev-progress.sh — plan-dev 진행률 cmux push 헬퍼.
#
# 사용:
#   plan-dev-progress.sh start --total=<n>
#   plan-dev-progress.sh tick [--slug=<slice>]
#   plan-dev-progress.sh show
#
# 환경변수:
#   PLAN_DEV_SESSION_BIN  — plan-dev-session.sh 경로 override (테스트용)
#   CMUX_PANE_BIN         — cmux-pane.sh 경로 override (테스트용)
#   PROGRESS_DRY_RUN      — notify/set-status 단계 dry-run (cmux-pane.sh 가 처리)

set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SESSION_BIN="${PLAN_DEV_SESSION_BIN:-$SELF_DIR/plan-dev-session.sh}"
CMUX_PANE="${CMUX_PANE_BIN:-$SELF_DIR/cmux-pane.sh}"

die() { echo "plan-dev-progress: $*" >&2; exit "${2:-1}"; }

usage() {
  cat >&2 <<'USAGE'
plan-dev-progress.sh <command> [args]

commands:
  start --total=<n>          세션 시작 + status pill 초기화
  tick [--slug=<slice>]      슬라이스 완료 카운트 +1 + pill/알림 갱신
  show                       진행률 표 + cmux 알림 출력
USAGE
  exit 2
}

_is_cmux() {
  local detect_bin="$SELF_DIR/detect-pane-env.sh"
  if [ -x "$detect_bin" ]; then
    local env
    env=$("$detect_bin" 2>/dev/null) || return 1
    [ "$env" = "cmux" ]
  else
    [ -n "${CMUX_WORKSPACE_ID:-}" ]
  fi
}

do_start() {
  local total=0
  for arg in "$@"; do
    case "$arg" in
      --total=*) total="${arg#*=}" ;;
    esac
  done

  "$SESSION_BIN" start --total="$total" || exit $?
  "$CMUX_PANE" set-status plan-dev "0/$total" --icon sparkle
}

do_tick() {
  local slug=""
  for arg in "$@"; do
    case "$arg" in
      --slug=*) slug="${arg#*=}" ;;
    esac
  done

  local tmp_err rc status_value
  tmp_err="$(mktemp)"
  trap 'rm -f "$tmp_err"' EXIT

  status_value=$("$SESSION_BIN" progress --inc 2>"$tmp_err")
  rc=$?

  if [ "$rc" -ne 0 ] || [ -z "$status_value" ]; then
    if grep -q '마커 없음' "$tmp_err"; then
      echo "plan-dev-progress: 마커 없음 — tick skip" >&2
    else
      cat "$tmp_err" >&2
      echo "plan-dev-progress: session progress 실패 — tick skip" >&2
    fi
    exit 0
  fi

  "$CMUX_PANE" set-status plan-dev "$status_value" --icon sparkle

  if [ -n "$slug" ]; then
    "$CMUX_PANE" notify --title "slice ✅ $slug" --body "$status_value"
  fi

  printf '%s\n' "$status_value"
}

do_show() {
  local json
  json=$("$SESSION_BIN" query --json 2>/dev/null) || {
    echo "plan-dev-progress: 마커 없음" >&2
    exit 1
  }

  printf '%s' "$json" | python3 -c "
import json, sys
d = json.load(sys.stdin)
done  = int(d.get('done_slices', 0))
total = int(d.get('total_slices', 0))
pct   = (done * 100 // total) if total > 0 else 0
print('=== plan-dev progress ===')
print('  work_branch  :', d.get('work_branch', ''))
print('  start_ts     :', d.get('start_ts', ''))
print('  total_slices :', total)
print('  done_slices  :', done)
print('  pct          : {}%'.format(pct))
"

  if _is_cmux; then
    echo ""
    echo "=== recent notifications ==="
    local notifs
    notifs=$("${CMUX_BIN:-cmux}" list-notifications 2>/dev/null | tail -5) || notifs=""
    if [ -z "$notifs" ]; then
      echo "  (no notifications)"
    else
      printf '%s\n' "$notifs" | sed 's/^/  /'
    fi
  fi
}

[ $# -ge 1 ] || usage

CMD="$1"; shift
case "$CMD" in
  start) do_start "$@" ;;
  tick)  do_tick  "$@" ;;
  show)  do_show  "$@" ;;
  *)     usage ;;
esac
