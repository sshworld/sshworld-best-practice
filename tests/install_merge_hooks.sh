#!/usr/bin/env bash
# TDD: install.sh hook merge union 정책 검증 (6 케이스)

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0; FAILED=()
run() { local name="$1"; shift; if "$@" >/dev/null 2>&1; then PASS=$((PASS+1)); echo "✔ $name"; else FAIL=$((FAIL+1)); FAILED+=("$name"); echo "✘ $name"; fi; }

mk_existing_settings() {
  local dir="$1"; local body="$2"
  mkdir -p "$dir/.claude"
  printf '%s' "$body" > "$dir/.claude/settings.json"
}

# T1: Union 핵심 — 기존 Write|Edit hook 보존 + repo hook 추가
t1_union_writeedit() {
  local TMP; TMP=$(mktemp -d); trap "rm -rf $TMP" RETURN
  mk_existing_settings "$TMP" '{
    "hooks": {
      "PreToolUse": [
        { "matcher": "Write|Edit",
          "hooks": [{"type":"command","command":"existing-A"}] }
      ]
    }
  }'
  "$REPO/install.sh" project "$TMP" > /dev/null 2>&1 || return 1
  # existing-A 보존
  jq -e '.hooks.PreToolUse[] | select(.matcher == "Write|Edit") | .hooks | map(.command) | index("existing-A") | . != null' \
    "$TMP/.claude/settings.json" > /dev/null || return 1
  # repo 의 enforce-test-first 도 들어와야
  jq -e '[.hooks.PreToolUse[] | select(.matcher == "Write|Edit") | .hooks[] | .command | test("enforce-test-first")] | any' \
    "$TMP/.claude/settings.json" > /dev/null || return 1
  return 0
}

# T2: Idempotent — 두 번 install 해도 중복 없음
t2_idempotent() {
  local TMP; TMP=$(mktemp -d); trap "rm -rf $TMP" RETURN
  mk_existing_settings "$TMP" '{
    "hooks": {
      "PreToolUse": [
        { "matcher": "Write|Edit",
          "hooks": [{"type":"command","command":"existing-A"}] }
      ]
    }
  }'
  "$REPO/install.sh" project "$TMP" > /dev/null 2>&1 || return 1
  local count1
  count1=$(jq '.hooks.PreToolUse[] | select(.matcher == "Write|Edit") | .hooks | length' "$TMP/.claude/settings.json")
  "$REPO/install.sh" project "$TMP" > /dev/null 2>&1 || return 1
  local count2
  count2=$(jq '.hooks.PreToolUse[] | select(.matcher == "Write|Edit") | .hooks | length' "$TMP/.claude/settings.json")
  [ "$count1" -eq "$count2" ] || return 1
  return 0
}

# T3: Matcher 격리 — Write|Edit 추가가 Bash 에 흘러들지 않음
t3_matcher_isolation() {
  local TMP; TMP=$(mktemp -d); trap "rm -rf $TMP" RETURN
  mk_existing_settings "$TMP" '{
    "hooks": {
      "PreToolUse": [
        { "matcher": "Bash",
          "hooks": [{"type":"command","command":"existing-bash-hook"}] }
      ]
    }
  }'
  "$REPO/install.sh" project "$TMP" > /dev/null 2>&1 || return 1
  # existing-bash-hook 보존
  jq -e '.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks | map(.command) | index("existing-bash-hook") | . != null' \
    "$TMP/.claude/settings.json" > /dev/null || return 1
  # Bash matcher 에 enforce-test-first 가 없어야 (Write|Edit 전용)
  local bash_has_test_first
  bash_has_test_first=$(jq '[.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks[] | .command | test("enforce-test-first")] | any' \
    "$TMP/.claude/settings.json")
  [ "$bash_has_test_first" = "false" ] || return 1
  # Bash matcher 에 repo 의 Bash hooks 도 들어와야
  jq -e '[.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks[] | .command | test("enforce-doc-sync")] | any' \
    "$TMP/.claude/settings.json" > /dev/null || return 1
  return 0
}

# T4: 새 event 추가 — 기존에 PreToolUse 만 있을 때 SessionStart/Stop 추가
t4_new_event() {
  local TMP; TMP=$(mktemp -d); trap "rm -rf $TMP" RETURN
  mk_existing_settings "$TMP" '{
    "hooks": {
      "PreToolUse": [
        { "matcher": "Bash",
          "hooks": [{"type":"command","command":"existing-bash-hook"}] }
      ]
    }
  }'
  "$REPO/install.sh" project "$TMP" > /dev/null 2>&1 || return 1
  jq -e '.hooks.SessionStart | length > 0' "$TMP/.claude/settings.json" > /dev/null || return 1
  jq -e '.hooks.Stop | length > 0' "$TMP/.claude/settings.json" > /dev/null || return 1
  return 0
}

# T5: permissions 회귀 — 기존 allow/deny 보존 + repo union
t5_perms() {
  local TMP; TMP=$(mktemp -d); trap "rm -rf $TMP" RETURN
  mk_existing_settings "$TMP" '{
    "permissions": {
      "allow": ["Bash(custom-cmd*)"],
      "deny":  ["Bash(custom-deny*)"]
    }
  }'
  "$REPO/install.sh" project "$TMP" > /dev/null 2>&1 || return 1
  jq -e '.permissions.allow | index("Bash(custom-cmd*)") | . != null' \
    "$TMP/.claude/settings.json" > /dev/null || return 1
  jq -e '.permissions.deny  | index("Bash(custom-deny*)") | . != null' \
    "$TMP/.claude/settings.json" > /dev/null || return 1
  return 0
}

# T6: 다른 top-level 키 보존 — model 키 유지
t6_other_top() {
  local TMP; TMP=$(mktemp -d); trap "rm -rf $TMP" RETURN
  mk_existing_settings "$TMP" '{
    "model": "opus",
    "hooks": {}
  }'
  "$REPO/install.sh" project "$TMP" > /dev/null 2>&1 || return 1
  jq -e '.model == "opus"' "$TMP/.claude/settings.json" > /dev/null || return 1
  return 0
}

run "T1 union write|edit" t1_union_writeedit
run "T2 idempotent" t2_idempotent
run "T3 matcher 격리" t3_matcher_isolation
run "T4 새 event 추가" t4_new_event
run "T5 permissions 회귀" t5_perms
run "T6 다른 top-level 키 보존" t6_other_top

# T7: hook 파일명 dedup — 기존 plain hook + repo command 시, repo 가 winner (1라인만).
# repo settings.json 의 track-cmux-edit-burst command 는 advisory only (inline STRICT 제거됨).
t7_hook_filename_dedup() {
  local TMP; TMP=$(mktemp -d); trap "rm -rf $TMP" RETURN
  mk_existing_settings "$TMP" '{
    "hooks": {
      "PreToolUse": [
        { "matcher": "Write|Edit",
          "hooks": [{"type":"command","command":"$HOME/.claude/hooks/track-cmux-edit-burst.sh --old-flag"}] }
      ]
    }
  }'
  HOME="$TMP" "$REPO/install.sh" user > /dev/null 2>&1 || return 1
  local count
  count=$(jq '[.hooks.PreToolUse[] | select(.matcher == "Write|Edit") | .hooks[] | select(.command | test("track-cmux-edit-burst\\.sh"))] | length' "$TMP/.claude/settings.json")
  # 같은 hook 파일명 → 1라인만 (repo winner, 기존 --old-flag dedup 됨)
  [ "$count" -eq 1 ] || return 1
  # repo command 는 inline STRICT 없음 (advisory only) — 기존 --old-flag 도 사라짐
  jq -e '.hooks.PreToolUse[] | select(.matcher == "Write|Edit") | .hooks[] | select(.command | test("track-cmux-edit-burst\\.sh")) | .command | (contains("CMUX_EDIT_BURST_STRICT=1") | not) and (contains("--old-flag") | not)' \
    "$TMP/.claude/settings.json" >/dev/null || return 1
  return 0
}

# T8: 비-hook custom 명령 보존 — hooks/ 경로 아닌 사용자 custom 은 그대로
t8_custom_non_hook_preserved() {
  local TMP; TMP=$(mktemp -d); trap "rm -rf $TMP" RETURN
  mk_existing_settings "$TMP" '{
    "hooks": {
      "PreToolUse": [
        { "matcher": "Write|Edit",
          "hooks": [{"type":"command","command":"my-custom-bash-script.sh"}] }
      ]
    }
  }'
  "$REPO/install.sh" project "$TMP" > /dev/null 2>&1 || return 1
  jq -e '[.hooks.PreToolUse[] | select(.matcher == "Write|Edit") | .hooks[] | .command] | index("my-custom-bash-script.sh") | . != null' \
    "$TMP/.claude/settings.json" >/dev/null || return 1
  return 0
}

run "T7 hook 파일명 dedup (repo winner)" t7_hook_filename_dedup
run "T8 비-hook custom 명령 보존" t8_custom_non_hook_preserved

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && echo "✅ all pass" || { echo "❌ FAILED: ${FAILED[*]}"; exit 1; }
