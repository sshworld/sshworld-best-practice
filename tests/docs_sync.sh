#!/usr/bin/env bash
# Slice D — README.md / CLAUDE.md 의 신규 키워드 동기화 검증.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
README="$REPO/README.md"
CLAUDE="$REPO/CLAUDE.md"

step() { echo "[$1] $2"; }
fail() { echo "❌ FAIL: $1" >&2; exit 1; }

for kw in "tmux-orchestrate" "parallel-consult" "limit-child-panes" "CLAUDE_MAX_CHILD_PANES" "tmux-pane.sh" "dispatch-slice-pane.sh" "Workflow 통합" ".claude/workflows" "reap" "CBP_LAUNCH_DEBUG"; do
  grep -F -- "$kw" "$README" > /dev/null || fail "README missing: $kw"
done
echo "[1] README 키워드 OK"

for kw in "tmux-orchestrate" "parallel-consult" "limit-child-panes" "CLAUDE_MAX_CHILD_PANES" "tmux-pane.sh" "dispatch-slice-pane.sh" ".claude/workflows" "reap" "CBP_LAUNCH_DEBUG"; do
  grep -F -- "$kw" "$CLAUDE" > /dev/null || fail "CLAUDE.md missing: $kw"
done
echo "[2] CLAUDE.md 키워드 OK"

echo "OK"
