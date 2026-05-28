#!/usr/bin/env bash
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0; FAILED=()
run() { local name="$1"; shift; if "$@" >/dev/null 2>&1; then echo "✔ $name"; PASS=$((PASS+1)); else echo "✘ $name"; FAIL=$((FAIL+1)); FAILED+=("$name"); fi; }

t_settings_inline_strict() {
  jq -e '
    .hooks.PreToolUse[]
    | select(.matcher == "Write|Edit")
    | .hooks[]
    | select(.command | contains("track-cmux-edit-burst.sh"))
    | .command
    | contains("CMUX_EDIT_BURST_STRICT=1")
  ' "$REPO/.claude/settings.json" >/dev/null
}

t_hook_threshold_default_2() {
  grep -F 'CMUX_EDIT_BURST_THRESHOLD:-2' "$REPO/.claude/hooks/track-cmux-edit-burst.sh" >/dev/null
}

t_skip_advisory_message() {
  grep -F "의식적으로 검토" "$REPO/.claude/hooks/track-cmux-edit-burst.sh" >/dev/null
}

run "settings.json hook command 라인에 CMUX_EDIT_BURST_STRICT=1 inline" t_settings_inline_strict
run "hook 파일 디폴트 임계치 2" t_hook_threshold_default_2
run "SKIP 메시지에 '의식적으로 검토' 권고" t_skip_advisory_message

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && echo "✅ all pass" || { echo "❌ FAILED: ${FAILED[*]}"; exit 1; }
