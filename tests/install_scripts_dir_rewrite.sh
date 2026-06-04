#!/usr/bin/env bash
# S4 — install 시점 @@SCRIPTS_DIR@@ 절대경로 bake 검증

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

step() { echo "[$1] $2"; }
fail() { echo "❌ FAIL: $1" >&2; exit 1; }

step 1 "install user scope"
HOME="$TMP" bash "$REPO/install.sh" user > /dev/null 2>&1 || fail "install failed"

# 검증 1: dest .claude/ 에 @@SCRIPTS_DIR@@ 잔재 없음
step 2 "@@SCRIPTS_DIR@@ 잔재 없음"
if grep -rq '@@SCRIPTS_DIR@@' "$TMP/.claude" 2>/dev/null; then
  echo "잔재 발견:" >&2
  grep -rn '@@SCRIPTS_DIR@@' "$TMP/.claude" >&2
  fail "@@SCRIPTS_DIR@@ remains in dest .claude/"
fi

# 검증 2: cmux-dispatch-hint.sh 에 절대경로 존재
step 3 "절대경로 bake 확인 (cmux-dispatch-hint.sh)"
grep -q "$TMP/scripts/" "$TMP/.claude/hooks/cmux-dispatch-hint.sh" \
  || fail "no absolute path baked in cmux-dispatch-hint.sh"

# 검증 3: enforce-cmux-context.sh case matcher 보존
step 4 "enforce-cmux-context.sh case matcher 보존"
grep -q 'scripts/tmux-pane\.sh)' "$TMP/.claude/hooks/enforce-cmux-context.sh" \
  || fail "case matcher 'scripts/tmux-pane.sh)' not preserved in enforce-cmux-context.sh"

echo "OK"
