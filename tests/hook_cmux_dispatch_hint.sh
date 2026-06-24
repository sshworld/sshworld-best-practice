#!/usr/bin/env bash
# Tests for hooks/cmux-dispatch-hint.sh

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$REPO/hooks/cmux-dispatch-hint.sh"

PASS=0; FAIL=0; FAILED=()

run() {
  local name="$1"; shift
  if "$@" >/dev/null 2>&1; then
    PASS=$((PASS+1))
    echo "✔ $name"
  else
    FAIL=$((FAIL+1))
    FAILED+=("$name")
    echo "✘ $name" >&2
  fi
}

[ -x "$HOOK" ] || { echo "hook not executable: $HOOK" >&2; exit 1; }

# T1: CMUX_WORKSPACE_ID unset → stdout empty, exit 0
t1_unset_no_output() {
  local out rc=0
  out=$(unset CMUX_WORKSPACE_ID 2>/dev/null; "$HOOK" 2>/dev/null) || rc=$?
  [ "$rc" -eq 0 ] && [ -z "$out" ]
}

# T2: cmux env set → stdout contains "dispatch", exit 0
t2_cmux_env_hints() {
  local out rc=0
  out=$(CMUX_WORKSPACE_ID="test-ws" "$HOOK" 2>/dev/null) || rc=$?
  [ "$rc" -eq 0 ] && echo "$out" | grep -q "dispatch"
}

run "T1 unset no output"    t1_unset_no_output
run "T2 cmux env hints"     t2_cmux_env_hints

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && echo "✅ all pass" || { echo "❌ FAILED: ${FAILED[*]}"; exit 1; }
