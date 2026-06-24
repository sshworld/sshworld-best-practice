#!/usr/bin/env bash
# install user scope deprecated → hooks/hooks.json ${CLAUDE_PLUGIN_ROOT} 기반 경로 검증.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0; FAILED=()
run() { local name="$1"; shift; if "$@" >/dev/null 2>&1; then echo "✔ $name"; PASS=$((PASS+1)); else echo "✘ $name"; FAIL=$((FAIL+1)); FAILED+=("$name"); fi; }

t_hooks_json_no_project_dir() {
  # hooks.json 에 $CLAUDE_PROJECT_DIR 잔재 없음 (${CLAUDE_PLUGIN_ROOT} 로 교체됨)
  ! grep -q 'CLAUDE_PROJECT_DIR' "$REPO/hooks/hooks.json"
}

t_hooks_json_has_plugin_root() {
  # hooks.json 에 ${CLAUDE_PLUGIN_ROOT} 사용
  grep -q 'CLAUDE_PLUGIN_ROOT' "$REPO/hooks/hooks.json"
}

run "hooks.json CLAUDE_PROJECT_DIR 잔재 없음" t_hooks_json_no_project_dir
run "hooks.json CLAUDE_PLUGIN_ROOT 사용" t_hooks_json_has_plugin_root

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && echo "✅ all pass" || { echo "❌ FAILED: ${FAILED[*]}"; exit 1; }
