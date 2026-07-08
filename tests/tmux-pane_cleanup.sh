#!/usr/bin/env bash
# Slice I — tmux-pane.sh cleanup 명령 검증.
# tmux-pane-mgr 세션 안에 더미 pane 들 만든 후 cleanup 호출 → 세션 자체 정리되는지 검증.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WRAPPER="$REPO/scripts/tmux-pane.sh"

step() { echo "[$1] $2"; }
fail() { echo "❌ FAIL: $1" >&2; exit 1; }

if ! command -v tmux > /dev/null 2>&1; then
  echo "SKIP: tmux not installed"
  exit 0
fi

unset TMUX

# 기존 tmux-pane-mgr 정리 (테스트 격리)
tmux kill-session -t tmux-pane-mgr 2>/dev/null || true

step 1 "wrapper 로 자식 pane 3개 spawn"
PANE1=$("$WRAPPER" launch zsh)
PANE2=$("$WRAPPER" launch zsh)
PANE3=$("$WRAPPER" launch zsh)
COUNT_BEFORE=$(tmux list-panes -s -t tmux-pane-mgr -F '#{pane_id}' 2>/dev/null | wc -l | tr -d ' ')
[ "$COUNT_BEFORE" -ge 3 ] || fail "spawn 후 pane 수 부족: $COUNT_BEFORE"

step 2 "cleanup 호출 → 자식 N개 stderr 보고 + 세션 kill"
OUT=$("$WRAPPER" cleanup 2>&1)
RC=$?
[ "$RC" = "0" ] || fail "cleanup exit code 비정상: $RC"
echo "$OUT" | grep -E "cleaning [0-9]+ child pane" > /dev/null || fail "cleanup 보고 메시지 누락: $OUT"

step 3 "tmux-pane-mgr 세션이 사라짐"
if tmux has-session -t tmux-pane-mgr 2>/dev/null; then
  fail "cleanup 후에도 세션 존재"
fi

step 4 "cleanup — 정리할 게 없으면 0 보고 + exit 0"
OUT=$("$WRAPPER" cleanup 2>&1)
RC=$?
[ "$RC" = "0" ] || fail "빈 cleanup exit 비정상: $RC"
echo "$OUT" | grep -E "cleaning 0 child pane|no child panes" > /dev/null || fail "빈 cleanup 보고 누락: $OUT"

step 5 "launch 이 spawn 한 pane 에 @cbp_child=1 태깅됨 (R1) — do_cleanup 의 self-window 스코프 필터 근거"
PANE4=$("$WRAPPER" launch zsh)
TAG=$(tmux show-options -p -t "$PANE4" -v @cbp_child 2>/dev/null || true)
[ "$TAG" = "1" ] || fail "@cbp_child 태깅 안 됨 (pane=$PANE4, tag='$TAG')"
tmux kill-session -t tmux-pane-mgr 2>/dev/null || true

echo "OK"
