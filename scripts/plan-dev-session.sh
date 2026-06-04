#!/usr/bin/env bash
# plan-dev-session.sh — plan-dev 세션 marker 헬퍼.
#
# 사용:
#   plan-dev-session.sh start [--base=<branch>] [--total=<n>] [--quiet]
#   plan-dev-session.sh query [--json|--key=<field>]
#   plan-dev-session.sh progress [--inc] [--set-done=<n>] [--set-total=<n>]
#   plan-dev-session.sh clear
#
# marker 경로: $(git rev-parse --git-common-dir)/plan-dev-session.json
# 키: start_ref, base_branch, work_branch, start_ts, start_pid, auto_branch,
#     total_slices, done_slices

set -uo pipefail

usage() {
  cat >&2 <<'USAGE'
plan-dev-session.sh <command> [args]

commands:
  start [--base=<branch>] [--total=<n>] [--quiet]          세션 marker 생성
  query [--json|--key=<field>]                              marker 내용 조회
  progress [--inc] [--set-done=<n>] [--set-total=<n>]      진행률 업데이트/조회
  clear                                                      marker 삭제
USAGE
  exit 2
}

die() { echo "plan-dev-session: $*" >&2; exit "${2:-1}"; }

# JSON 키 하나 추출 (jq 우선, python3 폴백)
json_get() {
  local file="$1" key="$2"
  if command -v jq >/dev/null 2>&1; then
    jq -r ".$key // empty" "$file"
  else
    python3 -c "
import json, sys
try:
    d = json.load(open('$file'))
    v = d.get('$key', '')
    print(v if v is not None else '')
except Exception as e:
    print('', file=sys.stderr)
    sys.exit(1)
"
  fi
}

# marker 경로 결정 (git-common-dir 기반)
marker_path() {
  local common_dir
  common_dir="$(git rev-parse --git-common-dir 2>/dev/null)" \
    || die "git repo 가 아님"
  echo "${common_dir}/plan-dev-session.json"
}

# ISO 8601 UTC 타임스탬프
iso_ts() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# PID 살아있는지 확인
pid_alive() {
  local pid="$1"
  kill -0 "$pid" 2>/dev/null
}

# 24시간 이내인지 확인 (start_ts 와 비교)
within_24h() {
  local ts="$1"
  # ISO 8601 UTC → epoch
  local epoch_now epoch_ts
  epoch_now=$(date -u +%s)
  # macOS / GNU date 양쪽 지원
  if date --version >/dev/null 2>&1; then
    # GNU date
    epoch_ts=$(date -d "$ts" +%s 2>/dev/null) || return 1
  else
    # BSD date (macOS)
    # "2024-01-02T03:04:05Z" → "20240102030405"
    local clean
    clean="${ts//[-:]}"         # "20240102T030405Z"
    clean="${clean//T}"         # "20240102030405Z"
    clean="${clean//Z}"         # "20240102030405"
    epoch_ts=$(date -ujf "%Y%m%d%H%M%S" "$clean" +%s 2>/dev/null) || return 1
  fi
  local diff=$(( epoch_now - epoch_ts ))
  [ "$diff" -lt 86400 ]
}

# base_branch 결정: --base 인자 > origin/develop > origin/main > origin/master
#                   > 로컬 develop > main > master
resolve_base_branch() {
  local forced="${1:-}"
  if [ -n "$forced" ]; then
    echo "$forced"
    return 0
  fi

  # origin/* 검사
  for ref in origin/develop origin/main origin/master; do
    if git rev-parse --verify "$ref" >/dev/null 2>&1; then
      echo "$ref"
      return 0
    fi
  done

  # 로컬 브랜치 검사
  for br in develop main master; do
    if git rev-parse --verify "$br" >/dev/null 2>&1; then
      echo "$br"
      return 0
    fi
  done

  # 부재
  return 1
}

# ─────────────────────────────────────────
# subcommand: start
# ─────────────────────────────────────────
do_start() {
  local base_arg="" quiet=0 total=0

  for arg in "$@"; do
    case "$arg" in
      --base=*)  base_arg="${arg#*=}" ;;
      --quiet)   quiet=1 ;;
      --total=*) total="${arg#*=}" ;;
      *)         ;;
    esac
  done

  # detached HEAD 검사
  local cur_branch
  cur_branch=$(git symbolic-ref --short HEAD 2>/dev/null) || {
    echo "plan-dev-session: detached HEAD 에서 plan-dev 시작 불가" >&2
    exit 2
  }

  # marker 경로
  local marker
  marker="$(marker_path)"

  # 기존 marker 검사
  local preserve_ts="" preserve_ref=""
  if [ -f "$marker" ]; then
    local existing_pid existing_ts existing_ref
    existing_pid=$(json_get "$marker" "start_pid" 2>/dev/null) || existing_pid=""
    existing_ts=$(json_get "$marker" "start_ts" 2>/dev/null) || existing_ts=""
    existing_ref=$(json_get "$marker" "start_ref" 2>/dev/null) || existing_ref=""

    if [ -n "$existing_pid" ] && [ -n "$existing_ts" ]; then
      if pid_alive "$existing_pid" && within_24h "$existing_ts"; then
        echo "plan-dev-session: 이미 진행 중 (PID=${existing_pid}, 시작=${existing_ts})" >&2
        exit 0
      fi
    fi
    # 재진입(dead pid + within_24h): start_ts/start_ref 보존 — progress start 재호출이 clobber 하던 버그 fix
    if [ -n "$existing_ts" ] && within_24h "$existing_ts"; then
      preserve_ts="$existing_ts"
      preserve_ref="$existing_ref"
    fi
    # stale → .bak 으로 이동
    mv "$marker" "${marker}.bak"
  fi

  # base_branch 결정
  local base_branch=""
  if base_branch="$(resolve_base_branch "$base_arg")"; then
    : # ok
  else
    echo "plan-dev-session: base_branch 를 찾을 수 없음 (origin/develop, origin/main, origin/master, develop, main, master 모두 부재). marker 없이 통과." >&2
    exit 0
  fi

  # 현재 HEAD SHA (within_24h 재진입이면 원본 보존)
  local start_ref
  start_ref=$(git rev-parse HEAD)
  [ -n "$preserve_ref" ] && start_ref="$preserve_ref"

  # auto_branch: 현재 branch == base 이면 true
  local auto_branch="false"
  # base_branch 가 origin/* 이면 local part 와 비교
  local base_local="${base_branch#origin/}"
  if [ "$cur_branch" = "$base_local" ] || [ "$cur_branch" = "$base_branch" ]; then
    auto_branch="true"
  fi

  local start_ts
  start_ts="$(iso_ts)"
  [ -n "$preserve_ts" ] && start_ts="$preserve_ts"

  # JSON 작성 (python3 사용 — sh 에서 JSON 직접 쓰면 escape 문제)
  python3 -c "
import json
d = {
    'start_ref':    '$start_ref',
    'base_branch':  '$base_branch',
    'work_branch':  '$cur_branch',
    'start_ts':     '$start_ts',
    'start_pid':    $$,
    'auto_branch':  $( [ "$auto_branch" = "true" ] && echo "True" || echo "False" ),
    'total_slices': $total,
    'done_slices':  0,
}
with open('$marker', 'w') as f:
    json.dump(d, f, indent=2)
    f.write('\n')
"

  if [ "$quiet" = "0" ]; then
    echo "$marker"
  fi
}

# ─────────────────────────────────────────
# subcommand: query
# ─────────────────────────────────────────
do_query() {
  local output_mode="json" key_field=""

  for arg in "$@"; do
    case "$arg" in
      --json)    output_mode="json" ;;
      --key=*)   output_mode="key"; key_field="${arg#*=}" ;;
      *)         ;;
    esac
  done

  local marker
  marker="$(marker_path)"

  if [ ! -f "$marker" ]; then
    echo "plan-dev-session: 마커 없음" >&2
    exit 1
  fi

  if [ "$output_mode" = "json" ]; then
    cat "$marker"
  else
    json_get "$marker" "$key_field"
  fi
}

# ─────────────────────────────────────────
# subcommand: progress
# ─────────────────────────────────────────
do_progress() {
  local inc=0 set_done="" set_total=""

  for arg in "$@"; do
    case "$arg" in
      --inc)          inc=1 ;;
      --set-done=*)   set_done="${arg#*=}" ;;
      --set-total=*)  set_total="${arg#*=}" ;;
      *)              ;;
    esac
  done

  local marker
  marker="$(marker_path)"

  if [ ! -f "$marker" ]; then
    echo "plan-dev-session: 마커 없음" >&2
    exit 1
  fi

  INC="$inc" SET_DONE="$set_done" SET_TOTAL="$set_total" MARKER_FILE="$marker" \
  python3 -c "
import json, os

f = os.environ['MARKER_FILE']
inc = os.environ['INC'] == '1'
set_done = os.environ.get('SET_DONE', '')
set_total = os.environ.get('SET_TOTAL', '')

d = json.load(open(f))
done = int(d.get('done_slices', 0))
total = int(d.get('total_slices', 0))

if inc:
    done += 1
if set_done != '':
    done = int(set_done)
if set_total != '':
    total = int(set_total)

d['done_slices'] = done
d['total_slices'] = total

if inc or set_done != '' or set_total != '':
    with open(f, 'w') as fp:
        json.dump(d, fp, indent=2)
        fp.write('\n')

if total > 0:
    pct = done * 100 // total
    print(str(done) + '/' + str(total) + ' (' + str(pct) + '%)')
else:
    print(str(done))
"
}

# ─────────────────────────────────────────
# subcommand: clear
# ─────────────────────────────────────────
do_clear() {
  local marker
  marker="$(marker_path)"

  if [ -f "$marker" ]; then
    rm "$marker"
    echo "cleared"
  else
    echo "no marker"
  fi
}

# ─────────────────────────────────────────
# dispatch
# ─────────────────────────────────────────
[ $# -ge 1 ] || usage

CMD="$1"; shift

case "$CMD" in
  start)    do_start "$@" ;;
  query)    do_query "$@" ;;
  progress) do_progress "$@" ;;
  clear)    do_clear "$@" ;;
  *)        usage ;;
esac
