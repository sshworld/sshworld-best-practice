#!/usr/bin/env bash
# install.sh deprecated → 플러그인 레이아웃 존재 검증으로 대체.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

step() { echo "[$1] $2"; }
fail() { echo "❌ FAIL: $1" >&2; exit 1; }

step 1 "install.sh deprecated shim"
out=$("$REPO/install.sh" 2>&1 || true)
echo "$out" | grep -qi "deprecated\|plugin" || fail "install.sh missing deprecation message"

step 2 "플러그인 파일 존재"
for f in \
  "scripts/tmux-pane.sh" \
  "scripts/dispatch-slice-pane.sh" \
  "skills/tmux-orchestrate/SKILL.md" \
  "commands/parallel-consult.md" \
  "hooks/limit-child-panes.sh" \
  ".claude-plugin/plugin.json" \
  "hooks/hooks.json"; do
  [ -f "$REPO/$f" ] || fail "missing plugin file: $f"
done

step 3 "실행 권한"
for f in \
  "scripts/tmux-pane.sh" \
  "scripts/dispatch-slice-pane.sh" \
  "hooks/limit-child-panes.sh"; do
  [ -x "$REPO/$f" ] || fail "not executable: $f"
done

echo "OK"
