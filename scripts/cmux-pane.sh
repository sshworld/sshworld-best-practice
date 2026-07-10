#!/usr/bin/env bash
# cmux-pane.sh — 얇은 cmux CLI wrapper.
# tmux-pane.sh 와 명령 표면 정렬. 명령: launch / send / capture / wait-idle / kill / list / cleanup / status / reap-orphans.
#
# 사용:
#   cmux-pane launch [<cmd>]
#   cmux-pane send <text> --pane=<ref> [--enter=false] [--delay=<sec>] [--enter-count=<n>]
#   cmux-pane capture --pane=<ref> [--lines=<n>]
#   cmux-pane wait-idle --pane=<ref> [--idle=<sec>] [--timeout=<sec>]
#   cmux-pane kill --pane=<ref>
#   cmux-pane list
#   cmux-pane cleanup
#   cmux-pane status
#   cmux-pane notify --title=<t> [--body=<b>] [--subtitle=<s>] [--workspace=<ref>] [--surface=<ref>]
#   cmux-pane set-status <key> <value> [--icon=<name>] [--color=<#hex>] [--workspace=<ref>]
#   cmux-pane reap-orphans
#
# 환경변수:
#   CMUX_BIN                  — cmux 바이너리 경로 (미지정 시 PATH 의 cmux)
#   CBP_WORKSPACE_PREFIX       — workspace 이름 prefix (디폴트 cbp-)
#   CBP_STATE_FILE             — state file 경로 override (디폴트: ~/.cache/cbp/children-<ws_sanitized>.json)
#                                ws_sanitized = ${CMUX_WORKSPACE_ID//[:\/]/_}
#   CBP_STATE_DIR              — reap-orphans 가 스캔하는 state file 디렉토리 (디폴트: ~/.cache/cbp)
#   CBP_LIST_LINES             — list 명령 입력 mock (테스트용. set 시 실제 cmux 호출 생략)
#   CLAUDE_FAKE_SELF_CMUX_WS   — 자기 workspace ref mock (테스트용)
#   FORCE_SELF_KILL            — 자기 workspace kill 거부 우회. surface kill 은 self-surface 만 거부 (FORCE_SELF_KILL 영향 없음).
#   PROGRESS_DRY_RUN           — notify/set-status 가 실제 cmux 호출 없이 명령 echo 후 exit 0 (테스트용)
#   CBP_LAUNCH_VERIFY_TRIES    — _do_launch_grid PTY 검증 루프 최대 시도 횟수 (디폴트 5).
#                                각 회: send-key Enter → sleep CBP_WARMUP_SLEEP → read-screen 확인.
#                                CBP_DISABLE_WARMUP=1 이면 검증 루프 자체를 스킵 (기존 동작 보존).
#   CBP_WARMUP_SLEEP           — _do_launch_grid 검증 루프 내 각 슬립 초 (디폴트 0.5).
#   CBP_REAP_ORPHANS_DRY_RUN   — reap-orphans dry-run 모드. 1 이면 close 없이 "would reap <ref>" 출력만.
#   CBP_REAP_ORPHANS_GRACE_SEC — reap-orphans 신생 surface grace 초 (디폴트 30). ts= 가 now 기준 이
#                                초 이내면 liveness 검사 자체를 skip 하고 보존 (launch PTY warmup 중
#                                오살 방지). ts 비수치/결측 → grace 미적용(기존 liveness 검사).
#                                reap --all/argless 의 신생 자식 grace skip 에도 동일 변수 재사용.
#   CBP_LAUNCH_DEBUG           — 1 이면 _do_launch_grid 의 생성 경로(new-pane/new-split raw_out),
#                                prev_surface, verify 루프 각 시도의 read-screen 출력을 stderr 로
#                                dump. 디폴트(0/unset) 시 동작·출력 완전 불변(추가 read-screen 호출 없음).

set -uo pipefail

CMUX_BIN="${CMUX_BIN:-cmux}"
CBP_WORKSPACE_PREFIX="${CBP_WORKSPACE_PREFIX:-cbp-}"

usage() {
  cat >&2 <<'USAGE'
cmux-pane <command> [args]

commands:
  launch [<cmd>]                                workspace 띄움 (디폴트: zsh).
                                                CMUX_WORKSPACE_ID set → 부모 workspace 안 grid split.
                                                  stdout=surface ref (예: surface:4).
                                                CMUX_WORKSPACE_ID unset → new-workspace 흐름.
                                                  stdout=workspace ref (예: workspace:cbp-abc123).
  send <text> --pane=<ref> [--enter=false] [--delay=<sec>] [--enter-count=<n>]
                                                텍스트 전송 후 Enter (--enter-count=N 회, 기본 1, 0이면 생략)
  capture --pane=<ref> [--lines=<n>]            workspace 화면 내용 stdout
  wait-idle --pane=<ref> [--idle=<sec>] [--timeout=<sec>]
                                                화면이 <idle>초 동안 변하지 않으면 반환.
                                                디폴트: idle=3, timeout=120
  kill --pane=<ref>                             surface:N → close-surface + state remove.
                                                  self-surface(CMUX_SURFACE_ID 일치) 만 거부, 그 외 허용.
                                                workspace:N → close-workspace (기존).
                                                  자기 workspace kill 거부 (FORCE_SELF_KILL=1 우회).
  list                                          cbp- prefix workspace 목록 JSON 출력
  cleanup                                       cbp- prefix workspace 일괄 close (자기 workspace 보존)
  status                                        현재 workspace + cbp-* 목록 텍스트 출력
  notify --title=<t> [--body=<b>] [--subtitle=<s>] [--workspace=<ref>] [--surface=<ref>]
                                                cmux 알림 패널에 메시지 push (좌측 사이드바 latest
                                                notification + ⌘I 패널 누적). workspace/surface 미지정 시
                                                cmux 가 $CMUX_WORKSPACE_ID / $CMUX_SURFACE_ID 자동 사용.
  set-status <key> <value> [--icon=<name>] [--color=<#hex>] [--workspace=<ref>]
                                                workspace 사이드바 탭 status pill 갱신 (key 별로 관리).
                                                예: set-status plan-dev "2/3 (66%)" --icon sparkle
  reap [--pane=<ref>] [--all] [--idle=<sec>] [--timeout=<sec>]
                                                --pane 지정: 단일 surface wait-idle→capture→완료(✅/❌)
                                                  감지 시 자동 close, 미완료면 보존.
                                                --pane 생략 또는 --all: state 의 모든 자식 순회
                                                  (fast-probe 기본 --idle=2 --timeout=10, 옵션 명시 시
                                                  override). 자식마다 subshell 실행 — 개별 실패가 루프
                                                  전체를 안 죽임. ts 기준 age < CBP_REAP_ORPHANS_GRACE_SEC
                                                  (기본 30)인 신생 자식은 probe 없이 "grace — kept".
                                                  마지막 줄 "reaped N / kept M" 요약. exit 0.
                                                CBP_REAP_DRY_RUN=1 dry-run.
  reap-orphans                                  모든 state file(CBP_STATE_DIR, 디폴트 ~/.cache/cbp) 스캔.
                                                dead surface(read-screen rc≠0) → close-surface + state 제거.
                                                alive / self(CMUX_SURFACE_ID) surface 보호.
                                                CBP_REAP_ORPHANS_DRY_RUN=1: close 없이 "would reap <ref>" 만 출력.
                                                CMUX_BIN 미존재 시 conservative exit 0.
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
      --delay=*)        DELAY="${1#*=}"; shift ;;
      --delay)          DELAY="$2"; shift 2 ;;
      --enter-count=*)  ENTER_COUNT="${1#*=}"; shift ;;
      --enter-count)    ENTER_COUNT="$2"; shift 2 ;;
      --lines=*)        LINES="${1#*=}"; shift ;;
      --lines)     LINES="$2"; shift 2 ;;
      --idle=*)    IDLE="${1#*=}"; shift ;;
      --idle)      IDLE="$2"; shift 2 ;;
      --timeout=*) TIMEOUT="${1#*=}"; shift ;;
      --timeout)   TIMEOUT="$2"; shift 2 ;;
      --done-pattern=*) DONE_PATTERN="${1#*=}"; shift ;;
      --done-pattern)   DONE_PATTERN="$2"; shift 2 ;;
      --all)       ALL="1"; shift ;;
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

# ----------------------------------------------------------------
# State file 헬퍼 함수 (private — do_launch/do_kill 등에서 사용)
# state file: 각 줄 "surface=<ref>|name=<name>|ts=<unix>|ws=<workspace_id>"
# jq 의존 없음. surface ref 에 '|' 또는 '=' 미포함 가정 (cmux ref = "surface:N" 형식).
# ----------------------------------------------------------------

# state file 경로 반환.
# CBP_STATE_FILE env 가 set 이면 그 값 사용.
# 미설정 시 ~/.cache/cbp/children-<ws_sanitized>.json
# ws_sanitized = ${CMUX_WORKSPACE_ID//[:\/]/_}
cbp_state_path() {
  if [ -n "${CBP_STATE_FILE:-}" ]; then
    printf '%s' "$CBP_STATE_FILE"
    return 0
  fi
  local ws="${CMUX_WORKSPACE_ID:-default}"
  local sanitized
  # 콜론 / 슬래시 → 언더스코어
  sanitized=$(printf '%s' "$ws" | tr ':/' '__')
  local cache_dir="${HOME}/.cache/cbp"
  mkdir -p "$cache_dir"
  printf '%s' "${cache_dir}/children-${sanitized}.json"
}

# Lock primitive — mkdir atomic mutex 단일 경로 (flock 유무 무관, macOS 실경로 일치).
# acquire/release 분리 → 호출부가 자기 셸 컨텍스트에서 critical section 실행
# (surface_ref 등 지역변수 회수 가능). lockdir 안 pid 파일로 stale holder 생존 확인.
_CBP_LOCKDIR=""

# 죽은 holder 의 stale lockdir 만 reap. 살아있는 holder 는 보호.
_cbp_lock_reap_stale() {
  local lockdir="$1"
  local holder
  holder=$(cat "${lockdir}/pid" 2>/dev/null || echo "")
  if [ -n "$holder" ] && kill -0 "$holder" 2>/dev/null; then
    return 1   # holder 살아있음 → reap 금지
  fi
  rm -rf "$lockdir" 2>/dev/null || true
  return 0
}

# lock 획득 (mkdir atomic). timeout 10초 → stale 판정 후 pid 기반 reap.
_cbp_lock_acquire() {
  local lockpath="$1"
  local lockdir="${lockpath}.d"
  local waited=0
  while ! mkdir "$lockdir" 2>/dev/null; do
    sleep 0.05
    waited=$(( waited + 1 ))
    if [ "$waited" -ge 200 ]; then
      _cbp_lock_reap_stale "$lockdir" || true
      waited=0
    fi
  done
  printf '%s' "$$" > "${lockdir}/pid" 2>/dev/null || true
  _CBP_LOCKDIR="$lockdir"
}

# lock 해제.
_cbp_lock_release() {
  local lockdir="$1"
  rm -rf "$lockdir" 2>/dev/null || true
  [ "$_CBP_LOCKDIR" = "$lockdir" ] && _CBP_LOCKDIR=""
}

# 호환 래퍼 (cmd 실행형) — cbp_state_remove 등에서 사용.
# 사용법: _cbp_lock <lockpath> <cmd> [args...]
_cbp_lock() {
  local lockpath="$1"; shift
  _cbp_lock_acquire "$lockpath"
  "$@"
  local rc=$?
  _cbp_lock_release "${lockpath}.d"
  return $rc
}

# state file 에 한 줄 추가 (lock 없음 — 이미 lock 보유한 호출부 전용).
# 각 라인: surface=<ref>|name=<name>|ts=<unix>|ws=<workspace_id>
_cbp_state_append_unlocked() {
  local sf="$1" surface_ref="$2" name="$3"
  local ts ws
  ts=$(date +%s)
  ws="${CMUX_WORKSPACE_ID:-default}"
  mkdir -p "$(dirname "$sf")"
  printf 'surface=%s|name=%s|ts=%s|ws=%s\n' "$surface_ref" "$name" "$ts" "$ws" >> "$sf"
}

# state file 에 한 줄 추가 (lock 보호). 인자: surface_ref, name.
cbp_state_append() {
  local surface_ref="$1"
  local name="$2"
  local sf
  sf=$(cbp_state_path)
  local lockpath="${sf}.lock"
  _cbp_lock_acquire "$lockpath"
  _cbp_state_append_unlocked "$sf" "$surface_ref" "$name"
  _cbp_lock_release "${lockpath}.d"
}

# state file 의 surface ref 목록을 한 줄당 하나 stdout.
# state file 없으면 빈 출력 (empty).
cbp_state_list() {
  local sf
  sf=$(cbp_state_path)
  [ -f "$sf" ] || return 0
  # 각 줄에서 surface= 필드 추출
  grep -o 'surface=[^|]*' "$sf" | sed 's/surface=//'
}

# state file 에서 특정 surface_ref 줄 제거. 인자: surface_ref.
cbp_state_remove() {
  local surface_ref="$1"
  local sf
  sf=$(cbp_state_path)
  [ -f "$sf" ] || return 0
  local lockpath="${sf}.lock"
  # shellcheck disable=SC2016
  _cbp_lock "$lockpath" bash -c '
    sf="$1" surface_ref="$2"
    tmp=$(mktemp "${sf}.XXXXXX")
    grep -v "surface=${surface_ref}|" "$sf" > "$tmp" 2>/dev/null || true
    mv "$tmp" "$sf"
  ' -- "$sf" "$surface_ref"
}

# ----------------------------------------------------------------
do_launch() {
  local cmd="${1:-}"  # 명시 cmd. grid 경로 → 비어있으면 send 안 함. non-grid 경로 → zsh 기본.
  local name="${CBP_WORKSPACE_PREFIX}$(rand_hex6)"

  # CMUX_WORKSPACE_ID set → grid split 분기 (부모 workspace 안에서 surface 생성)
  if [ -n "${CMUX_WORKSPACE_ID:-}" ]; then
    _do_launch_grid "$cmd" "$name"
    return $?
  fi

  # CMUX_WORKSPACE_ID unset → 기존 new-workspace 흐름 (cmd 없으면 zsh 기본)
  [ -z "$cmd" ] && cmd="zsh"
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

# surface 가 terminal(PTY 살아있음) 상태인지 확인.
# "$CMUX_BIN" read-screen --surface "<ref>" 로 확인 — rc0 이면 terminal, 그 외 not terminal.
# stdout/stderr 는 버림.
# 반환: 0=terminal, 1=not terminal.
_cbp_surface_is_terminal() {
  local surface_ref="$1"
  "$CMUX_BIN" read-screen --surface "$surface_ref" >/dev/null 2>&1
}

# CBP_LAUNCH_DEBUG=1 이면 진단 메시지를 stderr 로 dump. 디폴트(off) 시 완전 무동작(추가 호출 없음).
_cbp_debug() {
  [ "${CBP_LAUNCH_DEBUG:-0}" = "1" ] && echo "[CBP_LAUNCH_DEBUG] $*" >&2
  return 0
}

# 좀비 surface 방지 — _do_launch_grid 실패 종료(die exit) 시 trap 으로 호출.
# best-effort close-surface + state 제거. exit code 는 호출부(trap 문자열)에서 별도 보존.
_cbp_launch_trap_cleanup() {
  local ref="$1"
  "$CMUX_BIN" close-surface --surface "$ref" >/dev/null 2>&1 || true
  cbp_state_remove "$ref"
}

# do_launch 의 grid split 내부 구현 (CMUX_WORKSPACE_ID 가 set 인 경우).
# 라운드로빈 방향: count=0 → right (첫 자식), count=1 → down, count=2 → right, count=3 → down, ...
# CBP_SPLIT_POLICY env 로 방향 override 가능 (Slice A3 에서 확장 예정).
_do_launch_grid() {
  local _cmd="$1"  # cmd 가 있으면 PTY 검증 통과 후 do_send 로 전달
  local name="$2"

  local sf lockpath
  sf=$(cbp_state_path)
  lockpath="${sf}.lock"

  local surface_ref raw_out
  local _creation_path="unknown"

  # ── CRITICAL SECTION: count read → cmux 생성 → state 기록 원자화 ──────────
  # 병렬 dispatch race 방지. 이 구간이 비원자적이면 동시 호출이 같은 count/prev_surface
  # 를 읽어 다중 new-pane 또는 같은 prev split → cmux 동시 생성 실패로 surface detached.
  # 우회 (테스트 red baseline): CBP_DISABLE_LAUNCH_LOCK=1.
  local _locked=0
  if [ "${CBP_DISABLE_LAUNCH_LOCK:-0}" != "1" ]; then
    _cbp_lock_acquire "$lockpath"
    _locked=1
  fi

  # 기존 자식 목록으로 count 결정 (lock 보유 중이라 lock-free read OK)
  local children count=0
  children=$(cbp_state_list 2>/dev/null || true)
  if [ -n "$children" ]; then
    count=$(printf '%s\n' "$children" | grep -c '[^[:space:]]' 2>/dev/null) || count=0
  fi

  if [ "$count" -eq 0 ]; then
    # 첫 자식: 부모 workspace 우측에 new-pane
    raw_out=$("$CMUX_BIN" new-pane \
      --type terminal \
      --direction right \
      --workspace "$CMUX_WORKSPACE_ID" 2>/dev/null || true)
    surface_ref=$(printf '%s' "$raw_out" | awk '/^OK / {print $2; exit}')
    _creation_path="new-pane(first child)"
    _cbp_debug "creation path=$_creation_path raw_out=[$raw_out]"
  else
    # 후속 자식: 마지막→처음 순으로 살아있는 첫 번째 surface 를 prev_surface 로 선택.
    # 살아있는 게 없으면 count=0 과 동일하게 new-pane 폴백.
    local prev_surface=""
    local _sref
    # children 변수는 이미 위에서 읽음 (state_list 결과, 줄당 1개 surface ref).
    # 마지막→처음 순회: tac 또는 tail→head 폴백.
    local _reversed
    if command -v tac >/dev/null 2>&1; then
      _reversed=$(printf '%s\n' "$children" | tac)
    else
      _reversed=$(printf '%s\n' "$children" | tail -r 2>/dev/null || printf '%s\n' "$children" | awk '{a[NR]=$0} END{for(i=NR;i>=1;i--) print a[i]}')
    fi
    while IFS= read -r _sref; do
      [ -z "$_sref" ] && continue
      if _cbp_surface_is_terminal "$_sref"; then
        prev_surface="$_sref"
        break
      fi
    done <<_REVEOF
$_reversed
_REVEOF

    _cbp_debug "prev_surface=[$prev_surface]"

    if [ -z "$prev_surface" ]; then
      # 살아있는 prev 없음 → new-pane 폴백 (첫 자식 경로 재사용)
      raw_out=$("$CMUX_BIN" new-pane \
        --type terminal \
        --direction right \
        --workspace "$CMUX_WORKSPACE_ID" 2>/dev/null || true)
      surface_ref=$(printf '%s' "$raw_out" | awk '/^OK / {print $2; exit}')
      _creation_path="new-pane(fallback, no live prev)"
      _cbp_debug "creation path=$_creation_path raw_out=[$raw_out]"
    else
      # 라운드로빈 방향: count 홀수 → down, 짝수 → right
      local dir
      if [ -n "${CBP_SPLIT_POLICY:-}" ]; then
        dir="$CBP_SPLIT_POLICY"
      elif [ $(( count % 2 )) -eq 1 ]; then
        dir="down"
      else
        dir="right"
      fi

      raw_out=$("$CMUX_BIN" new-split "$dir" \
        --surface "$prev_surface" 2>/dev/null || true)
      surface_ref=$(printf '%s' "$raw_out" | awk '/^OK / {print $2; exit}')
      _creation_path="new-split($dir, prev=$prev_surface)"
      _cbp_debug "creation path=$_creation_path raw_out=[$raw_out]"
    fi
  fi

  # surface ref 공백 trim + fallback
  surface_ref=$(printf '%s' "$surface_ref" | tr -d '[:space:]')
  [ -z "$surface_ref" ] && surface_ref="surface:unknown"

  # 좀비 surface 방지 trap: surface 생성 성공 직후 ~ launch 정상 완료까지 유효.
  # 이후 실패 종료(verify-fail die + 이후 do_send die 포함) 시 best-effort close-surface
  # + state 제거. 정상 완료 시 두 성공 경로(warmup 스킵/검증 통과) 에서 trap 해제.
  # exit code 는 trap 안에서 즉시 $? 캡처 후 명시 재-exit 로 보존 (die 의 exit 3 등 덮어쓰기 방지).
  trap '_cbp_launch_trap_rc=$?; _cbp_launch_trap_cleanup "$surface_ref"; exit "$_cbp_launch_trap_rc"' EXIT

  # state file 기록 (lock 보유 중 — unlocked 직접 호출로 재진입 회피)
  _cbp_state_append_unlocked "$sf" "$surface_ref" "$name"

  # ── CRITICAL SECTION 끝 — release 후 후처리는 lock 밖 ──────────────────────
  if [ "$_locked" = "1" ]; then
    _cbp_lock_release "${lockpath}.d"
    _locked=0
  fi

  # rename-tab (stdout/stderr 모두 redirect — rename-tab 이 OK 한 줄 stdout 출력하므로)
  "$CMUX_BIN" rename-tab --surface "$surface_ref" "$name" >/dev/null 2>&1 || true

  # PTY 검증 루프 (lock 밖 — lock 해제 후 실행).
  # CBP_DISABLE_WARMUP=1 이면 기존처럼 검증 스킵 → surface_ref 즉시 반환 (회귀 보존).
  # 아니면: 최대 CBP_LAUNCH_VERIFY_TRIES(기본 5)회 — 매회 send-key Enter → sleep → read-screen.
  # terminal 되면 break(성공). 끝까지 실패 시 die(exit 3).
  if [ "${CBP_DISABLE_WARMUP:-0}" = "1" ]; then
    # warmup 스킵 경로 — cmd 가 있으면 surface 로 전달
    if [ -n "$_cmd" ]; then
      do_send "$_cmd" --pane="$surface_ref" >/dev/null
    fi
    trap - EXIT
    printf '%s\n' "$surface_ref"
    return 0
  fi

  local verify_tries="${CBP_LAUNCH_VERIFY_TRIES:-5}"
  local warmup_sleep="${CBP_WARMUP_SLEEP:-0.5}"
  local verified=0
  local _vt=0
  while [ "$_vt" -lt "$verify_tries" ]; do
    "$CMUX_BIN" send-key --surface "$surface_ref" Enter >/dev/null 2>&1 || true
    sleep "$warmup_sleep"
    if [ "${CBP_LAUNCH_DEBUG:-0}" = "1" ]; then
      local _debug_screen
      _debug_screen=$("$CMUX_BIN" read-screen --surface "$surface_ref" 2>&1)
      _cbp_debug "verify try $((_vt + 1))/${verify_tries} read-screen=[$_debug_screen]"
    fi
    if _cbp_surface_is_terminal "$surface_ref"; then
      verified=1
      break
    fi
    _vt=$(( _vt + 1 ))
  done

  if [ "$verified" = "0" ]; then
    die "launch: surface '$surface_ref' PTY 미기동 (not a terminal) — ${verify_tries}회 검증 실패. creation path=${_creation_path}. cmux 불안정 가능, --mode=subagent 폴백 고려." 3
  fi

  # PTY 검증 통과 후 cmd 전달 (cmd 있을 때만)
  if [ -n "$_cmd" ]; then
    do_send "$_cmd" --pane="$surface_ref" >/dev/null
  fi

  trap - EXIT
  printf '%s\n' "$surface_ref"
}

_send_is_submitted() {
  local screen="$1"
  [ -z "$screen" ] && return 2
  local last_prompt
  last_prompt=$(printf '%s\n' "$screen" | grep -E '^[[:space:]]*[❯>]' | tail -1)
  [ -z "$last_prompt" ] && return 2
  if printf '%s\n' "$last_prompt" | grep -qE '^[[:space:]]*[❯>][[:space:]]*$'; then
    return 0
  fi
  return 1
}

do_send() {
  local text="$1"; shift
  local PANE="" ENTER="true" DELAY="1.5" ENTER_COUNT="1"
  parse_long_opts "$@"
  [ -z "$PANE" ] && die "send: --pane=<ref> 필요" 2
  # surface:* → --surface, 그 외 → --workspace
  local pane_flag
  case "$PANE" in
    surface:*) pane_flag="--surface" ;;
    *)         pane_flag="--workspace" ;;
  esac
  "$CMUX_BIN" send "$pane_flag" "$PANE" "$text" || die "send: 실패" 3
  if [ "$ENTER" = "true" ] && [ "$ENTER_COUNT" != "0" ]; then
    sleep "$DELAY"
    local i=0
    while [ "$i" -lt "$ENTER_COUNT" ]; do
      "$CMUX_BIN" send-key "$pane_flag" "$PANE" Enter || die "send: Enter 실패" 3
      i=$((i + 1))
      [ "$i" -lt "$ENTER_COUNT" ] && sleep 0.3
    done
    # confirm loop: 제출 확인 재시도. CBP_SEND_CONFIRM=0 으로 끄기(기존 동작).
    if [ "${CBP_SEND_CONFIRM:-1}" != "0" ]; then
      local confirm_tries="${CBP_SEND_CONFIRM_TRIES:-3}"
      local confirm_sleep="${CBP_SEND_CONFIRM_SLEEP:-0.6}"
      # rc2=화면 못읽음=PTY detached 의심 → Enter 재전송으로 attach 강제 (bounded)
      local detached_tries="${CBP_SEND_CONFIRM_DETACHED_TRIES:-$confirm_tries}"
      local detached_ct=0
      local ct=0
      while [ "$ct" -lt "$confirm_tries" ]; do
        sleep "$confirm_sleep"
        local screen
        screen=$("$CMUX_BIN" read-screen "$pane_flag" "$PANE" 2>/dev/null || echo "")
        local check_rc
        _send_is_submitted "$screen"; check_rc=$?
        if [ "$check_rc" -eq 0 ]; then
          break
        elif [ "$check_rc" -eq 1 ]; then
          "$CMUX_BIN" send-key "$pane_flag" "$PANE" Enter || true
        else
          # rc2=화면 못읽음=PTY detached 의심 → Enter 재전송으로 attach 강제
          if [ "$detached_ct" -lt "$detached_tries" ]; then
            "$CMUX_BIN" send-key "$pane_flag" "$PANE" Enter || true
            detached_ct=$((detached_ct + 1))
          else
            break
          fi
        fi
        ct=$((ct + 1))
      done
    fi
  fi
  return 0
}

do_capture() {
  local PANE="" LINES=""
  parse_long_opts "$@"
  [ -z "$PANE" ] && die "capture: --pane=<ref> 필요" 2
  # surface:* → --surface, 그 외 → --workspace
  local pane_flag
  case "$PANE" in
    surface:*) pane_flag="--surface" ;;
    *)         pane_flag="--workspace" ;;
  esac
  if [ -n "$LINES" ]; then
    "$CMUX_BIN" read-screen "$pane_flag" "$PANE" --lines "$LINES" || die "capture: 실패" 3
  else
    "$CMUX_BIN" read-screen "$pane_flag" "$PANE" || die "capture: 실패" 3
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
    # surface:* → --surface, 그 외 → --workspace
    local _pane_flag
    case "$PANE" in
      surface:*) _pane_flag="--surface" ;;
      *)         _pane_flag="--workspace" ;;
    esac
    screen_content=$("$CMUX_BIN" read-screen "$_pane_flag" "$PANE" 2>/dev/null || echo "")
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

  case "$PANE" in
    surface:*)
      # self-surface 만 거부 (CMUX_SURFACE_ID match). 그 외 surface 는 모두 허용.
      # FORCE_SELF_KILL 영향 없음 (surface 는 부모 workspace 종속이므로 외부 surface kill 위험 낮음).
      local self_surface="${CMUX_SURFACE_ID:-}"
      if [ -n "$self_surface" ] && [ "$self_surface" = "$PANE" ]; then
        cat >&2 <<EOF
cmux-pane: 자기 surface kill 거부 — 우회: $CMUX_BIN close-surface --surface $PANE 직접 호출
EOF
        exit 2
      fi
      "$CMUX_BIN" close-surface --surface "$PANE" || die "kill: surface '$PANE' 없음 또는 close 실패" 3
      cbp_state_remove "$PANE"
      ;;
    *)
      # workspace ref (또는 그 외): 기존 close-workspace 흐름
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
      ;;
  esac
}

# --pane=<ref> 단일 자식 회수 (기존 do_reap 로직 그대로 — 이름만 분리).
# --all/argless 는 do_reap 이 이 함수를 자식마다 subshell 로 반복 호출한다.
_do_reap_one() {
  # (⏺ prefix 허용) Claude TUI 가 완료 마커를 "⏺ ✅" 또는 들여쓰기로 렌더하는 경우 대응
  local PANE="" IDLE="15" TIMEOUT="900" DONE_PATTERN='^[[:space:]]*(⏺[[:space:]]*)?(✅|❌)' ALL=""
  parse_long_opts "$@"
  [ -z "$PANE" ] && die "reap: --pane=<ref> 필요" 2

  do_wait_idle --pane="$PANE" --idle="$IDLE" --timeout="$TIMEOUT"

  local screen rc
  screen=$(do_capture --pane="$PANE" 2>/dev/null); rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "died — surface '$PANE' not a terminal (자식 비정상 종료 의심; subagent 폴백 권장)" >&2
    echo "died $PANE"
    cbp_state_remove "$PANE"
    return 5
  fi

  printf '%s\n' "$screen" | tail -20

  if printf '%s\n' "$screen" | grep -qE "$DONE_PATTERN"; then
    if [ "${CBP_REAP_DRY_RUN:-0}" = "1" ]; then
      echo "would reap $PANE"
      return 0
    fi
    do_kill --pane="$PANE"
    echo "reaped $PANE"
  else
    echo "not done — kept $PANE"
  fi
}

# --pane 생략 또는 --all: state 의 모든 자식을 fast-probe 로 순회.
# 각 자식은 subshell 에서 _do_reap_one 실행 — do_wait_idle 의 exit4(timeout)나 do_kill
# die 가 루프 전체를 죽이지 않도록 rc 만 수집(무시), stdout 으로 완료 여부만 판별.
# 신생 자식(ts 기준 age < CBP_REAP_ORPHANS_GRACE_SEC)은 probe 자체를 skip — launch
# PTY warmup 중 오살 방지 (state 는 verify 전에 선기록되므로).
_do_reap_all() {
  local PANE="" IDLE="" TIMEOUT="" ALL=""
  parse_long_opts "$@"
  local idle="${IDLE:-2}"
  local timeout="${TIMEOUT:-10}"
  local grace_sec="${CBP_REAP_ORPHANS_GRACE_SEC:-30}"

  local sf
  sf=$(cbp_state_path)
  local snapshot=""
  [ -f "$sf" ] && snapshot=$(cat "$sf")

  local now
  now=$(date +%s)
  local reaped=0
  local kept=0

  while IFS= read -r line; do
    [ -z "$line" ] && continue

    local surface_ref ts_ref
    surface_ref=$(printf '%s' "$line" | grep -o 'surface=[^|]*' | sed 's/surface=//')
    ts_ref=$(printf '%s' "$line" | grep -o 'ts=[^|]*' | sed 's/ts=//')
    [ -z "$surface_ref" ] && continue

    # grace: ts 가 수치이고 age < grace_sec 이면 probe 자체 skip.
    # ts 비수치/결측 → 이 case 미매치 → 아래 probe 로 폴백(conservative).
    case "$ts_ref" in
      *[!0-9]*|'')
        ;;
      *)
        local age=$((now - ts_ref))
        if [ "$age" -lt "$grace_sec" ]; then
          echo "grace — kept $surface_ref"
          kept=$((kept + 1))
          continue
        fi
        ;;
    esac

    local out
    out=$( ( _do_reap_one --pane="$surface_ref" --idle="$idle" --timeout="$timeout" ) 2>&1 )
    printf '%s\n' "$out"

    if printf '%s\n' "$out" | grep -q '^reaped '; then
      reaped=$((reaped + 1))
    else
      kept=$((kept + 1))
    fi
  done <<EOF
$snapshot
EOF

  echo "reaped $reaped / kept $kept"
  return 0
}

do_reap() {
  local PANE="" IDLE="15" TIMEOUT="900" ALL=""
  parse_long_opts "$@"

  if [ -z "$PANE" ] || [ "$ALL" = "1" ]; then
    _do_reap_all "$@"
    return $?
  fi

  _do_reap_one "$@"
}

do_list() {
  # state file 우선 (CMUX_WORKSPACE_ID set 일 때)
  if [ -n "${CMUX_WORKSPACE_ID:-}" ]; then
    local state_surfaces
    state_surfaces=$(cbp_state_list 2>/dev/null || true)
    if [ -n "$state_surfaces" ]; then
      # lazy reconcile: tree 결과에 surface: 토큰이 하나라도 있을 때만 수행.
      # CMUX_BIN=echo mock 환경에서는 tree → "tree" 한 줄 (surface: 없음) → reconcile skip (state 유지).
      # 실 환경에서는 "surface:N" 형태가 있으면 reconcile.
      local tree_out
      tree_out=$("$CMUX_BIN" tree 2>/dev/null || true)
      local tree_has_surfaces=0
      printf '%s' "$tree_out" | grep -q 'surface:' && tree_has_surfaces=1 || true
      local reconciled=""
      local sf
      sf=$(cbp_state_path)
      while IFS= read -r sref; do
        [ -z "$sref" ] && continue
        if [ "$tree_has_surfaces" = "1" ] && ! printf '%s' "$tree_out" | grep -qF "$sref"; then
          # cmux tree 에 없는 dangling surface → state 에서 제거 (silent)
          cbp_state_remove "$sref"
        else
          reconciled="${reconciled}${sref}
"
        fi
      done <<STATEEOF
$state_surfaces
STATEEOF

      # reconcile 후 남은 surface 로 JSON 조립
      local json="["
      local first=1
      while IFS= read -r sref; do
        [ -z "$sref" ] && continue
        if [ "$first" = "1" ]; then
          first=0
        else
          json="${json},"
        fi
        json="${json}{\"id\":\"${sref}\",\"name\":\"${CBP_WORKSPACE_PREFIX}$(printf '%s' "$sref" | tr ':' '-')\"}"
      done <<JSONEOF
$reconciled
JSONEOF

      json="${json}]"
      printf '%s\n' "$json"
      return 0
    fi
  fi

  # 폴백: 기존 cbp- workspace 목록
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
  local self_surface="${CMUX_SURFACE_ID:-}"

  # ── state file 기반 surface cleanup ──────────────────────────────
  local surface_closed=0
  if [ -n "${CMUX_WORKSPACE_ID:-}" ]; then
    local state_surfaces
    state_surfaces=$(cbp_state_list 2>/dev/null || true)
    if [ -n "$state_surfaces" ]; then
      while IFS= read -r sref; do
        [ -z "$sref" ] && continue
        # 자기 surface 보호
        if [ -n "$self_surface" ] && [ "$sref" = "$self_surface" ]; then
          continue
        fi
        "$CMUX_BIN" close-surface --surface "$sref" 2>/dev/null || true
        cbp_state_remove "$sref"
        surface_closed=$((surface_closed + 1))
      done <<SFEOF
$state_surfaces
SFEOF
    fi
  fi
  echo "cmux-pane: cleaning $surface_closed cmux child surface(s)" >&2

  # ── 기존 cbp- workspace cleanup (호환) ───────────────────────────
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

# non-cmux 환경이면 advisory + exit 0 (호출자 무해)
_skip_if_non_cmux() {
  local detect_bin
  detect_bin="$(dirname "${BASH_SOURCE[0]}")/detect-pane-env.sh"
  [ -x "$detect_bin" ] || return 0  # detect 없으면 그냥 진행
  local env
  env=$("$detect_bin" 2>/dev/null) || return 0
  if [ "$env" != "cmux" ]; then
    echo "cmux-pane: non-cmux env, skipped" >&2
    exit 0
  fi
}

# PROGRESS_DRY_RUN=1 이면 명령 echo 후 exit 0
_maybe_dry_run() {
  if [ -n "${PROGRESS_DRY_RUN:-}" ]; then
    printf 'DRY_RUN: %s\n' "$*"
    exit 0
  fi
}

do_notify() {
  local TITLE="" BODY="" SUBTITLE="" WORKSPACE="" SURFACE=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --title=*)     TITLE="${1#*=}"; shift ;;
      --title)       TITLE="$2"; shift 2 ;;
      --body=*)      BODY="${1#*=}"; shift ;;
      --body)        BODY="$2"; shift 2 ;;
      --subtitle=*)  SUBTITLE="${1#*=}"; shift ;;
      --subtitle)    SUBTITLE="$2"; shift 2 ;;
      --workspace=*) WORKSPACE="${1#*=}"; shift ;;
      --workspace)   WORKSPACE="$2"; shift 2 ;;
      --surface=*)   SURFACE="${1#*=}"; shift ;;
      --surface)     SURFACE="$2"; shift 2 ;;
      *) shift ;;
    esac
  done
  [ -z "$TITLE" ] && die "notify: --title 필요" 2
  WORKSPACE=$(printf '%s' "$WORKSPACE" | tr -d '[:space:]')
  SURFACE=$(printf '%s' "$SURFACE" | tr -d '[:space:]')

  local args=(notify --title "$TITLE")
  [ -n "$BODY" ]      && args+=(--body "$BODY")
  [ -n "$SUBTITLE" ]  && args+=(--subtitle "$SUBTITLE")
  [ -n "$WORKSPACE" ] && args+=(--workspace "$WORKSPACE")
  [ -n "$SURFACE" ]   && args+=(--surface "$SURFACE")

  _maybe_dry_run "$CMUX_BIN" "${args[@]}"
  _skip_if_non_cmux
  "$CMUX_BIN" "${args[@]}" || die "notify: 실패" 3
}

do_set_status() {
  local KEY="$1"; shift
  local VALUE="$1"; shift
  local ICON="" COLOR="" WORKSPACE=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --icon=*)      ICON="${1#*=}"; shift ;;
      --icon)        ICON="$2"; shift 2 ;;
      --color=*)     COLOR="${1#*=}"; shift ;;
      --color)       COLOR="$2"; shift 2 ;;
      --workspace=*) WORKSPACE="${1#*=}"; shift ;;
      --workspace)   WORKSPACE="$2"; shift 2 ;;
      *) shift ;;
    esac
  done
  WORKSPACE=$(printf '%s' "$WORKSPACE" | tr -d '[:space:]')

  local args=(set-status "$KEY" "$VALUE")
  [ -n "$ICON" ]      && args+=(--icon "$ICON")
  [ -n "$COLOR" ]     && args+=(--color "$COLOR")
  [ -n "$WORKSPACE" ] && args+=(--workspace "$WORKSPACE")

  _maybe_dry_run "$CMUX_BIN" "${args[@]}"
  _skip_if_non_cmux
  "$CMUX_BIN" "${args[@]}" || die "set-status: 실패" 3
}

# ----------------------------------------------------------------
# do_reap_orphans — cross-workspace 에 잔존하는 dead cmux 자식 surface 회수.
#
# 부모 세션이 finish 없이 종료해 영구 잔존하는 dead surface 를 모든 state file 에 걸쳐
# 안전하게 회수. 살아있는(alive) surface 는 건드리지 않음.
#
# 알고리즘 (2-phase lock — 병렬 launch append 유실 방지):
#   1. state dir(CBP_STATE_DIR, 디폴트 ~/.cache/cbp) 의 children-*.json 전체 스캔.
#   2. state file 별:
#      a. [lock 하] snapshot read (파일 내용 복사).
#      b. [lock 밖] snapshot 의 각 줄 "surface=<ref>|...|ts=<epoch>|ws=<WS>" 파싱해 liveness 판정:
#         - self surface (CMUX_SURFACE_ID 일치) → skip(보존).
#         - ts 가 수치이고 now 기준 CBP_REAP_ORPHANS_GRACE_SEC(디폴트 30) 이내
#           → liveness 검사 자체 skip, 보존 (launch PTY warmup 오살 방지).
#           ts 비수치/결측 → grace 미적용(기존 liveness 검사).
#           주의: CBP_LAUNCH_VERIFY_TRIES/CBP_WARMUP_SLEEP 확대 시 warmup 이 grace 초를
#           넘을 수 있음 — 그 경우 grace 상향 필요.
#         - read-screen --surface <ref> [--workspace <WS>] rc0 → alive → 건드리지 않음.
#           (ws_ref 있으면 --workspace 포함 — cross-workspace surface 오판 방지)
#         - rc 비0 → dead:
#             dry-run(CBP_REAP_ORPHANS_DRY_RUN=1) → "would reap <ref>" 출력, 줄 유지(rewrite 없음).
#             아니면 → close-surface --surface <ref> [--workspace <WS>] (ws_ref 비면 생략,
#             best-effort) + dead-line 목록에 추가.
#         이 구간은 cmux CLI 왕복(느림/hang 가능)이라 lock 밖에서 수행 — lock 쥔 채 돌리면
#         `_cbp_lock_acquire` 가 timeout 없는 spin 이라 병렬 launch 가 정지함(금지).
#      c. [lock 하, dead-line 있고 !dry-run 시만] 파일 재-read → dead-line 과 정확히 일치하는
#         줄만 제거하고 rewrite. b 단계 동안 다른 프로세스가 append 한 새 줄은 매칭되지 않으므로
#         그대로 보존됨. 빈 파일 되면 rm.
#   3. CMUX_BIN 미존재/실패 시 conservative exit 0.
#   4. 요약: "reaped N, kept M[, dry-run]" stdout.
# ----------------------------------------------------------------
do_reap_orphans() {
  # CMUX_BIN 존재 확인 — 미존재 시 no-op exit 0
  if ! command -v "$CMUX_BIN" >/dev/null 2>&1; then
    echo "cmux-pane reap-orphans: CMUX_BIN('$CMUX_BIN') 미존재 — skip" >&2
    return 0
  fi

  local state_dir="${CBP_STATE_DIR:-${HOME}/.cache/cbp}"
  local dry_run="${CBP_REAP_ORPHANS_DRY_RUN:-0}"
  local self_surface="${CMUX_SURFACE_ID:-}"
  local grace_sec="${CBP_REAP_ORPHANS_GRACE_SEC:-30}"

  # state dir 없으면 no-op
  if [ ! -d "$state_dir" ]; then
    echo "reaped 0, kept 0"
    return 0
  fi

  local total_reaped=0
  local total_kept=0
  local now
  now=$(date +%s)

  # children-*.json 全스캔
  local sf
  for sf in "$state_dir"/children-*.json; do
    [ -f "$sf" ] || continue   # glob 불일치(no match) 시 스킵

    local lockpath="${sf}.lock"

    # ── phase a: lock 하 snapshot read ──────────────────────────────────
    _cbp_lock_acquire "$lockpath"
    local snapshot
    snapshot=$(cat "$sf" 2>/dev/null || true)
    _cbp_lock_release "${lockpath}.d"

    # ── phase b: lock 밖 liveness 판정 ──────────────────────────────────
    local dead_lines=""
    local sf_reaped=0
    local sf_kept=0

    while IFS= read -r line; do
      [ -z "$line" ] && continue

      # surface=<ref> 추출
      local surface_ref
      surface_ref=$(printf '%s' "$line" | grep -o 'surface=[^|]*' | sed 's/surface=//')
      # ws=<WS> 추출
      local ws_ref
      ws_ref=$(printf '%s' "$line" | grep -o 'ws=[^|]*' | sed 's/ws=//')
      # ts=<epoch> 추출
      local ts_ref
      ts_ref=$(printf '%s' "$line" | grep -o 'ts=[^|]*' | sed 's/ts=//')

      if [ -z "$surface_ref" ]; then
        # 파싱 불가 줄 → 보존 (conservative)
        sf_kept=$((sf_kept + 1))
        continue
      fi

      # self surface → skip (보존)
      if [ -n "$self_surface" ] && [ "$surface_ref" = "$self_surface" ]; then
        sf_kept=$((sf_kept + 1))
        continue
      fi

      # 신생 grace: ts 가 수치이고 grace 이내면 liveness 검사 자체 skip.
      # 비수치/결측(빈 문자열 포함) → 이 case 에 안 걸려 기존 동작(liveness 검사)으로 폴백.
      case "$ts_ref" in
        *[!0-9]*|'')
          ;;
        *)
          local age=$((now - ts_ref))
          if [ "$age" -lt "$grace_sec" ]; then
            sf_kept=$((sf_kept + 1))
            continue
          fi
          ;;
      esac

      # 생존 확인: read-screen rc0=alive, 비0=dead.
      # cross-workspace surface 는 --workspace 없이 조회 시 "not found" 로 dead 오판 위험.
      # ws_ref 가 있으면 --workspace 도 함께 전달 (close-surface 와 동일 컨텍스트).
      local _liveness_cmd=("$CMUX_BIN" read-screen --surface "$surface_ref")
      [ -n "$ws_ref" ] && _liveness_cmd+=(--workspace "$ws_ref")
      if "${_liveness_cmd[@]}" >/dev/null 2>&1; then
        # alive → 보존
        sf_kept=$((sf_kept + 1))
      else
        # dead
        if [ "$dry_run" = "1" ]; then
          echo "would reap $surface_ref"
          sf_kept=$((sf_kept + 1))
        else
          # best-effort close-surface (실패 무시). ws_ref 비면 --workspace 생략 (liveness 와 동일 패턴).
          local _close_cmd=("$CMUX_BIN" close-surface --surface "$surface_ref")
          [ -n "$ws_ref" ] && _close_cmd+=(--workspace "$ws_ref")
          "${_close_cmd[@]}" >/dev/null 2>&1 || true
          dead_lines="${dead_lines}${line}
"
          sf_reaped=$((sf_reaped + 1))
        fi
      fi
    done <<EOF
$snapshot
EOF

    total_reaped=$((total_reaped + sf_reaped))
    total_kept=$((total_kept + sf_kept))

    # ── phase c: lock 하 재-read → dead-line 만 제거하고 rewrite ────────────
    # dry-run 은 rewrite 자체가 없으므로 이 단계 불필요. dead-line 없으면(전부 alive/grace/self)
    # rewrite 할 것도 없으므로 lock 재획득 자체를 skip.
    if [ "$dry_run" != "1" ] && [ -n "$dead_lines" ]; then
      _cbp_lock_acquire "$lockpath"
      local current
      current=$(cat "$sf" 2>/dev/null || true)
      local remaining=""
      while IFS= read -r cur_line; do
        [ -z "$cur_line" ] && continue
        if printf '%s\n' "$dead_lines" | grep -qxF "$cur_line"; then
          continue
        fi
        remaining="${remaining}${cur_line}
"
      done <<EOF2
$current
EOF2

      if [ -z "$(printf '%s' "$remaining" | tr -d '[:space:]')" ]; then
        rm -f "$sf"
      else
        printf '%s' "$remaining" > "$sf"
      fi
      _cbp_lock_release "${lockpath}.d"
    fi
  done

  local summary="reaped ${total_reaped}, kept ${total_kept}"
  [ "$dry_run" = "1" ] && summary="${summary}, dry-run"
  echo "$summary"
  return 0
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
    reap)      do_reap "$@" ;;
    reap-orphans) do_reap_orphans "$@" ;;
    list)      do_list "$@" ;;
    cleanup)   do_cleanup "$@" ;;
    status)    do_status "$@" ;;
    notify)     do_notify "$@" ;;
    set-status)
      [ $# -lt 2 ] && die "set-status: <key> <value> 필요" 2
      do_set_status "$@" ;;
    -h|--help|help) usage ;;
    *) die "unknown command: $cmd" 2 ;;
  esac
}

main "$@"
