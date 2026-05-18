#!/usr/bin/env bash
# Slice D — install.sh 의 신규 파일 배포 확인.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

step() { echo "[$1] $2"; }
fail() { echo "❌ FAIL: $1" >&2; exit 1; }

step 1 "install project"
"$REPO/install.sh" project "$TMP" > /dev/null 2>&1 || fail "install failed"

step 2 "신규 파일 배포 확인"
for f in \
  "scripts/tmux-pane.sh" \
  "scripts/dispatch-slice-pane.sh" \
  ".claude/skills/tmux-orchestrate/SKILL.md" \
  ".claude/commands/parallel-consult.md" \
  ".claude/hooks/limit-child-panes.sh"; do
  [ -f "$TMP/$f" ] || fail "missing in install: $f"
done

step 3 "실행 권한"
for f in \
  "scripts/tmux-pane.sh" \
  "scripts/dispatch-slice-pane.sh" \
  ".claude/hooks/limit-child-panes.sh"; do
  [ -x "$TMP/$f" ] || fail "not executable in install: $f"
done

echo "OK"
