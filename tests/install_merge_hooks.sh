#!/usr/bin/env bash
# TDD: merge-settings.sh hook merge union 정책 검증 (6 케이스)
# install.sh deprecated → merge-settings.sh 직접 호출로 대체.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MERGE="$REPO/scripts/merge-settings.sh"
PASS=0; FAIL=0; FAILED=()
run() { local name="$1"; shift; if "$@" >/dev/null 2>&1; then PASS=$((PASS+1)); echo "✔ $name"; else FAIL=$((FAIL+1)); FAILED+=("$name"); echo "✘ $name"; fi; }

# helper: write cur.json + new.json → merged
do_merge() {
  local cur="$1" new="$2" out="$3"
  bash "$MERGE" "$cur" "$new" > "$out"
}

NEW_SETTINGS="$REPO/.claude/settings.json"

# T1: Union 핵심 — 기존 Write|Edit hook 보존 + repo hook 추가
t1_union_writeedit() {
  local TMP; TMP=$(mktemp -d); trap "rm -rf $TMP" RETURN
  local cur="$TMP/cur.json" out="$TMP/merged.json"
  printf '%s' '{
    "hooks": {
      "PreToolUse": [
        { "matcher": "Write|Edit",
          "hooks": [{"type":"command","command":"existing-A"}] }
      ]
    }
  }' > "$cur"
  do_merge "$cur" "$NEW_SETTINGS" "$out" || return 1
  jq -e '.hooks.PreToolUse[] | select(.matcher == "Write|Edit") | .hooks | map(.command) | index("existing-A") | . != null' "$out" > /dev/null || return 1
  jq -e '[.hooks.PreToolUse[] | select(.matcher == "Write|Edit") | .hooks[] | .command | test("enforce-test-first")] | any' "$out" > /dev/null || return 1
  return 0
}

# T2: Idempotent — 두 번 merge 해도 중복 없음
t2_idempotent() {
  local TMP; TMP=$(mktemp -d); trap "rm -rf $TMP" RETURN
  local cur="$TMP/cur.json" m1="$TMP/m1.json" m2="$TMP/m2.json"
  printf '%s' '{
    "hooks": {
      "PreToolUse": [
        { "matcher": "Write|Edit",
          "hooks": [{"type":"command","command":"existing-A"}] }
      ]
    }
  }' > "$cur"
  do_merge "$cur" "$NEW_SETTINGS" "$m1" || return 1
  do_merge "$m1" "$NEW_SETTINGS" "$m2" || return 1
  local c1 c2
  c1=$(jq '.hooks.PreToolUse[] | select(.matcher == "Write|Edit") | .hooks | length' "$m1")
  c2=$(jq '.hooks.PreToolUse[] | select(.matcher == "Write|Edit") | .hooks | length' "$m2")
  [ "$c1" -eq "$c2" ] || return 1
  return 0
}

# T3: Matcher 격리 — Write|Edit 추가가 Bash 에 흘러들지 않음
t3_matcher_isolation() {
  local TMP; TMP=$(mktemp -d); trap "rm -rf $TMP" RETURN
  local cur="$TMP/cur.json" out="$TMP/merged.json"
  printf '%s' '{
    "hooks": {
      "PreToolUse": [
        { "matcher": "Bash",
          "hooks": [{"type":"command","command":"existing-bash-hook"}] }
      ]
    }
  }' > "$cur"
  do_merge "$cur" "$NEW_SETTINGS" "$out" || return 1
  jq -e '.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks | map(.command) | index("existing-bash-hook") | . != null' "$out" > /dev/null || return 1
  local bash_has_test_first
  bash_has_test_first=$(jq '[.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks[] | .command | test("enforce-test-first")] | any' "$out")
  [ "$bash_has_test_first" = "false" ] || return 1
  jq -e '[.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks[] | .command | test("enforce-doc-sync")] | any' "$out" > /dev/null || return 1
  return 0
}

# T4: 새 event 추가 — 기존에 PreToolUse 만 있을 때 SessionStart/Stop 추가
t4_new_event() {
  local TMP; TMP=$(mktemp -d); trap "rm -rf $TMP" RETURN
  local cur="$TMP/cur.json" out="$TMP/merged.json"
  printf '%s' '{
    "hooks": {
      "PreToolUse": [
        { "matcher": "Bash",
          "hooks": [{"type":"command","command":"existing-bash-hook"}] }
      ]
    }
  }' > "$cur"
  do_merge "$cur" "$NEW_SETTINGS" "$out" || return 1
  jq -e '.hooks.SessionStart | length > 0' "$out" > /dev/null || return 1
  jq -e '.hooks.Stop | length > 0' "$out" > /dev/null || return 1
  return 0
}

# T5: permissions 회귀 — 기존 allow/deny 보존 + repo union
t5_perms() {
  local TMP; TMP=$(mktemp -d); trap "rm -rf $TMP" RETURN
  local cur="$TMP/cur.json" out="$TMP/merged.json"
  printf '%s' '{
    "permissions": {
      "allow": ["Bash(custom-cmd*)"],
      "deny":  ["Bash(custom-deny*)"]
    }
  }' > "$cur"
  do_merge "$cur" "$NEW_SETTINGS" "$out" || return 1
  jq -e '.permissions.allow | index("Bash(custom-cmd*)") | . != null' "$out" > /dev/null || return 1
  jq -e '.permissions.deny  | index("Bash(custom-deny*)") | . != null' "$out" > /dev/null || return 1
  return 0
}

# T6: 다른 top-level 키 보존 — model 키 유지
t6_other_top() {
  local TMP; TMP=$(mktemp -d); trap "rm -rf $TMP" RETURN
  local cur="$TMP/cur.json" out="$TMP/merged.json"
  printf '%s' '{"model": "opus", "hooks": {}}' > "$cur"
  do_merge "$cur" "$NEW_SETTINGS" "$out" || return 1
  jq -e '.model == "opus"' "$out" > /dev/null || return 1
  return 0
}

run "T1 union write|edit" t1_union_writeedit
run "T2 idempotent" t2_idempotent
run "T3 matcher 격리" t3_matcher_isolation
run "T4 새 event 추가" t4_new_event
run "T5 permissions 회귀" t5_perms
run "T6 다른 top-level 키 보존" t6_other_top

# T7: hook 파일명 dedup — 기존 plain hook + repo command 시, repo 가 winner (1라인만).
t7_hook_filename_dedup() {
  local TMP; TMP=$(mktemp -d); trap "rm -rf $TMP" RETURN
  local cur="$TMP/cur.json" out="$TMP/merged.json"
  printf '%s' '{
    "hooks": {
      "PreToolUse": [
        { "matcher": "Write|Edit",
          "hooks": [{"type":"command","command":"$HOME/.claude/hooks/track-cmux-edit-burst.sh --old-flag"}] }
      ]
    }
  }' > "$cur"
  do_merge "$cur" "$NEW_SETTINGS" "$out" || return 1
  local count
  count=$(jq '[.hooks.PreToolUse[] | select(.matcher == "Write|Edit") | .hooks[] | select(.command | test("track-cmux-edit-burst\\.sh"))] | length' "$out")
  [ "$count" -eq 1 ] || return 1
  jq -e '.hooks.PreToolUse[] | select(.matcher == "Write|Edit") | .hooks[] | select(.command | test("track-cmux-edit-burst\\.sh")) | .command | (contains("--old-flag") | not)' \
    "$out" >/dev/null || return 1
  return 0
}

# T8: 비-hook custom 명령 보존 — hooks/ 경로 아닌 사용자 custom 은 그대로
t8_custom_non_hook_preserved() {
  local TMP; TMP=$(mktemp -d); trap "rm -rf $TMP" RETURN
  local cur="$TMP/cur.json" out="$TMP/merged.json"
  printf '%s' '{
    "hooks": {
      "PreToolUse": [
        { "matcher": "Write|Edit",
          "hooks": [{"type":"command","command":"my-custom-bash-script.sh"}] }
      ]
    }
  }' > "$cur"
  do_merge "$cur" "$NEW_SETTINGS" "$out" || return 1
  jq -e '[.hooks.PreToolUse[] | select(.matcher == "Write|Edit") | .hooks[] | .command] | index("my-custom-bash-script.sh") | . != null' \
    "$out" >/dev/null || return 1
  return 0
}

run "T7 hook 파일명 dedup (repo winner)" t7_hook_filename_dedup
run "T8 비-hook custom 명령 보존" t8_custom_non_hook_preserved

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && echo "✅ all pass" || { echo "❌ FAILED: ${FAILED[*]}"; exit 1; }
