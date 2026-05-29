#!/usr/bin/env bash
# cmux-pane.sh — 얇은 cmux CLI wrapper.
# tmux-pane.sh 와 명령 표면 정렬. 명령: launch / send / capture / wait-idle / kill / list / cleanup / status.
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
#
# 환경변수:
#   CMUX_BIN                  — cmux 바이너리 경로 (미지정 시 PATH 의 cmux)
#   CBP_WORKSPACE_PREFIX       — workspace 이름 prefix (디폴트 cbp-)
#   CBP_STATE_FILE             — state file 경로 override (디폴트: ~/.cache/cbp/children-<ws_sanitized>.json)
#                                ws_sanitized = ${CMUX_WORKSPACE_ID//[:\/]/_}
#   CBP_LIST_LINES             — list 명령 입력 mock (테스트용. set 시 실제 cmux 호출 생략)
#   CLAUDE_FAKE_SELF_CMUX_WS   — 자기 workspace ref mock (테스트용)
#   FORCE_SELF_KILL            — 자기 workspace kill 거부 우회. surface kill 은 self-surface 만 거부 (FORCE_SELF_KILL 영향 없음).
#   PROGRESS_DRY_RUN           — notify/set-status 가 실제 cmux 호출 없이 명령 echo 후 exit 0 (테스트용)

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
  local cmd="${1:-zsh}"
  local name="${CBP_WORKSPACE_PREFIX}$(rand_hex6)"

  # CMUX_WORKSPACE_ID set → grid split 분기 (부모 workspace 안에서 surface 생성)
  if [ -n "${CMUX_WORKSPACE_ID:-}" ]; then
    _do_launch_grid "$cmd" "$name"
    return $?
  fi

  # CMUX_WORKSPACE_ID unset → 기존 new-workspace 흐름
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

# do_launch 의 grid split 내부 구현 (CMUX_WORKSPACE_ID 가 set 인 경우).
# 라운드로빈 방향: count=0 → right (첫 자식), count=1 → down, count=2 → right, count=3 → down, ...
# CBP_SPLIT_POLICY env 로 방향 override 가능 (Slice A3 에서 확장 예정).
_do_launch_grid() {
  local _cmd="$1"  # cmd 는 new-pane/new-split 미지원 — Slice A3 에서 send 로 전달 예정
  local name="$2"

  local sf lockpath
  sf=$(cbp_state_path)
  lockpath="${sf}.lock"

  local surface_ref raw_out

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
  else
    # 후속 자식: 직전 자식 surface 를 기준으로 split
    local prev_surface
    prev_surface=$(tail -1 "$sf" | grep -o 'surface=[^|]*' | sed 's/surface=//')

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
  fi

  # surface ref 공백 trim + fallback
  surface_ref=$(printf '%s' "$surface_ref" | tr -d '[:space:]')
  [ -z "$surface_ref" ] && surface_ref="surface:unknown"

  # state file 기록 (lock 보유 중 — unlocked 직접 호출로 재진입 회피)
  _cbp_state_append_unlocked "$sf" "$surface_ref" "$name"

  # ── CRITICAL SECTION 끝 — release 후 후처리는 lock 밖 ──────────────────────
  if [ "$_locked" = "1" ]; then
    _cbp_lock_release "${lockpath}.d"
    _locked=0
  fi

  # rename-tab (stdout/stderr 모두 redirect — rename-tab 이 OK 한 줄 stdout 출력하므로)
  "$CMUX_BIN" rename-tab --surface "$surface_ref" "$name" >/dev/null 2>&1 || true

  # PTY warmup — surface 신규 생성 후 underlying tty 가 첫 send 입력을 swallow 하는 경우 우회.
  # send-key Enter 로 PTY 강제 attach + 짧은 sleep. 우회: CBP_DISABLE_WARMUP=1.
  if [ "${CBP_DISABLE_WARMUP:-0}" != "1" ]; then
    "$CMUX_BIN" send-key --surface "$surface_ref" Enter >/dev/null 2>&1 || true
    sleep "${CBP_WARMUP_SLEEP:-0.5}"
  fi

  printf '%s\n' "$surface_ref"
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
    notify)     do_notify "$@" ;;
    set-status)
      [ $# -lt 2 ] && die "set-status: <key> <value> 필요" 2
      do_set_status "$@" ;;
    -h|--help|help) usage ;;
    *) die "unknown command: $cmd" 2 ;;
  esac
}

main "$@"
