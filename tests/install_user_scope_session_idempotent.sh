#!/usr/bin/env bash
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0; FAILED=()
run() { local name="$1"; shift; if "$@" >/dev/null 2>&1; then echo "✔ $name"; PASS=$((PASS+1)); else echo "✘ $name"; FAIL=$((FAIL+1)); FAILED+=("$name"); fi; }

t_idempotent() {
  local TMP; TMP=$(mktemp -d) || return 1
  trap "rm -rf $TMP" RETURN
  HOME="$TMP" "$REPO/install.sh" user >/dev/null 2>&1 || return 1
  local N1; N1=$(jq '.hooks.SessionStart[0].hooks | length' "$TMP/.claude/settings.json")
  HOME="$TMP" "$REPO/install.sh" user >/dev/null 2>&1 || return 1
  local N2; N2=$(jq '.hooks.SessionStart[0].hooks | length' "$TMP/.claude/settings.json")
  [ "$N1" = "$N2" ]
}

t_user_scope_normalized() {
  local TMP; TMP=$(mktemp -d) || return 1
  trap "rm -rf $TMP" RETURN
  HOME="$TMP" "$REPO/install.sh" user >/dev/null 2>&1 || return 1
  # inline command 안에 "$HOME/scripts/detect-pane-env.sh" 패턴이 있어야 (단순화 결과)
  # any 사용: [] 반복 시 마지막 false 로 인한 exit 1 방지
  jq -e '[.hooks.SessionStart[0].hooks[].command | contains("$HOME/scripts/detect-pane-env.sh")] | any' \
     "$TMP/.claude/settings.json" >/dev/null 2>&1
}

run "user-scope SessionStart idempotent (2회 install 길이 동일)" t_idempotent
run "변환 결과가 \$HOME/scripts/ 형태" t_user_scope_normalized

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && echo "✅ all pass" || { echo "❌ FAILED: ${FAILED[*]}"; exit 1; }
