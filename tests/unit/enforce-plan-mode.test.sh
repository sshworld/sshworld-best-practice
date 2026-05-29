#!/usr/bin/env bash
# enforce-plan-mode.sh hook 단위 테스트.
# PreToolUse Write|Edit — plan-dev 마커 활성 + plan mode 미진입 시 Edit/Write 차단.
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="$REPO/.claude/hooks/enforce-plan-mode.sh"
PASS=0; FAIL=0; FAILED=()
run() { local name="$1"; shift; if "$@" >/dev/null 2>&1; then echo "✔ $name"; PASS=$((PASS+1)); else echo "✘ $name"; FAIL=$((FAIL+1)); FAILED+=("$name"); fi; }

# hook 실행 헬퍼: payload(stdin) + env override. exit code 반환.
# $1=payload $2=marker(존재시 생성) $3=flag(존재시 생성). 나머지 env 는 호출측에서.
_mk() {
  local tmp; tmp=$(mktemp -d); echo "$tmp"
}

t_no_marker_allows() {
  local tmp; tmp=$(_mk)
  # 마커 파일 미생성 → exit 0
  echo '{"tool_name":"Edit","permission_mode":"default"}' | \
    PLAN_MODE_SESSION_FILE="$tmp/nope.json" PLAN_MODE_SEEN_FILE="$tmp/seen" \
    bash "$HOOK"
  local ec=$?; rm -rf "$tmp"; [ "$ec" = "0" ]
}

t_plan_mode_records_flag_and_allows() {
  local tmp; tmp=$(_mk)
  echo '{}' > "$tmp/marker.json"
  echo '{"tool_name":"Write","permission_mode":"plan"}' | \
    PLAN_MODE_SESSION_FILE="$tmp/marker.json" PLAN_MODE_SEEN_FILE="$tmp/seen" \
    bash "$HOOK"
  local ec=$?
  local flag_made=1; [ -f "$tmp/seen" ] || flag_made=0
  rm -rf "$tmp"
  [ "$ec" = "0" ] && [ "$flag_made" = "1" ]
}

t_default_with_flag_allows() {
  local tmp; tmp=$(_mk)
  echo '{}' > "$tmp/marker.json"; touch "$tmp/seen"
  echo '{"tool_name":"Edit","permission_mode":"default"}' | \
    PLAN_MODE_SESSION_FILE="$tmp/marker.json" PLAN_MODE_SEEN_FILE="$tmp/seen" \
    bash "$HOOK"
  local ec=$?; rm -rf "$tmp"; [ "$ec" = "0" ]
}

t_default_no_flag_blocks() {
  local tmp; tmp=$(_mk)
  echo '{}' > "$tmp/marker.json"
  echo '{"tool_name":"Edit","permission_mode":"default"}' | \
    PLAN_MODE_SESSION_FILE="$tmp/marker.json" PLAN_MODE_SEEN_FILE="$tmp/seen" \
    bash "$HOOK"
  local ec=$?; rm -rf "$tmp"; [ "$ec" = "2" ]
}

t_bypass_perm_mode_skips() {
  local tmp; tmp=$(_mk)
  echo '{}' > "$tmp/marker.json"
  echo '{"tool_name":"Edit","permission_mode":"bypassPermissions"}' | \
    PLAN_MODE_SESSION_FILE="$tmp/marker.json" PLAN_MODE_SEEN_FILE="$tmp/seen" \
    bash "$HOOK"
  local ec=$?; rm -rf "$tmp"; [ "$ec" = "0" ]
}

t_skip_env_allows() {
  local tmp; tmp=$(_mk)
  echo '{}' > "$tmp/marker.json"
  echo '{"tool_name":"Edit","permission_mode":"default"}' | \
    SKIP_PLAN_MODE_ENFORCE=1 PLAN_MODE_SESSION_FILE="$tmp/marker.json" PLAN_MODE_SEEN_FILE="$tmp/seen" \
    bash "$HOOK"
  local ec=$?; rm -rf "$tmp"; [ "$ec" = "0" ]
}

t_disable_env_allows() {
  local tmp; tmp=$(_mk)
  echo '{}' > "$tmp/marker.json"
  echo '{"tool_name":"Edit","permission_mode":"default"}' | \
    DISABLE_PLAN_MODE_ENFORCE_HOOK=1 PLAN_MODE_SESSION_FILE="$tmp/marker.json" PLAN_MODE_SEEN_FILE="$tmp/seen" \
    bash "$HOOK"
  local ec=$?; rm -rf "$tmp"; [ "$ec" = "0" ]
}

t_non_write_tool_allows() {
  local tmp; tmp=$(_mk)
  echo '{}' > "$tmp/marker.json"
  echo '{"tool_name":"Bash","permission_mode":"default"}' | \
    PLAN_MODE_SESSION_FILE="$tmp/marker.json" PLAN_MODE_SEEN_FILE="$tmp/seen" \
    bash "$HOOK"
  local ec=$?; rm -rf "$tmp"; [ "$ec" = "0" ]
}

run "마커 없음 → allow(0)"                       t_no_marker_allows
run "permission_mode=plan → flag 기록 + allow(0)" t_plan_mode_records_flag_and_allows
run "default + flag 존재 → allow(0)"             t_default_with_flag_allows
run "default + flag 없음 → block(2)"             t_default_no_flag_blocks
run "bypassPermissions → skip(0)"                t_bypass_perm_mode_skips
run "SKIP_PLAN_MODE_ENFORCE=1 → allow(0)"         t_skip_env_allows
run "DISABLE_PLAN_MODE_ENFORCE_HOOK=1 → allow(0)" t_disable_env_allows
run "비 Write|Edit tool(Bash) → allow(0)"        t_non_write_tool_allows

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && echo "✅ all pass" || { echo "❌ FAILED: ${FAILED[*]}"; exit 1; }
