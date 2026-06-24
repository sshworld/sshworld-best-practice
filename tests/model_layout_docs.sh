#!/usr/bin/env bash
# Slice H — Slice F/G 변경에 따른 문서 갱신 lint.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PC="$REPO/commands/parallel-consult.md"
PD="$REPO/commands/plan-dev.md"
README="$REPO/README.md"
CLAUDE="$REPO/CLAUDE.md"

step() { echo "[$1] $2"; }
fail() { echo "❌ FAIL: $1" >&2; exit 1; }

step 1 "parallel-consult.md 의 --model / alias 가이드"
grep -F -- "--model" "$PC" > /dev/null || fail "parallel-consult.md 에 --model 누락"
grep -F "alias" "$PC" > /dev/null || fail "parallel-consult.md 에 alias 가이드 누락"
grep -E 'claude --model' "$PC" > /dev/null || fail "parallel-consult.md 에 'claude --model' 호출 예 누락"

step 2 "plan-dev.md 의 --model 옵션 안내"
grep -F -- "--model" "$PD" > /dev/null || fail "plan-dev.md 에 --model 누락"

step 3 "README — TMUX_PANE_NO_LAYOUT + DISPATCH_DEFAULT_MODEL + tmux.conf 권장"
grep -F "TMUX_PANE_NO_LAYOUT" "$README" > /dev/null || fail "README 에 TMUX_PANE_NO_LAYOUT 누락"
grep -F "DISPATCH_DEFAULT_MODEL" "$README" > /dev/null || fail "README 에 DISPATCH_DEFAULT_MODEL 누락"
grep -F "status-left" "$README" > /dev/null || fail "README 에 권장 tmux.conf status-left 누락"

step 4 "CLAUDE.md — 환경변수 표 갱신 + dispatcher model 인자 명시"
grep -F "TMUX_PANE_NO_LAYOUT" "$CLAUDE" > /dev/null || fail "CLAUDE 에 TMUX_PANE_NO_LAYOUT 누락"
grep -F "DISPATCH_DEFAULT_MODEL" "$CLAUDE" > /dev/null || fail "CLAUDE 에 DISPATCH_DEFAULT_MODEL 누락"

echo "OK"
