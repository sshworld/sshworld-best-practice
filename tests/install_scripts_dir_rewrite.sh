#!/usr/bin/env bash
# install 시점 @@SCRIPTS_DIR@@ → ${CLAUDE_PLUGIN_ROOT}/scripts 변환 검증.
# install.sh deprecated → 이제 소스 파일 자체가 이미 변환된 상태여야 함.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

step() { echo "[$1] $2"; }
fail() { echo "❌ FAIL: $1" >&2; exit 1; }

step 1 "@@SCRIPTS_DIR@@ 잔재 없음 (commands/ agents/ hooks/)"
if grep -rq '@@SCRIPTS_DIR@@' "$REPO/commands" "$REPO/agents" "$REPO/hooks" 2>/dev/null; then
  echo "잔재 발견:" >&2
  grep -rn '@@SCRIPTS_DIR@@' "$REPO/commands" "$REPO/agents" "$REPO/hooks" >&2
  fail "@@SCRIPTS_DIR@@ remains in plugin source files"
fi

step 2 'CLAUDE_PLUGIN_ROOT 사용 확인 (hooks/cmux-dispatch-hint.sh)'
grep -q 'CLAUDE_PLUGIN_ROOT' "$REPO/hooks/cmux-dispatch-hint.sh" \
  || fail "CLAUDE_PLUGIN_ROOT not found in cmux-dispatch-hint.sh"

step 3 "enforce-cmux-context.sh case matcher 보존"
grep -q 'scripts/tmux-pane\.sh[|)]' "$REPO/hooks/enforce-cmux-context.sh" \
  || fail "case matcher 'scripts/tmux-pane.sh' not preserved in enforce-cmux-context.sh"

echo "OK"
