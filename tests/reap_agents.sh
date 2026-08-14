#!/usr/bin/env bash
# reap-agents.sh — 계보 원장 + 회수 계약 테스트.
# 핵심 계약: 원천(origin)은 절대 회수되지 않고, 자식만 회수된다.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO/scripts/reap-agents.sh"

step() { echo ""; echo "[$1] $2"; }
fail() { echo "❌ FAIL: $1" >&2; exit 1; }

[ -x "$SCRIPT" ] || fail "not executable: $SCRIPT"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export CBP_LEDGER_DIR="$TMP/ledger"
export CBP_SESSIONS_DIR="$TMP/sessions"
mkdir -p "$CBP_SESSIONS_DIR"

# mock 바이너리 — 실제 cmux/tmux 를 절대 건드리지 않는다
cat > "$TMP/cmux" <<'EOF'
#!/usr/bin/env bash
echo "$@" >> "$CMUX_LOG"
EOF
cat > "$TMP/tmux" <<'EOF'
#!/usr/bin/env bash
echo "$@" >> "$TMUX_LOG"
EOF
chmod +x "$TMP/cmux" "$TMP/tmux"
export CMUX_BIN="$TMP/cmux" TMUX_BIN="$TMP/tmux"
export CMUX_LOG="$TMP/cmux.log" TMUX_LOG="$TMP/tmux.log"
: > "$CMUX_LOG"; : > "$TMUX_LOG"

step 1 "origin — CBP_ORIGIN_ID override"
OUT=$(CBP_ORIGIN_ID=origin-A "$SCRIPT" origin)
[ "$OUT" = "origin-A" ] || fail "origin override 실패: $OUT"

step 2 "record → 원장 파일에 자식 1줄"
CBP_ORIGIN_ID=origin-A "$SCRIPT" record --kind=cmux --ref=surface:900 --ws=ws:1 --label=S1 >/dev/null \
  || fail "record 실패"
[ -f "$CBP_LEDGER_DIR/origin-A.jsonl" ] || fail "원장 파일 없음"
grep -q 'surface:900' "$CBP_LEDGER_DIR/origin-A.jsonl" || fail "원장에 ref 없음"

step 3 "self surface 는 기록 거부 — 원장에 자신이 없어야 자살이 불가능"
set +e
CMUX_SURFACE_ID=surface:999 CBP_ORIGIN_ID=origin-A "$SCRIPT" record --kind=cmux --ref=surface:999 >/dev/null 2>&1
RC=$?
set -e
[ "$RC" = "2" ] || fail "self surface 기록이 거부되지 않음 (rc=$RC)"
grep -q 'surface:999' "$CBP_LEDGER_DIR/origin-A.jsonl" && fail "self surface 가 원장에 들어감"

step 4 "조상 pid 기록 거부"
set +e
CBP_ORIGIN_ID=origin-A "$SCRIPT" record --kind=bg --ref=self-bg --pid=$$ >/dev/null 2>&1
RC=$?
set -e
[ "$RC" = "2" ] || fail "조상 pid 기록이 거부되지 않음 (rc=$RC)"

step 5 "dry-run 이 기본 — 실제 명령 안 나감"
OUT=$(CBP_ORIGIN_ID=origin-A "$SCRIPT" reap)
printf '%s' "$OUT" | grep -q '\[dry-run\]' || fail "dry-run 출력 없음: $OUT"
[ -s "$CMUX_LOG" ] && fail "dry-run 인데 cmux 가 호출됨"

step 6 "--apply → 자식 회수 + 원장 비움"
OUT=$(CBP_ORIGIN_ID=origin-A "$SCRIPT" reap --apply)
printf '%s' "$OUT" | grep -q 'reaped  cmux surface:900' || fail "회수 로그 없음: $OUT"
grep -q 'close-surface --surface surface:900' "$CMUX_LOG" || fail "cmux close-surface 미호출: $(cat "$CMUX_LOG")"
[ -s "$CBP_LEDGER_DIR/origin-A.jsonl" ] && fail "apply 후 원장이 안 비워짐"

step 7 "타 세션 원장은 --orphans 없이 건드리지 않는다 (원천 보존)"
mkdir -p "$CBP_LEDGER_DIR"
printf '{"kind":"cmux","ref":"surface:700","origin":"origin-B","ts":1}\n' > "$CBP_LEDGER_DIR/origin-B.jsonl"
OUT=$(CBP_ORIGIN_ID=origin-A "$SCRIPT" reap --apply)
printf '%s' "$OUT" | grep -q 'skip 원장(타 세션' || fail "타 세션 원장을 건드림: $OUT"
grep -q 'surface:700' "$CMUX_LOG" && fail "타 세션 자식이 회수됨"

step 8 "origin 이 살아있으면 --orphans 여도 보존"
# origin-B 를 살아있는 세션으로 등록 (자기 pid = 확실히 alive)
cat > "$CBP_SESSIONS_DIR/1.json" <<EOF
{"pid":$$,"sessionId":"origin-B","kind":"bg","status":"idle"}
EOF
OUT=$(CBP_ORIGIN_ID=origin-A "$SCRIPT" reap --apply --orphans)
printf '%s' "$OUT" | grep -q 'origin 살아있음 — 원천 보존' || fail "살아있는 origin 이 보존되지 않음: $OUT"
grep -q 'surface:700' "$CMUX_LOG" && fail "살아있는 origin 의 자식이 회수됨"

step 9 "origin 이 죽었으면 --orphans 로 자식 회수 + 원장 삭제"
# 죽은 pid 로 교체 (예약된 큰 pid — 존재하지 않음)
cat > "$CBP_SESSIONS_DIR/1.json" <<'EOF'
{"pid":2147483600,"sessionId":"origin-B","kind":"bg","status":"idle"}
EOF
OUT=$(CBP_ORIGIN_ID=origin-A "$SCRIPT" reap --apply --orphans)
printf '%s' "$OUT" | grep -q '고아 원장' || fail "고아 원장 인식 실패: $OUT"
grep -q 'close-surface --surface surface:700' "$CMUX_LOG" || fail "고아 자식이 회수되지 않음"
[ -f "$CBP_LEDGER_DIR/origin-B.jsonl" ] && fail "고아 원장이 삭제되지 않음"

step 10 "tmux / bg / subagent kind 분기"
CBP_ORIGIN_ID=origin-C "$SCRIPT" record --kind=tmux --ref=%42 >/dev/null
CBP_ORIGIN_ID=origin-C "$SCRIPT" record --kind=subagent --ref=agent-1 >/dev/null
OUT=$(CBP_ORIGIN_ID=origin-C "$SCRIPT" reap --apply)
grep -q 'kill-pane -t %42' "$TMUX_LOG" || fail "tmux kill-pane 미호출"
printf '%s' "$OUT" | grep -q 'skip(subagent' || fail "subagent 는 skip 되어야 함: $OUT"

step 11 "REAP_AGENTS_DRY_RUN=1 이 --apply 를 무력화"
CBP_ORIGIN_ID=origin-D "$SCRIPT" record --kind=cmux --ref=surface:800 >/dev/null
: > "$CMUX_LOG"
OUT=$(REAP_AGENTS_DRY_RUN=1 CBP_ORIGIN_ID=origin-D "$SCRIPT" reap --apply)
printf '%s' "$OUT" | grep -q '\[dry-run\]' || fail "강제 dry-run 미적용: $OUT"
[ -s "$CMUX_LOG" ] && fail "강제 dry-run 인데 cmux 호출됨"

step 12 "audit 은 회수하지 않는다"
: > "$CMUX_LOG"
CBP_ORIGIN_ID=origin-D "$SCRIPT" audit >/dev/null 2>&1
[ -s "$CMUX_LOG" ] && fail "audit 이 회수를 실행함"

echo ""
echo "OK"
