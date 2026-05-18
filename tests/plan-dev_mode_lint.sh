#!/usr/bin/env bash
# Slice E lint — plan-dev.md 의 pane 모드 분기 + implementor.md 의 pane 안내 단락 검증.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLAN="$REPO/.claude/commands/plan-dev.md"
IMPL="$REPO/.claude/agents/implementor.md"

step() { echo "[$1] $2"; }
fail() { echo "❌ FAIL: $1" >&2; exit 1; }

step 1 "plan-dev.md 의 모드 분기 키워드"
for kw in "--mode=pane" "dispatch-slice-pane.sh" "tmux attach"; do
  grep -F -- "$kw" "$PLAN" > /dev/null || fail "plan-dev.md missing: $kw"
done
grep -E "회수 전 머지|회수 전에 머지" "$PLAN" > /dev/null || fail "plan-dev.md missing 회수-전-머지 안티패턴"

step 2 "implementor.md 의 pane 모드 안내"
grep -F "pane 모드" "$IMPL" > /dev/null || fail "implementor.md missing 'pane 모드'"
grep -F "tmux pane" "$IMPL" > /dev/null || fail "implementor.md missing 'tmux pane'"

echo "OK"
