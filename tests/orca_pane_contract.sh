#!/usr/bin/env bash
# orca_pane_contract.sh — scripts/orca-pane.sh 계약 테스트.
#
# 실 orca 바이너리는 절대 호출하지 않는다 — tmpdir 에 fake orca 스크립트를 만들고
# ORCA_BIN 으로 override 한다. fake orca 는 env 변수로 시나리오를 제어한다.
#
# 케이스:
#   1) launch stdout 은 term_ 로 시작하는 단일 토큰 (공백/추가 줄 없음)
#   2) fake orca 가 ok:false + exit0 을 반환해도 wrapper 는 실패해야 함 (핵심 계약)
#   3) wait-idle: lastOutputAt 이 idle 구간 동안 불변이면 0 반환
#   4) wait-idle: lastOutputAt 이 계속 변하면 timeout 까지 대기 후 비0 종료
#   5) capture: tail[] 3개 배열을 개행으로 join
#   6) kill: 자기 handle 거부, FORCE_SELF_KILL=1 이면 진행
#   7) reap: done-marker 존재 시 wait-idle 스킵(fake show 는 절대 idle 안 됨) 하고 즉시 reaped
#   8) reap-orphans: orphaned:false terminal 은 close 호출 안 함

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WRAPPER="$REPO/scripts/orca-pane.sh"

step() { echo ""; echo "[$1] $2"; }
fail() { echo "❌ FAIL: $1" >&2; exit 1; }

[ -x "$WRAPPER" ] || fail "$WRAPPER 없음 또는 실행권한 없음"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ----------------------------------------------------------------
# fake orca 생성 — 모든 서브커맨드를 env 변수로 제어.
# ----------------------------------------------------------------
make_fake_orca() {
  local dir="$1"
  cat > "$dir/orca" <<'MOCKEOF'
#!/usr/bin/env bash
group="${1:-}"; action="${2:-}"; shift 2 2>/dev/null || true
terminal=""
while [ $# -gt 0 ]; do
  case "$1" in
    --terminal) terminal="$2"; shift 2 ;;
    --terminal=*) terminal="${1#*=}"; shift ;;
    *) shift ;;
  esac
done

case "$group $action" in
  "terminal create")
    if [ "${ORCA_FAKE_CREATE_OK:-true}" = "true" ]; then
      handle="${ORCA_FAKE_HANDLE:-term_abc123}"
      printf '{"id":"1","ok":true,"result":{"terminal":{"handle":"%s"},"tabId":"t1","paneKey":"p1","worktreeId":"w1","title":"x"}}\n' "$handle"
    else
      printf '{"id":"1","ok":false,"error":{"code":"boom","message":"boom happened"}}\n'
    fi
    exit 0
    ;;
  "terminal send")
    accepted="${ORCA_FAKE_SEND_OK:-true}"
    printf '{"id":"1","ok":true,"result":{"send":{"accepted":%s,"bytesWritten":10}}}\n' "$accepted"
    exit 0
    ;;
  "terminal read")
    tail="${ORCA_FAKE_TAIL:-[]}"
    printf '{"id":"1","ok":true,"result":{"terminal":{"tail":%s,"status":"running","truncated":false}}}\n' "$tail"
    exit 0
    ;;
  "terminal show")
    mode="${ORCA_FAKE_SHOW_MODE:-static}"
    if [ "$mode" = "changing" ]; then
      cf="${ORCA_FAKE_SHOW_COUNTER_FILE:?ORCA_FAKE_SHOW_COUNTER_FILE 필요}"
      n=$(cat "$cf" 2>/dev/null || echo 0)
      n=$((n + 1))
      printf '%s' "$n" > "$cf"
      val=$((n * 1000))
    else
      val="${ORCA_FAKE_SHOW_VALUE:-1000}"
    fi
    printf '{"id":"1","ok":true,"result":{"terminal":{"lastOutputAt":%s,"orphaned":false,"connected":true,"title":"x","preview":""}}}\n' "$val"
    exit 0
    ;;
  "terminal list")
    list="${ORCA_FAKE_LIST_JSON:-[]}"
    printf '{"id":"1","ok":true,"result":{"terminals":%s}}\n' "$list"
    exit 0
    ;;
  "terminal close")
    if [ -n "${ORCA_FAKE_CLOSE_LOG:-}" ]; then
      printf '%s\n' "$terminal" >> "$ORCA_FAKE_CLOSE_LOG"
    fi
    printf '{"id":"1","ok":true,"result":{"close":{"ptyKilled":true}}}\n'
    exit 0
    ;;
  "terminal wait")
    printf '{"id":"1","ok":true,"result":{}}\n'
    exit 0
    ;;
  *)
    printf '{"id":"1","ok":false,"error":{"code":"unknown_command"}}\n'
    exit 0
    ;;
esac
MOCKEOF
  chmod +x "$dir/orca"
  echo "$dir/orca"
}

# ============================================================================
step 1 "launch stdout 은 term_ 단일 토큰 (공백/추가줄 없음)"
d1="$TMP/c1"; mkdir -p "$d1"
orca1=$(make_fake_orca "$d1")

out1=$(ORCA_BIN="$orca1" ORCA_FAKE_HANDLE="term_deadbeef" "$WRAPPER" launch 2>"$d1/err")
rc1=$?
[ "$rc1" -eq 0 ] || fail "launch exit=$rc1 stderr=$(cat "$d1/err")"
[ "$out1" = "term_deadbeef" ] || fail "launch stdout 불일치: '$out1'"
case "$out1" in
  term_*) : ;;
  *) fail "launch stdout 이 term_ 로 시작 안 함: '$out1'" ;;
esac
lines1=$(printf '%s\n' "$out1" | wc -l | tr -d ' ')
[ "$lines1" -eq 1 ] || fail "launch stdout 이 한 줄이 아님 (lines=$lines1)"
case "$out1" in
  *[[:space:]]*) fail "launch stdout 에 공백 포함: '$out1'" ;;
esac
echo "ok: launch → $out1"

# ============================================================================
step 2 "ok:false + exit0 응답이어도 wrapper 는 실패해야 함 (핵심 계약)"
d2="$TMP/c2"; mkdir -p "$d2"
orca2=$(make_fake_orca "$d2")

# fake orca 자체가 exit 0 인지 먼저 확인 (전제 검증)
ORCA_FAKE_CREATE_OK=false "$orca2" terminal create --worktree active --title x --json >/dev/null 2>&1
orca_raw_rc=$?
[ "$orca_raw_rc" -eq 0 ] || fail "전제 실패: fake orca 가 ok:false 인데 exit0 아님 (rc=$orca_raw_rc)"

set +e
out2=$(ORCA_BIN="$orca2" ORCA_FAKE_CREATE_OK=false "$WRAPPER" launch 2>"$d2/err")
rc2=$?
set -e
[ "$rc2" -ne 0 ] || fail "launch 이 ok:false 응답(exit0)을 성공으로 오판함: stdout='$out2'"
echo "ok: ok:false(exit0) → wrapper rc=$rc2 (비0)"

# ============================================================================
step 3 "wait-idle: lastOutputAt 불변 → idle 구간 후 0 반환"
d3="$TMP/c3"; mkdir -p "$d3"
orca3=$(make_fake_orca "$d3")

t0=$(date +%s)
set +e
ORCA_BIN="$orca3" ORCA_FAKE_SHOW_MODE=static ORCA_FAKE_SHOW_VALUE=42 \
  "$WRAPPER" wait-idle --pane=term_x --idle=1 --timeout=10 2>"$d3/err"
rc3=$?
set -e
t1=$(date +%s)
[ "$rc3" -eq 0 ] || fail "wait-idle(static) 이 실패함 rc=$rc3 stderr=$(cat "$d3/err")"
elapsed3=$((t1 - t0))
[ "$elapsed3" -lt 10 ] || fail "wait-idle(static) 이 timeout 까지 소모함 (elapsed=$elapsed3)"
echo "ok: wait-idle(static lastOutputAt) → rc=0, elapsed=${elapsed3}s"

# ============================================================================
step 4 "wait-idle: lastOutputAt 계속 변화 → timeout 까지 대기 후 비0"
d4="$TMP/c4"; mkdir -p "$d4"
orca4=$(make_fake_orca "$d4")
counter4="$d4/counter"
echo 0 > "$counter4"

t0=$(date +%s)
set +e
ORCA_BIN="$orca4" ORCA_FAKE_SHOW_MODE=changing ORCA_FAKE_SHOW_COUNTER_FILE="$counter4" \
  "$WRAPPER" wait-idle --pane=term_x --idle=1 --timeout=2 2>"$d4/err"
rc4=$?
set -e
t1=$(date +%s)
elapsed4=$((t1 - t0))
[ "$rc4" -ne 0 ] || fail "wait-idle(changing) 이 성공(rc0) 반환 — idle 오판"
[ "$elapsed4" -ge 2 ] || fail "wait-idle(changing) 이 timeout 전에 종료됨 (elapsed=$elapsed4)"
echo "ok: wait-idle(changing lastOutputAt) → rc=$rc4 (비0), elapsed=${elapsed4}s"

# ============================================================================
step 5 "capture: tail[] 3개 배열을 개행으로 join"
d5="$TMP/c5"; mkdir -p "$d5"
orca5=$(make_fake_orca "$d5")

out5=$(ORCA_BIN="$orca5" ORCA_FAKE_TAIL='["line1","line2","line3"]' \
  "$WRAPPER" capture --pane=term_x 2>"$d5/err")
rc5=$?
[ "$rc5" -eq 0 ] || fail "capture 실패 rc=$rc5 stderr=$(cat "$d5/err")"
lines5=$(printf '%s\n' "$out5" | wc -l | tr -d ' ')
[ "$lines5" -eq 3 ] || fail "capture 출력 줄 수 불일치 (기대 3, 실제 $lines5): '$out5'"
[ "$out5" = "$(printf 'line1\nline2\nline3')" ] || fail "capture 출력 내용 불일치: '$out5'"
echo "ok: capture → 3 lines joined"

# ============================================================================
step 6 "kill: 자기 handle 거부, FORCE_SELF_KILL=1 이면 진행"
d6="$TMP/c6"; mkdir -p "$d6"
orca6=$(make_fake_orca "$d6")
closelog6="$d6/close.log"; : > "$closelog6"

set +e
ORCA_BIN="$orca6" CLAUDE_FAKE_SELF_ORCA_HANDLE="term_self" ORCA_FAKE_CLOSE_LOG="$closelog6" \
  "$WRAPPER" kill --pane=term_self 2>"$d6/err"
rc6a=$?
set -e
[ "$rc6a" -eq 5 ] || fail "kill(self, 미강제) exit 코드 불일치 (기대 5, 실제 $rc6a)"
[ ! -s "$closelog6" ] || fail "kill(self, 미강제) 인데 close 호출됨: $(cat "$closelog6")"
echo "ok: kill(self) 거부 → rc=$rc6a"

set +e
ORCA_BIN="$orca6" CLAUDE_FAKE_SELF_ORCA_HANDLE="term_self" ORCA_FAKE_CLOSE_LOG="$closelog6" \
  FORCE_SELF_KILL=1 "$WRAPPER" kill --pane=term_self 2>"$d6/err2"
rc6b=$?
set -e
[ "$rc6b" -eq 0 ] || fail "kill(self, FORCE_SELF_KILL=1) 실패 rc=$rc6b stderr=$(cat "$d6/err2")"
grep -qF "term_self" "$closelog6" || fail "kill(self, FORCE_SELF_KILL=1) 인데 close 호출 안 됨"
echo "ok: kill(self, FORCE_SELF_KILL=1) 진행 → rc=$rc6b"

# ============================================================================
step 7 "reap: done-marker 존재 시 wait-idle 스킵 → 즉시 reaped"
d7="$TMP/c7"; mkdir -p "$d7"
orca7=$(make_fake_orca "$d7")
markerdir7="$d7/markers"; mkdir -p "$markerdir7"
pane7="term_reaptest"
printf '%s\n' "$pane7" > "$markerdir7/cbp-slice-done-branch"
counter7="$d7/counter7"
echo 0 > "$counter7"
closelog7="$d7/close.log"; : > "$closelog7"

t0=$(date +%s)
out7=$(ORCA_BIN="$orca7" \
  CBP_MARKER_DIR="$markerdir7" \
  ORCA_FAKE_TAIL='["done","✅ all good"]' \
  ORCA_FAKE_SHOW_MODE=changing ORCA_FAKE_SHOW_COUNTER_FILE="$counter7" \
  ORCA_FAKE_CLOSE_LOG="$closelog7" \
  "$WRAPPER" reap --pane="$pane7" --idle=1 --timeout=30 2>"$d7/err")
rc7=$?
t1=$(date +%s)
elapsed7=$((t1 - t0))
[ "$rc7" -eq 0 ] || fail "reap(marker fast-path) 실패 rc=$rc7 stderr=$(cat "$d7/err")"
printf '%s\n' "$out7" | grep -q "^reaped $pane7\$" || fail "reap 출력이 'reaped $pane7' 아님: '$out7'"
# wait-idle 이 호출됐다면(버그) fake show 가 절대 idle 이 안 되므로 timeout(30s) 만큼 걸림.
# fast-path 가 제대로 작동하면 수 초 안에 끝나야 한다.
[ "$elapsed7" -lt 5 ] || fail "reap 이 너무 오래 걸림(elapsed=${elapsed7}s) — wait-idle 이 스킵 안 된 것으로 의심"
[ ! -f "$markerdir7/cbp-slice-done-branch" ] || fail "reap 성공 후 done-marker 가 안 지워짐"
echo "ok: reap(marker fast-path) → $out7, elapsed=${elapsed7}s"

# ============================================================================
step 8 "reap-orphans: orphaned:false terminal 은 close 호출 안 함"
d8="$TMP/c8"; mkdir -p "$d8"
orca8=$(make_fake_orca "$d8")
closelog8="$d8/close.log"; : > "$closelog8"

list8='[{"handle":"term_orphan1","title":"cbp-orphan","orphaned":true,"connected":false},{"handle":"term_alive1","title":"cbp-alive","orphaned":false,"connected":true}]'

out8=$(ORCA_BIN="$orca8" ORCA_FAKE_LIST_JSON="$list8" ORCA_FAKE_CLOSE_LOG="$closelog8" \
  "$WRAPPER" reap-orphans 2>"$d8/err")
rc8=$?
[ "$rc8" -eq 0 ] || fail "reap-orphans 실패 rc=$rc8 stderr=$(cat "$d8/err")"
grep -qF "term_orphan1" "$closelog8" || fail "reap-orphans 이 orphaned:true 대상을 close 안 함"
if grep -qF "term_alive1" "$closelog8"; then
  fail "reap-orphans 이 orphaned:false(term_alive1) 를 close 함: $(cat "$closelog8")"
fi
echo "ok: reap-orphans → orphaned:true 만 close, orphaned:false 는 보존"

# ============================================================================
echo ""
echo "✅ orca_pane_contract: 8개 케이스 모두 PASS"
