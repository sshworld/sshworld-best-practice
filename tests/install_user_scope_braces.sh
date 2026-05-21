#!/usr/bin/env bash
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0; FAILED=()
run() { local name="$1"; shift; if "$@" >/dev/null 2>&1; then echo "✔ $name"; PASS=$((PASS+1)); else echo "✘ $name"; FAIL=$((FAIL+1)); FAILED+=("$name"); fi; }

t_braces_pattern_converted() {
  local TMP; TMP=$(mktemp -d) || return 1
  trap "rm -rf $TMP" RETURN
  HOME="$TMP" "$REPO/install.sh" user >/dev/null 2>&1 || return 1
  # 변환 후엔 어떤 hook command 에도 ${CLAUDE_PROJECT_DIR} 또는 $CLAUDE_PROJECT_DIR 잔재 없어야
  ! jq -e '[.. | objects | select(.command? != null) | .command | test("\\$\\{?CLAUDE_PROJECT_DIR\\}?")] | any' \
       "$TMP/.claude/settings.json" >/dev/null 2>&1
}

t_dollar_form_still_converted() {
  local TMP; TMP=$(mktemp -d) || return 1
  trap "rm -rf $TMP" RETURN
  HOME="$TMP" "$REPO/install.sh" user >/dev/null 2>&1 || return 1
  # 변환 결과로 $HOME 가 있어야 함 (= 적어도 한 command 변환됨)
  jq -e '[.. | objects | select(.command? != null) | .command | contains("$HOME")] | any' \
     "$TMP/.claude/settings.json" >/dev/null 2>&1
}

run "braces 패턴 변환됨" t_braces_pattern_converted
run "dollar 형 회귀 변환 여전" t_dollar_form_still_converted

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && echo "✅ all pass" || { echo "❌ FAILED: ${FAILED[*]}"; exit 1; }
