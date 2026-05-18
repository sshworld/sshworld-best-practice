#!/usr/bin/env bash
# cmux-pane.sh — 얇은 cmux CLI wrapper.
# tmux-pane.sh 와 명령 표면 정렬. 이 슬라이스: launch / send / capture.
#
# 사용:
#   cmux-pane launch [<cmd>]
#   cmux-pane send <text> --pane=<ref> [--enter=false] [--delay=<sec>]
#   cmux-pane capture --pane=<ref> [--lines=<n>]
#
# 환경변수:
#   CMUX_BIN              — cmux 바이너리 경로 (미지정 시 PATH 의 cmux)
#   CBP_WORKSPACE_PREFIX  — workspace 이름 prefix (디폴트 cbp-)

set -uo pipefail

CMUX_BIN="${CMUX_BIN:-cmux}"
CBP_WORKSPACE_PREFIX="${CBP_WORKSPACE_PREFIX:-cbp-}"

usage() {
  cat >&2 <<'USAGE'
cmux-pane <command> [args]

commands:
  launch [<cmd>]                                workspace 띄움 (디폴트: zsh). stdout=workspace ref
  send <text> --pane=<ref> [--enter=false] [--delay=<sec>]
                                                텍스트 전송 후 Enter
  capture --pane=<ref> [--lines=<n>]            workspace 화면 내용 stdout
USAGE
  exit 2
}

die() { echo "cmux-pane: $*" >&2; exit "${2:-1}"; }

# --key=value 또는 --key value 모두 지원
parse_long_opts() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --pane=*)   PANE="${1#*=}"; shift ;;
      --pane)     PANE="$2"; shift 2 ;;
      --enter=*)  ENTER="${1#*=}"; shift ;;
      --enter)    ENTER="$2"; shift 2 ;;
      --delay=*)  DELAY="${1#*=}"; shift ;;
      --delay)    DELAY="$2"; shift 2 ;;
      --lines=*)  LINES="${1#*=}"; shift ;;
      --lines)    LINES="$2"; shift 2 ;;
      --)         shift; break ;;
      *)          shift ;;
    esac
  done
}

# 6자 hex 생성 (openssl 없이도 동작하는 폴백 포함)
rand_hex6() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 3
  else
    printf '%06x' $((RANDOM * RANDOM % 16777216))
  fi
}

do_launch() {
  local cmd="${1:-zsh}"
  local name="${CBP_WORKSPACE_PREFIX}$(rand_hex6)"
  local out
  out=$("$CMUX_BIN" new-workspace --cwd "$PWD" --name "$name" --command "$cmd" 2>/dev/null || true)
  # workspace ref: cmux 출력의 첫 줄 (실제 cmux 는 "workspace:name" 한 줄 반환).
  # 출력이 없으면 fallback.
  local ref
  ref=$(echo "$out" | head -1)
  if [ -z "$ref" ]; then
    ref="workspace:$name"
  fi
  printf '%s\n' "$ref"
}

do_send() {
  local text="$1"; shift
  local PANE="" ENTER="true" DELAY="1.5"
  parse_long_opts "$@"
  [ -z "$PANE" ] && die "send: --pane=<ref> 필요" 2
  "$CMUX_BIN" send --workspace "$PANE" "$text" || die "send: 실패" 3
  if [ "$ENTER" = "true" ]; then
    sleep "$DELAY"
    "$CMUX_BIN" send-key --workspace "$PANE" Enter || die "send: Enter 실패" 3
  fi
}

do_capture() {
  local PANE="" LINES=""
  parse_long_opts "$@"
  [ -z "$PANE" ] && die "capture: --pane=<ref> 필요" 2
  if [ -n "$LINES" ]; then
    "$CMUX_BIN" read-screen --workspace "$PANE" --lines "$LINES" || die "capture: 실패" 3
  else
    "$CMUX_BIN" read-screen --workspace "$PANE" || die "capture: 실패" 3
  fi
}

main() {
  [ $# -lt 1 ] && usage
  local cmd="$1"; shift
  case "$cmd" in
    launch)  do_launch "$@" ;;
    send)
      [ $# -lt 1 ] && die "send: <text> 필요" 2
      local text="$1"; shift
      do_send "$text" "$@" ;;
    capture) do_capture "$@" ;;
    -h|--help|help) usage ;;
    *) die "unknown command: $cmd" 2 ;;
  esac
}

main "$@"
