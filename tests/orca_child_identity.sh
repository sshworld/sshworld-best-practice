#!/usr/bin/env bash
# orca_child_identity.sh — orca 자식 식별이 title 이 아니라 reap-agents.sh 원장
# (kind=orca) 기반인지 검증. S7 회귀: 자식 claude TUI 가 title 을 자기 것으로
# 덮어써도(실측 2026-08-25) cleanup/reap-orphans/limit-child-panes 가 여전히
# 자식을 찾아야 한다.
#
# 실제 orca 호출 금지 — fake orca 를 tmpdir 에 만들고 ORCA_BIN 으로 주입.
# 실제 원장 오염 금지 — CBP_LEDGER_DIR / CBP_ORIGIN_ID 를 매 케이스 tmpdir 로 sandbox.
# 개발 머신 자체가 진짜 Orca 세션이므로 ORCA_*/TERM_PROGRAM/TMUX/CMUX_* 를 scrub.
#
# 케이스:
#   1) 회귀 재현: 원장에 있는 ref 가 title 을 자식에게 덮어써도(cleanup) 닫힌다
#   2) cleanup: 원장에 없는 터미널은 title 이 cbp- 로 시작해도 안 닫힌다
#   3) cleanup: $ORCA_TERMINAL_HANDLE 은 원장에 있어도 절대 안 닫힌다
#   4) reap-orphans: 원장에 있고 orphaned:true → 닫는다
#   5) reap-orphans: 원장에 있지만 orphaned:false → 안 닫는다
#   6) reap-orphans: orphaned:true 지만 원장에 없음 → 안 닫는다 (남의 터미널 보호)
#   7) reap-orphans: CBP_REAP_ORPHANS_DRY_RUN=1 → "would reap" 만, 실제 close 없음
#   8) 원장 파일이 없음 → cleanup/reap-orphans 둘 다 exit 0, 아무것도 안 닫음
#   9) limit-child-panes: 원장의 살아있는 orca 자식 N개 + LIMIT=N → exit 2, LIMIT=N+1 → exit 0
#  10) limit-child-panes: 원장에는 있지만 이미 죽은(terminal list 에 없는) ref 는 안 셈
#  11) limit-child-panes: ORCA_BIN 이 없는 경로 → orca 기여 0, exit 0

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PANE="$REPO/scripts/orca-pane.sh"
REAPER="$REPO/scripts/reap-agents.sh"
HOOK="$REPO/hooks/limit-child-panes.sh"

step() { echo ""; echo "[$1] $2"; }
fail() { echo "❌ FAIL: $1" >&2; exit 1; }

[ -x "$PANE" ] || fail "$PANE 없음 또는 실행권한 없음"
[ -x "$REAPER" ] || fail "$REAPER 없음 또는 실행권한 없음"
[ -x "$HOOK" ] || fail "$HOOK 없음 또는 실행권한 없음"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# 개발 머신 = 실제 Orca 세션 — ambient 신호를 지운다.
unset ORCA_TERMINAL_HANDLE CLAUDE_FAKE_SELF_ORCA_HANDLE TERM_PROGRAM TMUX \
      CMUX_WORKSPACE_ID CMUX_SURFACE_ID ORCA_BIN CBP_LEDGER_DIR CBP_ORIGIN_ID

# limit-child-panes.sh 는 tmux 를 override 할 env var 가 없어(tmux 는 PATH 상 항상 그
# "tmux" 실행) — 개발 머신에 실제 tmux-pane-mgr 세션이 떠 있으면 TMUX_COUNT 가 0 이
# 아닐 수 있다. 훅과 동일한 방법으로 ambient baseline 을 미리 재고 그 위에 얹어 판정한다.
# cmux 는 ping 이 "cmux 밖에서 접속 거부" 로 실패하므로 실 cmux 여부와 무관하게 0 이지만,
# 혹시 모를 흔들림을 없애려 CMUX_BIN 도 존재하지 않는 경로로 고정한다.
export CMUX_BIN="$TMP/nonexistent-cmux-binary-for-test"
BASELINE_TMUX_COUNT=0
if command -v tmux >/dev/null 2>&1; then
  BASELINE_TMUX_COUNT=$(tmux list-panes -s -t tmux-pane-mgr -F '#{pane_id}' 2>/dev/null | wc -l | tr -d ' ')
fi
[ -z "$BASELINE_TMUX_COUNT" ] && BASELINE_TMUX_COUNT=0

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
  *)
    printf '{"id":"1","ok":false,"error":{"code":"unknown_command"}}\n'
    exit 0
    ;;
esac
MOCKEOF
  chmod +x "$dir/orca"
  echo "$dir/orca"
}

make_payload() {
  local cmd="$1"
  printf '{"tool_name":"Bash","tool_input":{"command":%s}}' \
    "$(python3 -c "import json,sys; print(json.dumps(sys.argv[1]))" "$cmd")"
}

# ============================================================================
step 1 "회귀 재현: 원장 ref 가 자식이 덮어쓴 title 이어도 cleanup 이 닫는다"
d1="$TMP/c1"; mkdir -p "$d1"
orca1=$(make_fake_orca "$d1")
ledger1="$d1/ledger"
CBP_LEDGER_DIR="$ledger1" CBP_ORIGIN_ID="origin-1" \
  "$REAPER" record --kind=orca --ref=term_A >/dev/null || fail "record 실패"

list1='[{"handle":"term_A","title":"◑ Claude Sonnet with bypass permissions","orphaned":false,"connected":true}]'
closelog1="$d1/close.log"; : > "$closelog1"

ORCA_BIN="$orca1" ORCA_FAKE_LIST_JSON="$list1" ORCA_FAKE_CLOSE_LOG="$closelog1" \
  CBP_LEDGER_DIR="$ledger1" CBP_ORIGIN_ID="origin-1" \
  "$PANE" cleanup >/dev/null 2>"$d1/err" \
  || fail "cleanup 실패: $(cat "$d1/err")"
grep -qF "term_A" "$closelog1" || fail "덮어쓴 title 이어도 원장에 있으면 닫혀야 하는데 안 닫힘"
echo "ok: title 덮어써도 원장 기반으로 term_A 닫힘"

# ============================================================================
step 2 "cleanup: 원장에 없는 터미널은 title 이 cbp- 로 시작해도 안 닫힌다"
d2="$TMP/c2"; mkdir -p "$d2"
orca2=$(make_fake_orca "$d2")
ledger2="$d2/ledger"  # 원장 디렉토리는 있지만 이 ref 는 안 적음

list2='[{"handle":"term_stranger","title":"cbp-looks-like-ours","orphaned":false,"connected":true}]'
closelog2="$d2/close.log"; : > "$closelog2"

ORCA_BIN="$orca2" ORCA_FAKE_LIST_JSON="$list2" ORCA_FAKE_CLOSE_LOG="$closelog2" \
  CBP_LEDGER_DIR="$ledger2" CBP_ORIGIN_ID="origin-2" \
  "$PANE" cleanup >/dev/null 2>"$d2/err" \
  || fail "cleanup 실패: $(cat "$d2/err")"
if grep -qF "term_stranger" "$closelog2"; then
  fail "원장에 없는 터미널을 title 만으로 닫음: $(cat "$closelog2")"
fi
echo "ok: 원장에 없으면 title 무관하게 보존"

# ============================================================================
step 3 "cleanup: \$ORCA_TERMINAL_HANDLE 은 원장에 있어도 절대 안 닫힌다"
d3="$TMP/c3"; mkdir -p "$d3"
orca3=$(make_fake_orca "$d3")
ledger3="$d3/ledger"
CBP_LEDGER_DIR="$ledger3" CBP_ORIGIN_ID="origin-3" \
  "$REAPER" record --kind=orca --ref=term_other >/dev/null || fail "record 실패"
# self 는 원장 기록 자체를 reap-agents.sh 가 거부하므로, 별도 원장에 self ref 를 직접 심는다
# (실 세계에서는 있을 수 없는 상태지만, "설령 원장에 있어도 self 는 닫지 않는다" 를 증명).
mkdir -p "$ledger3"
printf '{"kind": "orca", "ref": "term_self", "origin": "origin-3", "ts": 1}\n' >> "$ledger3/origin-3.jsonl"

list3='[{"handle":"term_other","title":"x","orphaned":false,"connected":true},{"handle":"term_self","title":"x","orphaned":false,"connected":true}]'
closelog3="$d3/close.log"; : > "$closelog3"

ORCA_BIN="$orca3" ORCA_FAKE_LIST_JSON="$list3" ORCA_FAKE_CLOSE_LOG="$closelog3" \
  CBP_LEDGER_DIR="$ledger3" CBP_ORIGIN_ID="origin-3" ORCA_TERMINAL_HANDLE="term_self" \
  "$PANE" cleanup >/dev/null 2>"$d3/err" \
  || fail "cleanup 실패: $(cat "$d3/err")"
grep -qF "term_other" "$closelog3" || fail "원장에 있는 term_other 가 안 닫힘"
if grep -qF "term_self" "$closelog3"; then
  fail "\$ORCA_TERMINAL_HANDLE(term_self) 이 원장에 있다고 닫혀버림: $(cat "$closelog3")"
fi
echo "ok: self terminal 은 원장에 있어도 보존, 나머지는 닫힘"

# ============================================================================
step 4 "reap-orphans: 원장에 있고 orphaned:true → 닫는다"
d4="$TMP/c4"; mkdir -p "$d4"
orca4=$(make_fake_orca "$d4")
ledger4="$d4/ledger"
CBP_LEDGER_DIR="$ledger4" CBP_ORIGIN_ID="origin-4" \
  "$REAPER" record --kind=orca --ref=term_orphaned >/dev/null || fail "record 실패"

list4='[{"handle":"term_orphaned","title":"x","orphaned":true,"connected":false}]'
closelog4="$d4/close.log"; : > "$closelog4"

ORCA_BIN="$orca4" ORCA_FAKE_LIST_JSON="$list4" ORCA_FAKE_CLOSE_LOG="$closelog4" \
  CBP_LEDGER_DIR="$ledger4" CBP_ORIGIN_ID="origin-4" \
  "$PANE" reap-orphans >/dev/null 2>"$d4/err" \
  || fail "reap-orphans 실패: $(cat "$d4/err")"
grep -qF "term_orphaned" "$closelog4" || fail "원장 + orphaned:true 인데 안 닫힘"
echo "ok: 원장 + orphaned:true → 닫힘"

# ============================================================================
step 5 "reap-orphans: 원장에 있지만 orphaned:false → 안 닫는다"
d5="$TMP/c5"; mkdir -p "$d5"
orca5=$(make_fake_orca "$d5")
ledger5="$d5/ledger"
CBP_LEDGER_DIR="$ledger5" CBP_ORIGIN_ID="origin-5" \
  "$REAPER" record --kind=orca --ref=term_notorphan >/dev/null || fail "record 실패"

list5='[{"handle":"term_notorphan","title":"x","orphaned":false,"connected":true}]'
closelog5="$d5/close.log"; : > "$closelog5"

ORCA_BIN="$orca5" ORCA_FAKE_LIST_JSON="$list5" ORCA_FAKE_CLOSE_LOG="$closelog5" \
  CBP_LEDGER_DIR="$ledger5" CBP_ORIGIN_ID="origin-5" \
  "$PANE" reap-orphans >/dev/null 2>"$d5/err" \
  || fail "reap-orphans 실패: $(cat "$d5/err")"
if [ -s "$closelog5" ]; then
  fail "원장 + orphaned:false 인데 닫힘: $(cat "$closelog5")"
fi
echo "ok: 원장 + orphaned:false → 보존"

# ============================================================================
step 6 "reap-orphans: orphaned:true 지만 원장에 없음 → 안 닫는다 (남의 터미널 보호)"
d6="$TMP/c6"; mkdir -p "$d6"
orca6=$(make_fake_orca "$d6")
ledger6="$d6/ledger"  # 비어있는 원장 디렉토리

list6='[{"handle":"term_nobodys","title":"x","orphaned":true,"connected":false}]'
closelog6="$d6/close.log"; : > "$closelog6"

ORCA_BIN="$orca6" ORCA_FAKE_LIST_JSON="$list6" ORCA_FAKE_CLOSE_LOG="$closelog6" \
  CBP_LEDGER_DIR="$ledger6" CBP_ORIGIN_ID="origin-6" \
  "$PANE" reap-orphans >/dev/null 2>"$d6/err" \
  || fail "reap-orphans 실패: $(cat "$d6/err")"
if [ -s "$closelog6" ]; then
  fail "orphaned:true 지만 원장에 없는 터미널을 닫음(남의 터미널 침범): $(cat "$closelog6")"
fi
echo "ok: orphaned:true 지만 원장에 없으면 보존"

# ============================================================================
step 7 "reap-orphans: CBP_REAP_ORPHANS_DRY_RUN=1 → would reap 만, 실제 close 없음"
d7="$TMP/c7"; mkdir -p "$d7"
orca7=$(make_fake_orca "$d7")
ledger7="$d7/ledger"
CBP_LEDGER_DIR="$ledger7" CBP_ORIGIN_ID="origin-7" \
  "$REAPER" record --kind=orca --ref=term_dryrun >/dev/null || fail "record 실패"

list7='[{"handle":"term_dryrun","title":"x","orphaned":true,"connected":false}]'
closelog7="$d7/close.log"; : > "$closelog7"

out7=$(ORCA_BIN="$orca7" ORCA_FAKE_LIST_JSON="$list7" ORCA_FAKE_CLOSE_LOG="$closelog7" \
  CBP_LEDGER_DIR="$ledger7" CBP_ORIGIN_ID="origin-7" CBP_REAP_ORPHANS_DRY_RUN=1 \
  "$PANE" reap-orphans 2>"$d7/err") || fail "reap-orphans(dry-run) 실패: $(cat "$d7/err")"
printf '%s\n' "$out7" | grep -q "would reap term_dryrun" || fail "would reap 출력 없음: $out7"
if [ -s "$closelog7" ]; then
  fail "dry-run 인데 실제 close 가 호출됨: $(cat "$closelog7")"
fi
echo "ok: dry-run → would reap 만 출력, close 없음"

# ============================================================================
step 8 "원장 파일이 없음 → cleanup/reap-orphans 둘 다 exit 0, 아무것도 안 닫음"
d8="$TMP/c8"; mkdir -p "$d8"
orca8=$(make_fake_orca "$d8")
ledger8="$d8/no-such-ledger-dir"  # 아예 존재하지 않음

list8='[{"handle":"term_x","title":"cbp-x","orphaned":true,"connected":false}]'
closelog8="$d8/close.log"; : > "$closelog8"

set +e
ORCA_BIN="$orca8" ORCA_FAKE_LIST_JSON="$list8" ORCA_FAKE_CLOSE_LOG="$closelog8" \
  CBP_LEDGER_DIR="$ledger8" CBP_ORIGIN_ID="origin-8" \
  "$PANE" cleanup >/dev/null 2>"$d8/err_cleanup"
rc8a=$?
ORCA_BIN="$orca8" ORCA_FAKE_LIST_JSON="$list8" ORCA_FAKE_CLOSE_LOG="$closelog8" \
  CBP_LEDGER_DIR="$ledger8" CBP_ORIGIN_ID="origin-8" \
  "$PANE" reap-orphans >/dev/null 2>"$d8/err_reap"
rc8b=$?
set -e
[ "$rc8a" -eq 0 ] || fail "원장 없음인데 cleanup exit≠0 ($rc8a): $(cat "$d8/err_cleanup")"
[ "$rc8b" -eq 0 ] || fail "원장 없음인데 reap-orphans exit≠0 ($rc8b): $(cat "$d8/err_reap")"
if [ -s "$closelog8" ]; then
  fail "원장 없음인데 뭔가 닫힘: $(cat "$closelog8")"
fi
echo "ok: 원장 없음 → 둘 다 exit 0, close 없음"

# ============================================================================
step 9 "limit-child-panes: 원장의 살아있는 orca 자식 N개 — LIMIT=N 차단, LIMIT=N+1 통과"
d9="$TMP/c9"; mkdir -p "$d9"
orca9=$(make_fake_orca "$d9")
ledger9="$d9/ledger"
CBP_LEDGER_DIR="$ledger9" CBP_ORIGIN_ID="origin-9" \
  "$REAPER" record --kind=orca --ref=term_h1 >/dev/null || fail "record 실패"
CBP_LEDGER_DIR="$ledger9" CBP_ORIGIN_ID="origin-9" \
  "$REAPER" record --kind=orca --ref=term_h2 >/dev/null || fail "record 실패"

list9='[{"handle":"term_h1","title":"x","orphaned":false,"connected":true},{"handle":"term_h2","title":"x","orphaned":false,"connected":true}]'
payload9=$(make_payload './scripts/orca-pane.sh launch')
limit9=$((BASELINE_TMUX_COUNT + 2))

set +e
OUT9A=$(echo "$payload9" | ORCA_BIN="$orca9" ORCA_FAKE_LIST_JSON="$list9" \
  CBP_LEDGER_DIR="$ledger9" CBP_ORIGIN_ID="origin-9" CLAUDE_MAX_CHILD_PANES="$limit9" "$HOOK" 2>&1)
RC9A=$?
set -e
[ "$RC9A" -eq 2 ] || fail "LIMIT=N($limit9) 인데 차단 안 됨 (rc=$RC9A): $OUT9A"

limit9b=$((limit9 + 1))
set +e
OUT9B=$(echo "$payload9" | ORCA_BIN="$orca9" ORCA_FAKE_LIST_JSON="$list9" \
  CBP_LEDGER_DIR="$ledger9" CBP_ORIGIN_ID="origin-9" CLAUDE_MAX_CHILD_PANES="$limit9b" "$HOOK" 2>&1)
RC9B=$?
set -e
[ "$RC9B" -eq 0 ] || fail "LIMIT=N+1($limit9b) 인데 통과 안 됨 (rc=$RC9B): $OUT9B"
echo "ok: 원장 살아있는 자식 2개 — LIMIT=$limit9 차단, LIMIT=$limit9b 통과"

# ============================================================================
step 10 "limit-child-panes: 원장에는 있지만 이미 죽은(terminal list 에 없는) ref 는 안 셈"
d10="$TMP/c10"; mkdir -p "$d10"
orca10=$(make_fake_orca "$d10")
ledger10="$d10/ledger"
CBP_LEDGER_DIR="$ledger10" CBP_ORIGIN_ID="origin-10" \
  "$REAPER" record --kind=orca --ref=term_dead >/dev/null || fail "record 실패"

list10='[]'  # term_dead 가 terminal list 에 없음 — 이미 죽음
payload10=$(make_payload './scripts/orca-pane.sh launch')
limit10=$((BASELINE_TMUX_COUNT + 1))

set +e
OUT10=$(echo "$payload10" | ORCA_BIN="$orca10" ORCA_FAKE_LIST_JSON="$list10" \
  CBP_LEDGER_DIR="$ledger10" CBP_ORIGIN_ID="origin-10" CLAUDE_MAX_CHILD_PANES="$limit10" "$HOOK" 2>&1)
RC10=$?
set -e
[ "$RC10" -eq 0 ] || fail "죽은 ref 가 카운트되어 LIMIT=$limit10 에서 차단됨 (rc=$RC10): $OUT10"
echo "ok: 죽은 ref 는 카운트 안 됨 → 통과"

# ============================================================================
step 11 "limit-child-panes: ORCA_BIN 이 없는 경로 → orca 기여 0, exit 0"
d11="$TMP/c11"; mkdir -p "$d11"
ledger11="$d11/ledger"
CBP_LEDGER_DIR="$ledger11" CBP_ORIGIN_ID="origin-11" \
  "$REAPER" record --kind=orca --ref=term_ghost >/dev/null || fail "record 실패"

payload11=$(make_payload './scripts/orca-pane.sh launch')
limit11=$((BASELINE_TMUX_COUNT + 1))

# LIMIT<=baseline 이면 orca 기여가 0 이어도 CURRENT >= LIMIT 로 항상 차단되므로,
# orca 미가용 판정은 baseline+1 로 검증한다 (orca 기여가 0 초과였다면 여기서 차단됨).
set +e
OUT11=$(echo "$payload11" | ORCA_BIN="$d11/nonexistent-orca-binary" \
  CBP_LEDGER_DIR="$ledger11" CBP_ORIGIN_ID="origin-11" CLAUDE_MAX_CHILD_PANES="$limit11" "$HOOK" 2>&1)
RC11=$?
set -e
[ "$RC11" -eq 0 ] || fail "ORCA_BIN 없는 경로인데 LIMIT=$limit11 에서 차단됨 (rc=$RC11): $OUT11"
echo "ok: ORCA_BIN 없음 → orca 기여 0, 세션 안 막힘"

# ============================================================================
echo ""
echo "✅ orca_child_identity: 11개 케이스 모두 PASS"
