#!/usr/bin/env bash
# reap_agents_orca.sh — reap-agents.sh 의 orca kind 배선 계약 테스트.
# 핵심 계약: orca record/reap 이 cmux/tmux 와 동일한 자기-보호 구조를 갖는다.

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

# mock 바이너리 — 실제 cmux/tmux/orca 를 절대 건드리지 않는다
cat > "$TMP/cmux" <<'EOF'
#!/usr/bin/env bash
echo "$@" >> "$CMUX_LOG"
EOF
cat > "$TMP/tmux" <<'EOF'
#!/usr/bin/env bash
echo "$@" >> "$TMUX_LOG"
EOF
cat > "$TMP/orca" <<'EOF'
#!/usr/bin/env bash
echo "$@" >> "$ORCA_LOG"
EOF
chmod +x "$TMP/cmux" "$TMP/tmux" "$TMP/orca"
export CMUX_BIN="$TMP/cmux" TMUX_BIN="$TMP/tmux" ORCA_BIN="$TMP/orca"
export CMUX_LOG="$TMP/cmux.log" TMUX_LOG="$TMP/tmux.log" ORCA_LOG="$TMP/orca.log"
: > "$CMUX_LOG"; : > "$TMUX_LOG"; : > "$ORCA_LOG"
export REAP_AGENTS_DRY_RUN=1

# ─────────────────────────────────────────────────────────
step 1 "record --kind=orca --ref=term_x → 원장에 kind=orca 1줄"
CBP_ORIGIN_ID=origin-A "$SCRIPT" record --kind=orca --ref=term_x --label=S1 >/dev/null \
  || fail "record 실패"
[ -f "$CBP_LEDGER_DIR/origin-A.jsonl" ] || fail "원장 파일 없음"
grep -q '"kind": "orca"' "$CBP_LEDGER_DIR/origin-A.jsonl" \
  || grep -q '"kind":"orca"' "$CBP_LEDGER_DIR/origin-A.jsonl" \
  || fail "원장에 kind=orca 없음: $(cat "$CBP_LEDGER_DIR/origin-A.jsonl")"
grep -q 'term_x' "$CBP_LEDGER_DIR/origin-A.jsonl" || fail "원장에 ref=term_x 없음"

# ─────────────────────────────────────────────────────────
step 2 "record --kind=orca --ref=\$ORCA_TERMINAL_HANDLE → 거부 (자살 방지)"
set +e
ORCA_TERMINAL_HANDLE=term_self CBP_ORIGIN_ID=origin-A \
  "$SCRIPT" record --kind=orca --ref=term_self >/dev/null 2>&1
RC=$?
set -e
[ "$RC" -ne 0 ] || fail "self terminal 기록이 거부되지 않음 (rc=$RC)"
grep -q 'term_self' "$CBP_LEDGER_DIR/origin-A.jsonl" && fail "self terminal 이 원장에 들어감"

# ─────────────────────────────────────────────────────────
step 3 "reap (dry-run) → orca terminal close 커맨드 문자열 출력"
OUT=$(CBP_ORIGIN_ID=origin-A "$SCRIPT" reap)
printf '%s' "$OUT" | grep -q 'orca terminal close --terminal term_x' \
  || fail "orca terminal close 커맨드 문자열 없음: $OUT"
[ -s "$ORCA_LOG" ] && fail "dry-run 인데 orca 가 실제로 호출됨"

# ─────────────────────────────────────────────────────────
step 4 "reap 은 \$ORCA_TERMINAL_HANDLE 과 같은 ref 를 가진 행을 보존한다 (keep self)"
# origin-A 원장에는 term_x 만 (term_self 는 거부되어 안 들어감) — 별도 원장으로 self-ref 를 심는다.
CBP_ORIGIN_ID=origin-E "$SCRIPT" record --kind=orca --ref=term_keep-me >/dev/null
OUT=$(ORCA_TERMINAL_HANDLE=term_keep-me CBP_ORIGIN_ID=origin-E "$SCRIPT" reap)
printf '%s' "$OUT" | grep -q 'keep(self terminal) term_keep-me' \
  || fail "self terminal 행이 keep 되지 않음: $OUT"
printf '%s' "$OUT" | grep -q 'orca terminal close --terminal term_keep-me' \
  && fail "self terminal 인데 close 커맨드가 나옴: $OUT"

# ─────────────────────────────────────────────────────────
step 5 "cmux/tmux 행은 여전히 기존 close 커맨드 생성 (회귀 가드)"
CBP_ORIGIN_ID=origin-F "$SCRIPT" record --kind=cmux --ref=surface:900 >/dev/null
CBP_ORIGIN_ID=origin-F "$SCRIPT" record --kind=tmux --ref=%42 >/dev/null
OUT=$(CBP_ORIGIN_ID=origin-F "$SCRIPT" reap)
printf '%s' "$OUT" | grep -q 'close-surface --surface surface:900' \
  || fail "cmux close-surface 커맨드 회귀: $OUT"
printf '%s' "$OUT" | grep -q 'kill-pane -t %42' \
  || fail "tmux kill-pane 커맨드 회귀: $OUT"

echo ""
echo "OK"
