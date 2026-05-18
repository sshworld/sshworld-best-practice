#!/usr/bin/env bash
# tmux-pane.sh — 얇은 tmux 래퍼.
# 부모 Claude 가 다른 tmux pane 의 CLI 에이전트 (자식 Claude / 디버거 / 스크립트) 와 통신할 때 사용.
# 외부 `tmux-cli` (pchalasani/claude-code-tools) 와 명령 표면 정렬, 인자명만 정렬 (`--idle` 등).
#
# 사용:
#   tmux-pane launch [<cmd>]
#   tmux-pane send <text> --pane=<id> [--enter=false] [--delay=<sec>]
#   tmux-pane capture --pane=<id>
#   tmux-pane wait-idle --pane=<id> [--idle=<sec>] [--timeout=<sec>]
#   tmux-pane kill --pane=<id>
#   tmux-pane list
#   tmux-pane status
#
# 환경변수:
#   FORCE_SELF_KILL=1          — kill 의 자기 pane 검사 우회
#   CLAUDE_FAKE_SELF_PANE=...  — 테스트용: 현재 pane id 를 강제 주입

set -uo pipefail

MGR_SESSION="tmux-pane-mgr"

usage() {
  cat >&2 <<'USAGE'
tmux-pane <command> [args]

commands:
  launch [<cmd>]                                pane 띄움 (디폴트: zsh). stdout=pane id
  send <text> --pane=<id> [--enter=false] [--delay=<sec>]
                                                텍스트 전송 후 Enter (delay 후)
  capture --pane=<id>                           pane 내용 stdout
  wait-idle --pane=<id> [--idle=<sec>] [--timeout=<sec>]
                                                idle 도달까지 대기 (idle=3, timeout=120)
  kill --pane=<id>                              pane 종료 (자기 pane 거부)
  list                                          pane 목록 JSON
  status                                        현재 pane + window 의 pane 목록 텍스트
USAGE
  exit 2
}

die() { echo "tmux-pane: $*" >&2; exit "${2:-1}"; }

require_tmux() {
  command -v tmux > /dev/null 2>&1 || { echo "tmux-pane: tmux 미설치 — brew install tmux" >&2; exit 2; }
}

# in-tmux 면 현재 window 사용. 밖이면 관리 세션(MGR_SESSION) 자동 생성.
ensure_mgr_session() {
  if [ -n "${TMUX:-}" ]; then return 0; fi
  if ! tmux has-session -t "$MGR_SESSION" 2>/dev/null; then
    tmux new-session -d -s "$MGR_SESSION" -x 200 -y 50 'sleep 86400' >/dev/null 2>&1
  fi
}

# 인자 파싱: --key=value 또는 --key value 모두 지원
parse_long_opts() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --pane=*)    PANE="${1#*=}"; shift ;;
      --pane)      PANE="$2"; shift 2 ;;
      --enter=*)   ENTER="${1#*=}"; shift ;;
      --enter)     ENTER="$2"; shift 2 ;;
      --delay=*)   DELAY="${1#*=}"; shift ;;
      --delay)     DELAY="$2"; shift 2 ;;
      --idle=*)    IDLE="${1#*=}"; shift ;;
      --idle)      IDLE="$2"; shift 2 ;;
      --timeout=*) TIMEOUT="${1#*=}"; shift ;;
      --timeout)   TIMEOUT="$2"; shift 2 ;;
      --)          shift; break ;;
      *)           shift ;;
    esac
  done
}

format_pane() {
  # 입력: pane spec (예: tmux-pane-mgr:0.1 또는 %42)
  # 출력: session:window.pane 형식
  tmux display-message -t "$1" -p '#{session_name}:#{window_index}.#{pane_index}' 2>/dev/null
}

do_launch() {
  require_tmux
  local cmd="${1:-zsh}"
  if [ -n "${TMUX:-}" ]; then
    tmux split-window -P -F '#{session_name}:#{window_index}.#{pane_index}' "$cmd"
  else
    ensure_mgr_session
    tmux new-window -t "$MGR_SESSION" -P -F '#{session_name}:#{window_index}.#{pane_index}' "$cmd"
  fi
}

do_send() {
  require_tmux
  local text="$1"; shift
  local PANE="" ENTER="true" DELAY="1.5"
  parse_long_opts "$@"
  [ -z "$PANE" ] && die "send: --pane=<id> 필요" 2
  tmux has-session -t "${PANE%%:*}" 2>/dev/null || die "send: pane 없음 ($PANE)" 3
  tmux send-keys -t "$PANE" -- "$text" || die "send: send-keys 실패" 3
  if [ "$ENTER" = "true" ]; then
    # delay 후 Enter — wrapper 가 Enter 전 짧은 잠시를 보장 (외부 tmux-cli 와 동일 동작)
    sleep "$DELAY"
    tmux send-keys -t "$PANE" Enter || die "send: Enter 실패" 3
  fi
}

do_capture() {
  require_tmux
  local PANE=""
  parse_long_opts "$@"
  [ -z "$PANE" ] && die "capture: --pane=<id> 필요" 2
  tmux capture-pane -p -t "$PANE" || die "capture: 실패" 3
}

do_wait_idle() {
  require_tmux
  local PANE="" IDLE="3" TIMEOUT="120"
  parse_long_opts "$@"
  [ -z "$PANE" ] && die "wait-idle: --pane=<id> 필요" 2

  local elapsed=0 idle_accum=0 prev_hash="" cur_hash=""
  while [ "$(echo "$elapsed < $TIMEOUT" | bc -l 2>/dev/null || awk -v a="$elapsed" -v b="$TIMEOUT" 'BEGIN{print (a<b)}')" = "1" ]; do
    cur_hash=$(tmux capture-pane -p -t "$PANE" 2>/dev/null | shasum | awk '{print $1}')
    if [ "$cur_hash" = "$prev_hash" ] && [ -n "$prev_hash" ]; then
      idle_accum=$(awk -v a="$idle_accum" 'BEGIN{print a+0.5}')
      if [ "$(awk -v a="$idle_accum" -v b="$IDLE" 'BEGIN{print (a>=b)}')" = "1" ]; then
        return 0
      fi
    else
      idle_accum=0
    fi
    prev_hash="$cur_hash"
    sleep 0.5
    elapsed=$(awk -v a="$elapsed" 'BEGIN{print a+0.5}')
  done
  die "wait-idle: timeout (${TIMEOUT}s)" 4
}

do_kill() {
  require_tmux
  local PANE=""
  parse_long_opts "$@"
  [ -z "$PANE" ] && die "kill: --pane=<id> 필요" 2

  # 자기 pane 검증
  local self_pane="${CLAUDE_FAKE_SELF_PANE:-}"
  if [ -z "$self_pane" ] && [ -n "${TMUX:-}" ]; then
    self_pane=$(tmux display-message -p '#{session_name}:#{window_index}.#{pane_index}' 2>/dev/null)
  fi
  if [ -n "$self_pane" ] && [ "$self_pane" = "$PANE" ] && [ "${FORCE_SELF_KILL:-0}" != "1" ]; then
    echo "tmux-pane: 자기 pane kill 거부 — 우회: tmux kill-pane -t $PANE 또는 FORCE_SELF_KILL=1" >&2
    exit 5
  fi
  tmux kill-pane -t "$PANE" 2>/dev/null || die "kill: 실패 — pane 없음? ($PANE)" 3
}

do_list() {
  require_tmux
  ensure_mgr_session
  # in-tmux 면 현재 window, 밖이면 관리 세션 전체
  local target="${TMUX:+}"
  local panes=""
  if [ -n "${TMUX:-}" ]; then
    panes=$(tmux list-panes -F '#{session_name}:#{window_index}.#{pane_index}|#{pane_index}|#{pane_current_command}')
  else
    panes=$(tmux list-panes -s -t "$MGR_SESSION" -F '#{session_name}:#{window_index}.#{pane_index}|#{pane_index}|#{pane_current_command}' 2>/dev/null || true)
  fi

  # JSON 배열 수동 조립 (jq 미의존)
  echo -n "["
  local first=1
  while IFS='|' read -r id idx cmd; do
    [ -z "$id" ] && continue
    [ $first -eq 0 ] && echo -n ","
    printf '{"id":"%s","index":"%s","command":"%s"}' "$id" "$idx" "$cmd"
    first=0
  done <<< "$panes"
  echo "]"
}

do_status() {
  require_tmux
  if [ -n "${TMUX:-}" ]; then
    local cur=$(tmux display-message -p '#{session_name}:#{window_index}.#{pane_index}')
    echo "current pane: $cur"
    echo "panes in window:"
    tmux list-panes -F '  #{?pane_active,*, } #{session_name}:#{window_index}.#{pane_index}  #{pane_current_command}'
  else
    echo "outside tmux — managed session: $MGR_SESSION"
    ensure_mgr_session
    tmux list-panes -s -t "$MGR_SESSION" -F '  #{session_name}:#{window_index}.#{pane_index}  #{pane_current_command}' 2>/dev/null || echo "  (none)"
  fi
}

main() {
  [ $# -lt 1 ] && usage
  local cmd="$1"; shift
  case "$cmd" in
    launch)     do_launch "$@" ;;
    send)
      [ $# -lt 1 ] && die "send: <text> 필요" 2
      local text="$1"; shift
      do_send "$text" "$@" ;;
    capture)    do_capture "$@" ;;
    wait-idle)  do_wait_idle "$@" ;;
    kill)       do_kill "$@" ;;
    list)       do_list "$@" ;;
    status)     do_status "$@" ;;
    -h|--help|help) usage ;;
    *) die "unknown command: $cmd" 2 ;;
  esac
}

main "$@"
