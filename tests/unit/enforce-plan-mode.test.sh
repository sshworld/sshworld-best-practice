#!/usr/bin/env bash
# enforce-plan-mode.sh hook 단위 테스트.
# PreToolUse Write|Edit — plan-dev 마커 활성 + plan mode 미진입 시 Edit/Write 차단.
# "plan mode 거침" 판정 = marker 보다 newer 한 plan 파일이 PLANS_DIR 에 존재.
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="$REPO/.claude/hooks/enforce-plan-mode.sh"
PASS=0; FAIL=0; FAILED=()
run() { local name="$1"; shift; if "$@" >/dev/null 2>&1; then echo "✔ $name"; PASS=$((PASS+1)); else echo "✘ $name"; FAIL=$((FAIL+1)); FAILED+=("$name"); fi; }

# tmp 에 marker(start_ts 포함) + plans dir 구성. $2=plan_state(none|newer|older). echo "marker|plans".
# 판정은 marker 파일 mtime 이 아니라 start_ts JSON 필드 기준.
mk_env() {
  local tmp="$1" state="$2"
  local marker="$tmp/marker.json" plans="$tmp/plans"
  mkdir -p "$plans"
  local now; now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  case "$state" in
    none)  printf '{"start_ts":"%s"}' "$now" > "$marker" ;;
    older) echo '{}' > "$plans/p.md"; sleep 2; now=$(date -u +%Y-%m-%dT%H:%M:%SZ); printf '{"start_ts":"%s"}' "$now" > "$marker" ;;
    newer) printf '{"start_ts":"%s"}' "$now" > "$marker"; sleep 2; echo '{}' > "$plans/p.md" ;;
  esac
  echo "$marker|$plans"
}

t_no_marker_allows() {
  local tmp; tmp=$(mktemp -d)
  echo '{"tool_name":"Edit","permission_mode":"default"}' | \
    PLAN_MODE_SESSION_FILE="$tmp/nope.json" PLAN_MODE_PLANS_DIR="$tmp/plans" bash "$HOOK"
  local ec=$?; rm -rf "$tmp"; [ "$ec" = "0" ]
}

t_newer_plan_allows() {
  local tmp; tmp=$(mktemp -d); local e; e=$(mk_env "$tmp" newer)
  echo '{"tool_name":"Edit","permission_mode":"default"}' | \
    PLAN_MODE_SESSION_FILE="${e%|*}" PLAN_MODE_PLANS_DIR="${e#*|}" bash "$HOOK"
  local ec=$?; rm -rf "$tmp"; [ "$ec" = "0" ]
}

t_no_plan_blocks() {
  local tmp; tmp=$(mktemp -d); local e; e=$(mk_env "$tmp" none)
  echo '{"tool_name":"Edit","permission_mode":"default"}' | \
    PLAN_MODE_SESSION_FILE="${e%|*}" PLAN_MODE_PLANS_DIR="${e#*|}" bash "$HOOK"
  local ec=$?; rm -rf "$tmp"; [ "$ec" = "2" ]
}

t_older_plan_blocks() {
  local tmp; tmp=$(mktemp -d); local e; e=$(mk_env "$tmp" older)
  echo '{"tool_name":"Edit","permission_mode":"default"}' | \
    PLAN_MODE_SESSION_FILE="${e%|*}" PLAN_MODE_PLANS_DIR="${e#*|}" bash "$HOOK"
  local ec=$?; rm -rf "$tmp"; [ "$ec" = "2" ]
}

t_plan_mode_allows_even_no_plan() {
  local tmp; tmp=$(mktemp -d); local e; e=$(mk_env "$tmp" none)
  echo '{"tool_name":"Write","permission_mode":"plan"}' | \
    PLAN_MODE_SESSION_FILE="${e%|*}" PLAN_MODE_PLANS_DIR="${e#*|}" bash "$HOOK"
  local ec=$?; rm -rf "$tmp"; [ "$ec" = "0" ]
}

t_bypass_allows() {
  local tmp; tmp=$(mktemp -d); local e; e=$(mk_env "$tmp" none)
  echo '{"tool_name":"Edit","permission_mode":"bypassPermissions"}' | \
    PLAN_MODE_SESSION_FILE="${e%|*}" PLAN_MODE_PLANS_DIR="${e#*|}" bash "$HOOK"
  local ec=$?; rm -rf "$tmp"; [ "$ec" = "0" ]
}

t_skip_env_allows() {
  local tmp; tmp=$(mktemp -d); local e; e=$(mk_env "$tmp" none)
  echo '{"tool_name":"Edit","permission_mode":"default"}' | \
    SKIP_PLAN_MODE_ENFORCE=1 PLAN_MODE_SESSION_FILE="${e%|*}" PLAN_MODE_PLANS_DIR="${e#*|}" bash "$HOOK"
  local ec=$?; rm -rf "$tmp"; [ "$ec" = "0" ]
}

t_disable_env_allows() {
  local tmp; tmp=$(mktemp -d); local e; e=$(mk_env "$tmp" none)
  echo '{"tool_name":"Edit","permission_mode":"default"}' | \
    DISABLE_PLAN_MODE_ENFORCE_HOOK=1 PLAN_MODE_SESSION_FILE="${e%|*}" PLAN_MODE_PLANS_DIR="${e#*|}" bash "$HOOK"
  local ec=$?; rm -rf "$tmp"; [ "$ec" = "0" ]
}

t_non_write_allows() {
  local tmp; tmp=$(mktemp -d); local e; e=$(mk_env "$tmp" none)
  echo '{"tool_name":"Bash","permission_mode":"default"}' | \
    PLAN_MODE_SESSION_FILE="${e%|*}" PLAN_MODE_PLANS_DIR="${e#*|}" bash "$HOOK"
  local ec=$?; rm -rf "$tmp"; [ "$ec" = "0" ]
}

run "마커 없음 → allow(0)"                          t_no_marker_allows
run "newer plan 존재 → allow(0)"                    t_newer_plan_allows
run "plan 없음 → block(2)"                          t_no_plan_blocks
run "older plan(marker 가 newer) → block(2)"        t_older_plan_blocks
run "permission_mode=plan → allow(0) (plan 없어도)" t_plan_mode_allows_even_no_plan
run "bypassPermissions → allow(0)"                  t_bypass_allows
run "SKIP_PLAN_MODE_ENFORCE=1 → allow(0)"            t_skip_env_allows
run "DISABLE_PLAN_MODE_ENFORCE_HOOK=1 → allow(0)"    t_disable_env_allows
run "비 Write|Edit(Bash) → allow(0)"                t_non_write_allows

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && echo "✅ all pass" || { echo "❌ FAILED: ${FAILED[*]}"; exit 1; }
