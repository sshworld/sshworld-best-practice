#!/usr/bin/env bash
# cmux-pane.sh — 얇은 cmux CLI wrapper.
# tmux-pane.sh 와 명령 표면 정렬. 명령: launch / send / capture / wait-idle / kill / list / cleanup / status.
#
# 사용:
#   cmux-pane launch [<cmd>]
#   cmux-pane send <text> --pane=<ref> [--enter=false] [--delay=<sec>]
#   cmux-pane capture --pane=<ref> [--lines=<n>]
#   cmux-pane wait-idle --pane=<ref> [--idle=<sec>] [--timeout=<sec>]
#   cmux-pane kill --pane=<ref>
#   cmux-pane list
#   cmux-pane cleanup
#   cmux-pane status
#
# 환경변수:
#   CMUX_BIN                  — cmux 바이너리 경로 (미지정 시 PATH 의 cmux)
#   CBP_WORKSPACE_PREFIX       — workspace 이름 prefix (디폴트 cbp-)
#   CBP_LIST_LINES             — list 명령 입력 mock (테스트용. set 시 실제 cmux 호출 생략)
#   CLAUDE_FAKE_SELF_CMUX_WS   — 자기 workspace ref mock (테스트용)
#   FORCE_SELF_KILL            — 자기 workspace kill 거부 우회

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
  wait-idle --pane=<ref> [--idle=<sec>] [--timeout=<sec>]
                                                화면이 <idle>초 동안 변하지 않으면 반환.
                                                디폴트: idle=3, timeout=120
  kill --pane=<ref>                             workspace close. 자기 workspace 거부 (FORCE_SELF_KILL=1 우회)
  list                                          cbp- prefix workspace 목록 JSON 출력
  cleanup                                       cbp- prefix workspace 일괄 close (자기 workspace 보존)
  status                                        현재 workspace + cbp-* 목록 텍스트 출력
USAGE
  exit 2
}

die() { echo "cmux-pane: $*" >&2; exit "${2:-1}"; }

# --key=value 또는 --key value 모두 지원
parse_long_opts() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --pane=*)    PANE="${1#*=}"; shift ;;
      --pane)      PANE="$2"; shift 2 ;;
      --enter=*)   ENTER="${1#*=}"; shift ;;
      --enter)     ENTER="$2"; shift 2 ;;
      --delay=*)   DELAY="${1#*=}"; shift ;;
      --delay)     DELAY="$2"; shift 2 ;;
      --lines=*)   LINES="${1#*=}"; shift ;;
      --lines)     LINES="$2"; shift 2 ;;
      --idle=*)    IDLE="${1#*=}"; shift ;;
      --idle)      IDLE="$2"; shift 2 ;;
      --timeout=*) TIMEOUT="${1#*=}"; shift ;;
      --timeout)   TIMEOUT="$2"; shift 2 ;;
      --)          shift; break ;;
      *)           shift ;;
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

# wait-idle: tmux-pane.sh:do_wait_idle 와 동일 알고리즘.
# 0.5초마다 capture → sha 비교 → idle 누적.
# capture 는 cmux 의 "$CMUX_BIN" read-screen --workspace <ref> 결과 hash.
do_wait_idle() {
  local PANE="" IDLE="3" TIMEOUT="120"
  parse_long_opts "$@"
  [ -z "$PANE" ] && die "wait-idle: --pane=<ref> 필요" 2

  local deadline=$(( $(date +%s) + TIMEOUT ))
  local idle_count=0
  local prev_hash="" cur_hash=""

  while true; do
    local now
    now=$(date +%s)
    if [ "$now" -ge "$deadline" ]; then
      echo "wait-idle: timeout (${TIMEOUT}s)" >&2
      exit 4
    fi

    local screen_content
    screen_content=$("$CMUX_BIN" read-screen --workspace "$PANE" 2>/dev/null || echo "")
    if command -v sha256sum >/dev/null 2>&1; then
      cur_hash=$(printf '%s' "$screen_content" | sha256sum | cut -c1-16)
    elif command -v shasum >/dev/null 2>&1; then
      cur_hash=$(printf '%s' "$screen_content" | shasum -a 256 | cut -c1-16)
    else
      cur_hash=$(printf '%s' "$screen_content" | cksum | cut -d' ' -f1)
    fi

    if [ "$cur_hash" = "$prev_hash" ]; then
      idle_count=$(( idle_count + 1 ))
      # 0.5초 간격이므로 idle_count * 0.5 >= IDLE → idle_count >= IDLE * 2
      if [ "$idle_count" -ge $(( IDLE * 2 )) ]; then
        return 0
      fi
    else
      idle_count=0
      prev_hash="$cur_hash"
    fi

    sleep 0.5
  done
}

# 자기 workspace ref 반환.
# CLAUDE_FAKE_SELF_CMUX_WS env 가 설정되면 그 값 사용 (테스트용 mock).
# 미설정 시 "$CMUX_BIN" identify 결과 첫 줄.
get_self_ws_ref() {
  if [ -n "${CLAUDE_FAKE_SELF_CMUX_WS:-}" ]; then
    printf '%s' "$CLAUDE_FAKE_SELF_CMUX_WS"
    return 0
  fi
  "$CMUX_BIN" identify 2>/dev/null | head -1 || true
}

# cbp- prefix workspace 행 목록 반환 (줄당 "<name> <ref>" 형태).
# CBP_LIST_LINES env 가 set 이면 그 값을 파싱 (테스트용 mock).
# 미설정 시 실제 "$CMUX_BIN" list-workspaces 호출.
get_cbp_list_lines() {
  if [ -n "${CBP_LIST_LINES:-}" ]; then
    printf '%s\n' "$CBP_LIST_LINES"
  else
    "$CMUX_BIN" list-workspaces 2>/dev/null || true
  fi
}

do_kill() {
  local PANE=""
  parse_long_opts "$@"
  [ -z "$PANE" ] && die "kill: --pane=<ref> 필요" 2

  # 자기 workspace kill 거부 (FORCE_SELF_KILL=1 우회)
  if [ "${FORCE_SELF_KILL:-0}" != "1" ]; then
    local self_ref
    self_ref=$(get_self_ws_ref)
    if [ -n "$self_ref" ] && [ "$self_ref" = "$PANE" ]; then
      cat >&2 <<EOF
cmux-pane: 자기 workspace kill 거부 — 우회: $CMUX_BIN close-workspace --workspace $PANE 직접 호출 또는 FORCE_SELF_KILL=1
EOF
      exit 2
    fi
  fi

  "$CMUX_BIN" close-workspace --workspace "$PANE" || die "kill: workspace '$PANE' 없음 또는 close 실패" 3
}

do_list() {
  local raw_lines
  raw_lines=$(get_cbp_list_lines)

  # cbp- prefix 행만 필터링 후 JSON 배열 수동 조립
  # 입력 형태: "<name> <ref>" (공백 구분)
  local json="["
  local first=1
  local name ref

  while IFS= read -r line; do
    [ -z "$line" ] && continue
    # 첫 번째 필드=name, 두 번째 필드=ref
    name=$(printf '%s' "$line" | awk '{print $1}')
    ref=$(printf '%s' "$line" | awk '{print $2}')
    # cbp- prefix 매치 검사
    case "$name" in
      cbp-*)
        if [ "$first" = "1" ]; then
          first=0
        else
          json="${json},"
        fi
        json="${json}{\"id\":\"${ref}\",\"name\":\"${name}\"}"
        ;;
    esac
  done <<EOF
$raw_lines
EOF

  json="${json}]"
  printf '%s\n' "$json"
}

do_cleanup() {
  local self_ref
  self_ref=$(get_self_ws_ref)

  # list 를 통해 cbp- workspace 수집
  local raw_lines
  raw_lines=$(get_cbp_list_lines)

  local closed=0
  local name ref

  while IFS= read -r line; do
    [ -z "$line" ] && continue
    name=$(printf '%s' "$line" | awk '{print $1}')
    ref=$(printf '%s' "$line" | awk '{print $2}')
    case "$name" in
      cbp-*)
        # 자기 workspace 는 보존
        if [ -n "$self_ref" ] && [ "$ref" = "$self_ref" ]; then
          continue
        fi
        "$CMUX_BIN" close-workspace --workspace "$ref" 2>/dev/null || true
        closed=$((closed + 1))
        ;;
    esac
  done <<EOF
$raw_lines
EOF

  echo "cmux-pane: cleaning $closed cmux workspace(s)" >&2
}

do_status() {
  local self_ref
  self_ref=$(get_self_ws_ref)

  if [ -n "$self_ref" ]; then
    echo "current workspace: $self_ref"
  else
    echo "current workspace: outside cmux app"
  fi

  echo "cbp-* workspaces:"
  local raw_lines
  raw_lines=$(get_cbp_list_lines)
  local name ref found=0

  while IFS= read -r line; do
    [ -z "$line" ] && continue
    name=$(printf '%s' "$line" | awk '{print $1}')
    ref=$(printf '%s' "$line" | awk '{print $2}')
    case "$name" in
      cbp-*)
        echo "  $ref  $name"
        found=1
        ;;
    esac
  done <<EOF
$raw_lines
EOF

  if [ "$found" = "0" ]; then
    echo "  (없음)"
  fi
}

main() {
  [ $# -lt 1 ] && usage
  local cmd="$1"; shift
  case "$cmd" in
    launch)    do_launch "$@" ;;
    send)
      [ $# -lt 1 ] && die "send: <text> 필요" 2
      local text="$1"; shift
      do_send "$text" "$@" ;;
    capture)   do_capture "$@" ;;
    wait-idle) do_wait_idle "$@" ;;
    kill)      do_kill "$@" ;;
    list)      do_list "$@" ;;
    cleanup)   do_cleanup "$@" ;;
    status)    do_status "$@" ;;
    -h|--help|help) usage ;;
    *) die "unknown command: $cmd" 2 ;;
  esac
}

main "$@"
