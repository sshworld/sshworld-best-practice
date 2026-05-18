#!/usr/bin/env bash
# Slice A 스모크 — scripts/tmux-pane.sh 의 CLI 계약 e2e 검증.
# tmux 없으면 SKIP (CI 환경 등 고려).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WRAPPER="$SCRIPT_DIR/scripts/tmux-pane.sh"

step() { echo ""; echo "[$1] $2"; }
fail() { echo "❌ FAIL: $1" >&2; exit 1; }

if ! command -v tmux > /dev/null 2>&1; then
  echo "SKIP: tmux not installed"
  exit 0
fi

if [ ! -x "$WRAPPER" ]; then
  fail "wrapper not executable: $WRAPPER"
fi

# 본 테스트는 tmux 세션 안에서 돌릴 수 없으면 (TMUX 없으면) wrapper 의 remote mode 가 자동 동작.
# 깔끔한 격리를 위해 임시 세션 안에서 실행.

SESSION="tmux-pane-smoke-$$"
tmux new-session -d -s "$SESSION" -x 200 -y 50 'sleep 60'
trap 'tmux kill-session -t "$SESSION" 2>/dev/null || true' EXIT

# wrapper 호출은 TMUX env 가 있어야 in-tmux mode. 대신 attach 없이 client-less 로 돌리려면
# wrapper 가 새 session 을 만들지 않게 wrapping.
RUN_IN_TMUX() {
  tmux send-keys -t "$SESSION" "$*" Enter
}

# 더 단순한 접근: wrapper 자체가 TMUX env 부재 시 remote mode 로 'tmux-pane-mgr' 세션을 자동 생성.
# 그 모드에서 검증.
unset TMUX

step 1 "launch zsh"
PANE=$("$WRAPPER" launch zsh) || fail "launch failed (exit=$?)"
echo "  pane=$PANE"
[[ "$PANE" =~ ^[a-zA-Z0-9_.-]+:[0-9]+\.[0-9]+$ ]] || fail "pane id format invalid: $PANE"

step 2 "send echo command"
"$WRAPPER" send "echo hello-tmux-pane" --pane="$PANE" || fail "send failed (exit=$?)"

step 3 "wait-idle"
"$WRAPPER" wait-idle --pane="$PANE" --idle=1 --timeout=10 || fail "wait-idle failed (exit=$?)"

step 4 "capture contains hello-tmux-pane"
OUT=$("$WRAPPER" capture --pane="$PANE") || fail "capture failed (exit=$?)"
echo "$OUT" | grep -q "hello-tmux-pane" || fail "capture output missing marker: $OUT"

step 5 "list returns parseable JSON"
LIST=$("$WRAPPER" list) || fail "list failed (exit=$?)"
echo "$LIST" | python3 -c "import json,sys; json.load(sys.stdin)" || fail "list output not JSON: $LIST"

step 6 "self-kill rejected (exit 5)"
SELF=$("$WRAPPER" launch zsh)
# wrapper 의 자기 pane 검사 로직 — 호출자가 외부라 실제 self 비교 불가.
# CLAUDE_FAKE_SELF_PANE 로 self 를 주입해 거부 동작 검증.
OUT=$(CLAUDE_FAKE_SELF_PANE="$SELF" "$WRAPPER" kill --pane="$SELF" 2>&1)
RC=$?
[ "$RC" = "5" ] || fail "expected exit 5 on self-kill, got $RC; out=$OUT"
echo "$OUT" | grep -q "우회" || fail "self-kill stderr missing 우회: $OUT"

step 7 "FORCE_SELF_KILL=1 bypass"
FORCE_SELF_KILL=1 CLAUDE_FAKE_SELF_PANE="$SELF" "$WRAPPER" kill --pane="$SELF" || fail "force-self-kill failed"

step 8 "normal kill"
"$WRAPPER" kill --pane="$PANE" || fail "normal kill failed (exit=$?)"

echo ""
echo "OK"
