#!/usr/bin/env bash
# orca-pane.sh — 얇은 Orca(stablyai desktop app) CLI 래퍼.
# tmux-pane.sh / cmux-pane.sh 와 명령 표면 정렬 (제3의 multiplexer driver).
#
# 사용:
#   orca-pane launch [<cmd>]
#   orca-pane send <text> --pane=<term_*> [--enter=false] [--delay=<sec>] [--enter-count=<n>]
#   orca-pane capture --pane=<term_*> [--lines=<n>]
#   orca-pane wait-idle --pane=<term_*> [--idle=<sec>] [--timeout=<sec>] [--for=tui-idle]
#   orca-pane kill --pane=<term_*>
#   orca-pane list
#   orca-pane cleanup
#   orca-pane status
#   orca-pane reap --pane=<term_*> [--idle=<sec>] [--timeout=<sec>]
#   orca-pane reap-orphans
#
# ⚠️ 핵심 계약: orca CLI 는 `ok:false` 응답도 **exit code 0** 으로 낼 수 있다
# (예: `orca terminal show --terminal term_bogus --json` → exit0 + {"ok":false,...}).
# 그래서 이 스크립트는 절대 exit code 로 성공을 판단하지 않고, 항상 JSON 의
# `.ok` 필드만 신뢰한다 (`_orca_run` 헬퍼가 이 판정을 중앙화).
#
# 환경변수:
#   ORCA_BIN                     — orca 바이너리 경로 (디폴트 PATH 의 orca). 테스트에서
#                                  fake orca 스크립트로 override 하면 실 orca 미필요.
#   CBP_TITLE_PREFIX              — launch 가 붙이는 title prefix (디폴트 cbp-). 사람이 보기
#                                  좋은 표시용일 뿐 — 자식 claude TUI 가 기동하면서 title 을
#                                  자기 것으로 덮어써(실측 2026-08-25) cleanup/reap-orphans 의
#                                  식별 근거로 쓸 수 없다. 식별은 reap-agents.sh 원장(kind=orca)
#                                  기반 — CBP_LEDGER_DIR / CBP_ORIGIN_ID 로 테스트 샌드박싱.
#   FORCE_SELF_KILL=1             — kill 의 자기 terminal 검사 우회.
#   CLAUDE_FAKE_SELF_ORCA_HANDLE  — 테스트용: 현재 terminal handle 강제 주입
#                                  (ORCA_TERMINAL_HANDLE 보다 우선).
#   CBP_REAP_FAST_CHECK           — reap 의 done-marker fast-path 스위치 (디폴트 1=on).
#                                  marker 파일 첫 줄이 대상 pane ref 와 일치하면 wait-idle
#                                  스킵 후 바로 capture 로 직행.
#   CBP_REAP_ORPHANS_DRY_RUN      — reap-orphans dry-run. 1 이면 close 없이
#                                  "would reap <ref>" 출력만.
#
# 마커 리졸버는 cmux-pane.sh 와 동일 계약(cbp-marker-path.sh) 을 공유 소스한다.

set -uo pipefail

ORCA_BIN="${ORCA_BIN:-orca}"
CBP_TITLE_PREFIX="${CBP_TITLE_PREFIX:-cbp-}"

# done-marker 경로는 cmux-pane.sh 와 **같은 리졸버**를 쓴다 (writer=hooks/notify-slice-done.sh).
_CBP_RESOLVER="${BASH_SOURCE[0]%/*}/cbp-marker-path.sh"
if [ -r "$_CBP_RESOLVER" ]; then
  # shellcheck source=/dev/null
  . "$_CBP_RESOLVER"
else
  cbp_marker_dir() { git rev-parse --path-format=absolute --git-common-dir 2>/dev/null; }
  cbp_marker_key() { git rev-parse --abbrev-ref HEAD 2>/dev/null; }
fi

usage() {
  cat >&2 <<'USAGE'
orca-pane <command> [args]

commands:
  launch [<cmd>] [--title=<text>]               terminal 띄움. stdout=term_<uuid> 핸들 한 줄.
  send <text> --pane=<term_*> [--enter=false] [--delay=<sec>] [--enter-count=<n>]
                                                텍스트 전송 후 Enter (--enter-count=N 회, 기본 1, 0이면 생략)
  capture --pane=<term_*> [--lines=<n>]         terminal 화면 tail stdout
  wait-idle --pane=<term_*> [--idle=<sec>] [--timeout=<sec>] [--for=tui-idle]
                                                lastOutputAt 이 <idle>초 동안 변하지 않으면 반환.
                                                디폴트: idle=3, timeout=120.
                                                --for=tui-idle 이면 native `orca terminal wait` 사용.
  kill --pane=<term_*>                          terminal 종료 (자기 terminal 거부)
  list                                          terminal 목록 JSON
  cleanup                                       원장(kind=orca) 에 있는 terminal 일괄 정리 (자기 terminal 보존)
  status                                        terminal 목록 텍스트
  reap --pane=<term_*> [--idle=<sec>] [--timeout=<sec>]
                                                done-marker 있으면 wait-idle 스킵 후 바로 capture.
                                                완료(✅/❌) 감지 시 close, 아니면 보존.
  reap-orphans                                  orphaned:true && 원장(kind=orca) terminal 일괄 정리.
USAGE
  exit 2
}

die() { echo "orca-pane: $*" >&2; exit "${2:-1}"; }

require_orca() {
  command -v "$ORCA_BIN" >/dev/null 2>&1 || die "orca 미설치 또는 ORCA_BIN 경로 오류 ($ORCA_BIN)" 2
}

# --key=value 또는 --key value 모두 지원
parse_long_opts() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --pane=*)         PANE="${1#*=}"; shift ;;
      --pane)           PANE="$2"; shift 2 ;;
      --enter=*)        ENTER="${1#*=}"; shift ;;
      --enter)          ENTER="$2"; shift 2 ;;
      --delay=*)        DELAY="${1#*=}"; shift ;;
      --delay)          DELAY="$2"; shift 2 ;;
      --enter-count=*)  ENTER_COUNT="${1#*=}"; shift ;;
      --enter-count)    ENTER_COUNT="$2"; shift 2 ;;
      --lines=*)        LINES="${1#*=}"; shift ;;
      --lines)          LINES="$2"; shift 2 ;;
      --idle=*)         IDLE="${1#*=}"; shift ;;
      --idle)           IDLE="$2"; shift 2 ;;
      --timeout=*)      TIMEOUT="${1#*=}"; shift ;;
      --timeout)        TIMEOUT="$2"; shift 2 ;;
      --for=*)          FOR="${1#*=}"; shift ;;
      --for)            FOR="$2"; shift 2 ;;
      --)               shift; break ;;
      *)                shift ;;
    esac
  done
}

# ----------------------------------------------------------------
# orca JSON envelope 헬퍼 — jq 미의존, python3 -c 인라인 파싱 (repo 기존 패턴,
# 참조: scripts/dispatch-slice-pane.sh 의 marker JSON 읽기).
# 모든 orca 호출은 이 헬퍼를 거친다 — exit code 가 아니라 `.ok` 만 신뢰한다.
# ----------------------------------------------------------------
_ORCA_RAW=""
_ORCA_ERR=""

# orca 명령 실행 (항상 --json 부여). 결과는 $_ORCA_RAW 에 저장.
# 반환: 0 = ok:true / 1 = ok:false(정상 응답이지만 실패) / 2 = 실행·파싱 자체 실패.
_orca_run() {
  require_orca
  _ORCA_RAW=$("$ORCA_BIN" "$@" --json 2>/dev/null)
  if [ -z "$_ORCA_RAW" ]; then
    _ORCA_ERR="orca 명령이 빈 응답을 반환함: $*"
    return 2
  fi
  local ok
  ok=$(printf '%s' "$_ORCA_RAW" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    print("parse_error")
    sys.exit(0)
print("true" if d.get("ok") else "false")
' 2>/dev/null)
  case "$ok" in
    true) return 0 ;;
    false)
      _ORCA_ERR=$(_orca_get 'error.message')
      [ -z "$_ORCA_ERR" ] && _ORCA_ERR=$(_orca_get 'error.code')
      [ -z "$_ORCA_ERR" ] && _ORCA_ERR="ok:false ($*)"
      return 1
      ;;
    *)
      _ORCA_ERR="orca 응답 JSON 파싱 실패: $_ORCA_RAW"
      return 2
      ;;
  esac
}

# $_ORCA_RAW 에서 dotted path 하나 추출 (스칼라/불리언 문자열화). 없으면 빈 문자열.
_orca_get() {
  local path="$1"
  printf '%s' "$_ORCA_RAW" | python3 -c '
import json, sys
path = sys.argv[1]
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
node = d
for part in path.split("."):
    if isinstance(node, dict):
        node = node.get(part)
    else:
        node = None
        break
if node is None:
    pass
elif isinstance(node, bool):
    print("true" if node else "false")
elif isinstance(node, (dict, list)):
    print(json.dumps(node))
else:
    print(node)
' "$path" 2>/dev/null
}

# $_ORCA_RAW 의 dotted path 가 배열(문자열 원소)이면 한 줄에 하나씩 출력.
_orca_get_lines() {
  local path="$1"
  printf '%s' "$_ORCA_RAW" | python3 -c '
import json, sys
path = sys.argv[1]
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
node = d
for part in path.split("."):
    if isinstance(node, dict):
        node = node.get(part)
    else:
        node = None
        break
if isinstance(node, list):
    for item in node:
        print(item)
' "$path" 2>/dev/null
}

# ----------------------------------------------------------------
# 원장(reap-agents.sh) 에서 kind=orca 인 ref 목록 (한 줄에 하나). 원장 파일이나
# reap-agents.sh 자체가 없으면 조용히 빈 목록 — cleanup/reap-orphans 를 실패시키지 않는다.
# CBP_LEDGER_DIR / CBP_ORIGIN_ID 는 reap-agents.sh 가 그대로 읽으므로 여기선 그냥 흘려보낸다.
_orca_ledger_refs() {
  local reaper="${BASH_SOURCE[0]%/*}/reap-agents.sh"
  [ -x "$reaper" ] || return 0
  "$reaper" list 2>/dev/null | python3 -c '
import json, sys
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        d = json.loads(line)
    except Exception:
        continue
    if d.get("kind") == "orca" and d.get("ref"):
        print(d["ref"])
' 2>/dev/null
  return 0
}

do_launch() {
  local cmd="" title_override=""
  local a
  for a in "$@"; do
    case "$a" in
      --title=*) title_override="${a#*=}" ;;
      *) [ -z "$cmd" ] && cmd="$a" ;;
    esac
  done
  local title="${CBP_TITLE_PREFIX}${title_override:-$(date +%s)-$$}"

  if ! _orca_run terminal create --worktree active --title "$title"; then
    die "launch: terminal create 실패 — $_ORCA_ERR" 3
  fi

  local handle
  handle=$(_orca_get 'result.terminal.handle')
  handle=$(printf '%s' "$handle" | tr -d '[:space:]')
  [ -z "$handle" ] && die "launch: 응답에 handle 없음 — $_ORCA_RAW" 3

  # cmd 있으면 새 terminal 로 전달 (cmux-pane.sh do_launch 의 cmd 전달과 동일 관례)
  if [ -n "$cmd" ]; then
    do_send "$cmd" --pane="$handle" >/dev/null
  fi

  printf '%s\n' "$handle"
}

do_send() {
  local text="$1"; shift
  local PANE="" ENTER="true" DELAY="1.5" ENTER_COUNT="1"
  parse_long_opts "$@"
  [ -z "$PANE" ] && die "send: --pane=<term_*> 필요" 2

  # 텍스트만 먼저 전송 (Enter 없이) — cmux-pane.sh 와 동일하게 텍스트/제출 분리.
  if ! _orca_run terminal send --terminal "$PANE" --text "$text"; then
    die "send: 텍스트 전송 실패 — $_ORCA_ERR" 3
  fi
  local accepted
  accepted=$(_orca_get 'result.send.accepted')
  if [ "$accepted" != "true" ]; then
    # 1회 재시도 후 그래도 실패면 die
    if ! _orca_run terminal send --terminal "$PANE" --text "$text"; then
      die "send: 텍스트 전송 실패(재시도) — $_ORCA_ERR" 3
    fi
    accepted=$(_orca_get 'result.send.accepted')
    [ "$accepted" != "true" ] && die "send: accepted=false (재시도 후에도 실패)" 3
  fi

  if [ "$ENTER" = "true" ] && [ "$ENTER_COUNT" != "0" ]; then
    sleep "$DELAY"
    local i=0
    while [ "$i" -lt "$ENTER_COUNT" ]; do
      if ! _orca_run terminal send --terminal "$PANE" --text "" --enter; then
        die "send: Enter 전송 실패 — $_ORCA_ERR" 3
      fi
      local enter_ok
      enter_ok=$(_orca_get 'result.send.accepted')
      if [ "$enter_ok" != "true" ]; then
        if ! _orca_run terminal send --terminal "$PANE" --text "" --enter; then
          die "send: Enter 전송 실패(재시도) — $_ORCA_ERR" 3
        fi
        enter_ok=$(_orca_get 'result.send.accepted')
        [ "$enter_ok" != "true" ] && die "send: Enter accepted=false (재시도 후에도 실패)" 3
      fi
      i=$((i + 1))
      [ "$i" -lt "$ENTER_COUNT" ] && sleep 0.3
    done
  fi
  return 0
}

do_capture() {
  local PANE="" LINES=""
  parse_long_opts "$@"
  [ -z "$PANE" ] && die "capture: --pane=<term_*> 필요" 2
  local lines="${LINES:-200}"

  if ! _orca_run terminal read --terminal "$PANE" --limit "$lines"; then
    die "capture: 실패 — $_ORCA_ERR" 3
  fi
  _orca_get_lines 'result.terminal.tail'
}

# wait-idle: 디폴트는 native tui-idle 이 아니라 lastOutputAt 폴링 (tui-idle 은 실제 TUI
# 에이전트에서만 유효 — 평범한 zsh 상대로는 항상 timeout 까지 태워버리기 때문).
do_wait_idle() {
  local PANE="" IDLE="3" TIMEOUT="120" FOR=""
  parse_long_opts "$@"
  [ -z "$PANE" ] && die "wait-idle: --pane=<term_*> 필요" 2

  if [ "$FOR" = "tui-idle" ]; then
    local timeout_ms=$((TIMEOUT * 1000))
    if _orca_run terminal wait --terminal "$PANE" --for tui-idle --timeout-ms "$timeout_ms"; then
      return 0
    fi
    die "wait-idle: tui-idle 대기 실패 — $_ORCA_ERR" 4
  fi

  local deadline=$(( $(date +%s) + TIMEOUT ))
  local prev_output_at="" idle_since=""

  while true; do
    local now
    now=$(date +%s)
    if [ "$now" -ge "$deadline" ]; then
      echo "orca-pane: wait-idle timeout (${TIMEOUT}s)" >&2
      exit 4
    fi

    if ! _orca_run terminal show --terminal "$PANE"; then
      # terminal 이 사라짐(ok:false, 예: terminal_handle_stale) — 죽은 terminal 은
      # 자명하게 idle 로 취급한다. reap 이 회수 대상을 기다리며 블로킹하지 않기 위함.
      return 0
    fi

    local cur
    cur=$(_orca_get 'result.terminal.lastOutputAt')
    [ -z "$cur" ] && cur=0

    if [ "$cur" != "$prev_output_at" ]; then
      idle_since="$now"
      prev_output_at="$cur"
    elif [ -z "$idle_since" ]; then
      idle_since="$now"
    fi

    if [ $(( now - idle_since )) -ge "$IDLE" ]; then
      return 0
    fi

    sleep 0.5
  done
}

do_kill() {
  local PANE=""
  parse_long_opts "$@"
  [ -z "$PANE" ] && die "kill: --pane=<term_*> 필요" 2

  local self_handle="${CLAUDE_FAKE_SELF_ORCA_HANDLE:-${ORCA_TERMINAL_HANDLE:-}}"
  if [ -n "$self_handle" ] && [ "$self_handle" = "$PANE" ] && [ "${FORCE_SELF_KILL:-0}" != "1" ]; then
    echo "orca-pane: 자기 terminal kill 거부 — 우회: FORCE_SELF_KILL=1" >&2
    exit 5
  fi

  if ! _orca_run terminal close --terminal "$PANE"; then
    die "kill: 실패 — $_ORCA_ERR" 3
  fi
}

do_list() {
  if ! _orca_run terminal list --worktree active; then
    die "list: 실패 — $_ORCA_ERR" 3
  fi
  printf '%s' "$_ORCA_RAW" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    print("[]")
    sys.exit(0)
terms = (d.get("result") or {}).get("terminals") or []
out = []
for t in terms:
    out.append({
        "id": t.get("handle"),
        "title": t.get("title"),
        "orphaned": bool(t.get("orphaned")),
        "connected": bool(t.get("connected")),
    })
print(json.dumps(out))
'
}

do_cleanup() {
  local self_handle="${ORCA_TERMINAL_HANDLE:-}"
  local count=0

  if ! _orca_run terminal list --worktree active; then
    echo "cleaning 0 child terminal(s) — orca terminal list 실패" >&2
    return 0
  fi

  local ledger_refs
  ledger_refs=$(_orca_ledger_refs)

  local handles
  handles=$(printf '%s' "$_ORCA_RAW" | LEDGER_REFS="$ledger_refs" python3 -c '
import json, os, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
terms = (d.get("result") or {}).get("terminals") or []
refs = set(os.environ.get("LEDGER_REFS", "").splitlines())
for t in terms:
    h = t.get("handle")
    if h and h in refs:
        print(h)
')

  local h
  while IFS= read -r h; do
    [ -z "$h" ] && continue
    [ -n "$self_handle" ] && [ "$h" = "$self_handle" ] && continue
    if _orca_run terminal close --terminal "$h"; then
      count=$((count + 1))
    fi
  done <<EOF
$handles
EOF

  echo "cleaning $count child terminal(s)" >&2
}

do_status() {
  echo "current terminal: ${ORCA_TERMINAL_HANDLE:-outside orca}"
  echo "cbp-* terminals:"
  if ! _orca_run terminal list --worktree active; then
    echo "  (조회 실패 — $_ORCA_ERR)"
    return 0
  fi
  local rows
  rows=$(printf '%s' "$_ORCA_RAW" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
terms = (d.get("result") or {}).get("terminals") or []
prefix = sys.argv[1]
for t in terms:
    title = t.get("title") or ""
    if title.startswith(prefix):
        print(f"  {t.get(\"handle\")}  {title}")
' "$CBP_TITLE_PREFIX")
  if [ -z "$rows" ]; then
    echo "  (없음)"
  else
    printf '%s\n' "$rows"
  fi
}

# done-marker 파일(S2 생산, hooks/notify-slice-done.sh) 조회 — cmux-pane.sh 의
# _cbp_find_done_marker 와 동일 계약. line1 이 대상 pane ref 와 일치하면 매치.
_orca_find_done_marker() {
  local pane_ref="$1"
  local common_dir
  common_dir=$(cbp_marker_dir) || return 0
  [ -z "$common_dir" ] && return 0

  local f first_line
  for f in "$common_dir"/cbp-slice-done-*; do
    [ -f "$f" ] || continue
    first_line=$(head -1 "$f" 2>/dev/null)
    [ "$first_line" = "$pane_ref" ] || continue
    printf '%s\n' "$f"
    return 0
  done
  return 0
}

do_reap() {
  # (⏺ prefix 허용) Claude TUI 가 완료 마커를 "⏺ ✅" 또는 들여쓰기로 렌더하는 경우 대응 —
  # 엄격 column-0 grep 은 실제 TUI 렌더를 못 잡는다.
  local PANE="" IDLE="3" TIMEOUT="120"
  local DONE_PATTERN='^[[:space:]]*(⏺[[:space:]]*)?(✅|❌)'
  parse_long_opts "$@"
  [ -z "$PANE" ] && die "reap: --pane=<term_*> 필요" 2

  local done_marker
  done_marker=$(_orca_find_done_marker "$PANE" 2>/dev/null || true)

  if [ "${CBP_REAP_FAST_CHECK:-1}" != "0" ] && [ -n "$done_marker" ]; then
    : # fast-path — wait-idle 스킵, 바로 capture 로 직행
  else
    do_wait_idle --pane="$PANE" --idle="$IDLE" --timeout="$TIMEOUT"
  fi

  local screen rc
  screen=$(do_capture --pane="$PANE" 2>/dev/null); rc=$?
  if [ "$rc" -ne 0 ]; then
    [ -n "$done_marker" ] && rm -f "$done_marker"
    echo "died $PANE"
    return 0
  fi

  if printf '%s\n' "$screen" | grep -qE "$DONE_PATTERN"; then
    do_kill --pane="$PANE" >/dev/null 2>&1
    [ -n "$done_marker" ] && rm -f "$done_marker"
    echo "reaped $PANE"
  else
    echo "kept $PANE (not done)"
  fi
}

do_reap_orphans() {
  if ! _orca_run terminal list --worktree active; then
    echo "reap-orphans: orca terminal list 실패 — skip" >&2
    return 0
  fi

  local self_handle="${ORCA_TERMINAL_HANDLE:-}"
  local ledger_refs
  ledger_refs=$(_orca_ledger_refs)

  local rows
  rows=$(printf '%s' "$_ORCA_RAW" | LEDGER_REFS="$ledger_refs" python3 -c '
import json, os, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
terms = (d.get("result") or {}).get("terminals") or []
refs = set(os.environ.get("LEDGER_REFS", "").splitlines())
for t in terms:
    if not t.get("orphaned"):
        continue
    h = t.get("handle")
    if h and h in refs:
        print(h)
')

  local h
  while IFS= read -r h; do
    [ -z "$h" ] && continue
    [ -n "$self_handle" ] && [ "$h" = "$self_handle" ] && continue
    if [ "${CBP_REAP_ORPHANS_DRY_RUN:-0}" = "1" ]; then
      echo "would reap $h"
    else
      _orca_run terminal close --terminal "$h" || true
    fi
  done <<EOF
$rows
EOF
  return 0
}

main() {
  [ $# -lt 1 ] && usage
  local cmd="$1"; shift
  case "$cmd" in
    launch)       do_launch "$@" ;;
    send)
      [ $# -lt 1 ] && die "send: <text> 필요" 2
      local text="$1"; shift
      do_send "$text" "$@" ;;
    capture)      do_capture "$@" ;;
    wait-idle)    do_wait_idle "$@" ;;
    kill)         do_kill "$@" ;;
    list)         do_list "$@" ;;
    cleanup)      do_cleanup "$@" ;;
    status)       do_status "$@" ;;
    reap)         do_reap "$@" ;;
    reap-orphans) do_reap_orphans "$@" ;;
    -h|--help|help) usage ;;
    *) die "unknown command: $cmd" 2 ;;
  esac
}

main "$@"
