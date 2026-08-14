#!/usr/bin/env bash
# reap-agents.sh — 자식(spawn) 계보 원장 + 회수.
#
# 문제: Claude 세션 레코드(~/.claude/sessions/<pid>.json)에는 **부모 필드가 없다**.
# cmux surface / tmux pane / bg 세션 / subagent 를 띄운 "원천" 이 어디인지 시스템이
# 기록하지 않으므로, 회수 시 "누가 내 자식인가" 를 알 수 없다. 그래서 기존 회수기는
# 전역 스윕(reap-orphans)에 의존했고, 그게 남의 surface·자기 자신까지 닫는 사고를 냈다.
#
# 해결: **띄울 때 원장에 적고, 회수할 때 원장만 본다.**
#   - 원장 경로: ${CBP_LEDGER_DIR:-~/.cache/cbp/ledger}/<origin>.jsonl
#   - origin = 이 세션(부모)의 식별자. **원장에 자기 자신은 절대 안 들어간다** →
#     구조적으로 자기 자신을 회수할 수 없다 (자살 버그 계열의 근본 차단).
#   - 부모가 죽은 원장 = 고아 → 그 자식 전부 회수 대상.
#
# 사용:
#   reap-agents.sh origin
#   reap-agents.sh record --kind=cmux --ref=surface:42 [--ws=<ws>] [--pid=<pid>] [--label=<t>]
#   reap-agents.sh list [--origin=<id>]
#   reap-agents.sh reap [--apply] [--orphans] [--idle-hours=<n>]
#   reap-agents.sh audit          # 회수 안 하고 현황만 (bg 세션 전체 포함)
#
# 환경변수:
#   CBP_LEDGER_DIR      원장 디렉토리 override (테스트용)
#   CBP_ORIGIN_ID       origin 강제 지정 (테스트용)
#   CBP_SESSIONS_DIR    Claude 세션 레코드 디렉토리 override (기본 ~/.claude/sessions)
#   CMUX_BIN / TMUX_BIN 바이너리 override (기본 cmux / tmux)
#   REAP_AGENTS_DRY_RUN=1  --apply 를 무시하고 항상 dry-run
#
# 종료코드: 0 정상 / 2 사용법·치명오류

set -uo pipefail

LEDGER_DIR="${CBP_LEDGER_DIR:-$HOME/.cache/cbp/ledger}"
SESSIONS_DIR="${CBP_SESSIONS_DIR:-$HOME/.claude/sessions}"
CMUX_BIN="${CMUX_BIN:-cmux}"
TMUX_BIN="${TMUX_BIN:-tmux}"

usage() {
  sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
  exit 2
}

# ── 조상 pid 체인 (자기 보호의 1차 방어선) ─────────────────────────
_pid_chain() {
  local p="${1:-$$}" i=0
  while [ "$p" -gt 1 ] && [ "$i" -lt 40 ]; do
    printf '%s\n' "$p"
    p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')
    [ -z "$p" ] && break
    i=$((i + 1))
  done
}

# 조상 pid 판정. **파이프 금지** — `_pid_chain | grep -q` 는 grep 이 매치 즉시
# 파이프를 닫아 _pid_chain 이 SIGPIPE(141)로 죽고, `set -o pipefail` 이 그 실패를
# 파이프라인 결과로 삼아 "매치했는데 거짓" 이 된다. 자기 보호가 조용히 무력화되는
# 형태라 특히 위험하다.
_is_ancestor_pid() {
  local target="$1" p
  [ -n "$target" ] || return 1
  for p in $(_pid_chain "$$"); do
    [ "$p" = "$target" ] && return 0
  done
  return 1
}

# ── origin 결정: env override → 세션 레코드(pid 체인 매치) → pid 폴백 ──
do_origin() {
  if [ -n "${CBP_ORIGIN_ID:-}" ]; then
    printf '%s\n' "$CBP_ORIGIN_ID"
    return 0
  fi
  local chain
  chain=$(_pid_chain "$$" | tr '\n' ' ')
  if [ -d "$SESSIONS_DIR" ]; then
    local found
    found=$(CHAIN="$chain" SDIR="$SESSIONS_DIR" python3 - <<'PY' 2>/dev/null
import json, os, glob
chain = set(os.environ.get("CHAIN", "").split())
for f in glob.glob(os.path.join(os.environ["SDIR"], "*.json")):
    try:
        d = json.load(open(f))
    except Exception:
        continue
    if str(d.get("pid")) in chain and d.get("sessionId"):
        print(d["sessionId"]); break
PY
)
    if [ -n "$found" ]; then printf '%s\n' "$found"; return 0; fi
  fi
  printf 'pid-%s\n' "$(_pid_chain "$$" | tail -1)"
}

_ledger_path() { printf '%s/%s.jsonl\n' "$LEDGER_DIR" "$1"; }

# ── record: 자식 1개 기록 ──────────────────────────────────────────
do_record() {
  local kind="" ref="" ws="" pid="" label=""
  for a in "$@"; do
    case "$a" in
      --kind=*)  kind="${a#*=}" ;;
      --ref=*)   ref="${a#*=}" ;;
      --ws=*)    ws="${a#*=}" ;;
      --pid=*)   pid="${a#*=}" ;;
      --label=*) label="${a#*=}" ;;
    esac
  done
  [ -n "$kind" ] && [ -n "$ref" ] || { echo "reap-agents: record 는 --kind 와 --ref 필수" >&2; exit 2; }
  case "$kind" in cmux|tmux|bg|subagent) ;; *) echo "reap-agents: 알 수 없는 kind: $kind" >&2; exit 2 ;; esac

  # 자기 자신 기록 거부 — 원장에 자신이 없으면 자살이 구조적으로 불가능하다.
  if [ -n "${CMUX_SURFACE_ID:-}" ] && [ "$ref" = "$CMUX_SURFACE_ID" ]; then
    echo "reap-agents: self surface 기록 거부 ($ref)" >&2; exit 2
  fi
  if [ -n "${CBP_SELF_PANE:-}" ] && [ "$ref" = "$CBP_SELF_PANE" ]; then
    echo "reap-agents: self pane 기록 거부 ($ref)" >&2; exit 2
  fi
  if _is_ancestor_pid "$pid"; then
    echo "reap-agents: 조상 pid 기록 거부 ($pid)" >&2; exit 2
  fi

  local origin; origin=$(do_origin)
  mkdir -p "$LEDGER_DIR"
  KIND="$kind" REF="$ref" WS="$ws" PID="$pid" LABEL="$label" \
  ORIGIN="$origin" OUT="$(_ledger_path "$origin")" python3 - <<'PY'
import json, os, time
row = {
    "kind": os.environ["KIND"], "ref": os.environ["REF"],
    "ws": os.environ.get("WS") or None, "pid": os.environ.get("PID") or None,
    "label": os.environ.get("LABEL") or None,
    "origin": os.environ["ORIGIN"], "ts": int(time.time()),
}
with open(os.environ["OUT"], "a") as f:
    f.write(json.dumps(row, ensure_ascii=False) + "\n")
PY
  echo "recorded: $kind $ref → $(_ledger_path "$origin")"
}

do_list() {
  local origin=""
  for a in "$@"; do case "$a" in --origin=*) origin="${a#*=}" ;; esac; done
  [ -n "$origin" ] || origin=$(do_origin)
  local f; f=$(_ledger_path "$origin")
  [ -f "$f" ] || { echo "(원장 없음: $f)"; return 0; }
  cat "$f"
}

# ── origin 이 살아있는지 (세션 레코드의 pid 로 판정) ────────────────
_origin_alive() {
  local origin="$1"
  [ -d "$SESSIONS_DIR" ] || return 1
  ORIGIN="$origin" SDIR="$SESSIONS_DIR" python3 - <<'PY' 2>/dev/null
import json, os, glob, sys
target = os.environ["ORIGIN"]
for f in glob.glob(os.path.join(os.environ["SDIR"], "*.json")):
    try: d = json.load(open(f))
    except Exception: continue
    if d.get("sessionId") == target:
        pid = d.get("pid")
        try:
            os.kill(int(pid), 0); sys.exit(0)
        except Exception:
            sys.exit(1)
sys.exit(1)
PY
}

# ── 자식 1개 회수 ─────────────────────────────────────────────────
_reap_one() {
  local kind="$1" ref="$2" ws="$3" pid="$4" apply="$5"
  local cmd=""
  case "$kind" in
    cmux)     cmd="$CMUX_BIN close-surface --surface $ref"; [ -n "$ws" ] && cmd="$cmd --workspace $ws" ;;
    tmux)     cmd="$TMUX_BIN kill-pane -t $ref" ;;
    bg)       [ -n "$pid" ] || { echo "  skip(bg, pid 없음) $ref"; return 0; }
              cmd="kill $pid" ;;
    subagent) echo "  skip(subagent — 인프로세스, 별도 회수 불필요) $ref"; return 0 ;;
  esac
  if [ "$apply" = "1" ]; then
    eval "$cmd" >/dev/null 2>&1 && echo "  reaped  $kind $ref" || echo "  fail    $kind $ref ($cmd)"
  else
    echo "  [dry-run] $cmd"
  fi
}

do_reap() {
  local apply=0 orphans=0
  for a in "$@"; do
    case "$a" in
      --apply)   apply=1 ;;
      --orphans) orphans=1 ;;
    esac
  done
  [ "${REAP_AGENTS_DRY_RUN:-0}" = "1" ] && apply=0

  local self_origin; self_origin=$(do_origin)
  mkdir -p "$LEDGER_DIR"

  local total=0
  shopt -s nullglob
  for f in "$LEDGER_DIR"/*.jsonl; do
    local origin; origin=$(basename "$f" .jsonl)
    local is_self=0; [ "$origin" = "$self_origin" ] && is_self=1
    if [ "$is_self" = "0" ]; then
      # 남의 원장 — --orphans 이고 그 origin 이 죽었을 때만 손댄다.
      [ "$orphans" = "1" ] || { echo "skip 원장(타 세션, --orphans 아님): $origin"; continue; }
      if _origin_alive "$origin"; then
        echo "skip 원장(origin 살아있음 — 원천 보존): $origin"; continue
      fi
      echo "고아 원장(origin 사망): $origin"
    else
      echo "내 원장: $origin"
    fi

    while IFS= read -r line; do
      [ -z "$line" ] && continue
      local kind ref ws pid
      kind=$(printf '%s' "$line" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("kind",""))' 2>/dev/null)
      ref=$(printf  '%s' "$line" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("ref",""))'  2>/dev/null)
      ws=$(printf   '%s' "$line" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("ws") or "")' 2>/dev/null)
      pid=$(printf  '%s' "$line" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("pid") or "")' 2>/dev/null)
      [ -n "$ref" ] || continue
      # 2차 방어선: 어떤 경로로든 자기 자신이면 절대 회수하지 않는다.
      if [ -n "${CMUX_SURFACE_ID:-}" ] && [ "$ref" = "$CMUX_SURFACE_ID" ]; then
        echo "  keep(self surface) $ref"; continue
      fi
      if _is_ancestor_pid "$pid"; then
        echo "  keep(self pid chain) $pid"; continue
      fi
      _reap_one "$kind" "$ref" "$ws" "$pid" "$apply"
      total=$((total + 1))
    done < "$f"

    if [ "$apply" = "1" ]; then
      : > "$f"
      [ "$is_self" = "0" ] && rm -f "$f"
    fi
  done
  shopt -u nullglob
  echo "대상 $total 건 (apply=$apply)"
}

# ── audit: 회수 없이 현황만 ────────────────────────────────────────
do_audit() {
  echo "origin: $(do_origin)"
  echo "원장 디렉토리: $LEDGER_DIR"
  shopt -s nullglob
  local n=0
  for f in "$LEDGER_DIR"/*.jsonl; do
    n=$((n + 1))
    printf '  %-40s %s줄\n' "$(basename "$f")" "$(wc -l < "$f" | tr -d ' ')"
  done
  shopt -u nullglob
  [ "$n" -eq 0 ] && echo "  (원장 없음)"
  echo
  echo "Claude 세션 레코드 ($SESSIONS_DIR):"
  SDIR="$SESSIONS_DIR" python3 - <<'PY' 2>/dev/null || echo "  (조회 실패)"
import json, os, glob, time
now = time.time()
rows = []
for f in glob.glob(os.path.join(os.environ["SDIR"], "*.json")):
    try: d = json.load(open(f))
    except Exception: continue
    pid = d.get("pid")
    try:
        os.kill(int(pid), 0); alive = True
    except Exception:
        alive = False
    rows.append((round((now - os.path.getmtime(f)) / 3600, 1), d.get("kind"), d.get("status"), alive, (d.get("name") or "")[:34]))
rows.sort(reverse=True)
for idle, kind, status, alive, name in rows:
    print(f"  idle {idle:6}h  {str(kind):11} {str(status):7} alive={alive!s:5} {name}")
print(f"  총 {len(rows)}개")
PY
}

[ $# -ge 1 ] || usage
CMD="$1"; shift
case "$CMD" in
  origin) do_origin ;;
  record) do_record "$@" ;;
  list)   do_list "$@" ;;
  reap)   do_reap "$@" ;;
  audit)  do_audit ;;
  *)      usage ;;
esac
