#!/usr/bin/env bash
# merge-settings.sh 단위 테스트.
# settings.json 병합 — hooks event/matcher union + dedup (doubling 버그 회귀 가드).
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MERGE="$REPO/scripts/merge-settings.sh"
PASS=0; FAIL=0; FAILED=()
run() { local name="$1"; shift; if "$@" >/dev/null 2>&1; then echo "✔ $name"; PASS=$((PASS+1)); else echo "✘ $name"; FAIL=$((FAIL+1)); FAILED+=("$name"); fi; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
I=0
do_merge() { # $1=cur json $2=new json → stdout merged path
  I=$((I+1))
  local c="$TMP/cur.$I.json" n="$TMP/new.$I.json" o="$TMP/out.$I.json"
  printf '%s' "$1" > "$c"; printf '%s' "$2" > "$n"
  bash "$MERGE" "$c" "$n" > "$o" 2>/dev/null || return 1
  echo "$o"
}

t_doubling_regression() {
  local cur new out
  cur='{"hooks":{"SessionStart":[
    {"matcher":"","hooks":[{"type":"command","command":"node caveman.js"}]},
    {"matcher":"","hooks":[{"type":"command","command":"node caveman.js"}]}
  ]}}'
  new='{"hooks":{"SessionStart":[{"matcher":"","hooks":[{"type":"command","command":"INLINE"}]}]}}'
  out=$(do_merge "$cur" "$new") || return 1
  local cav grp
  cav=$(jq '[.hooks.SessionStart[].hooks[].command]|map(select(test("caveman")))|length' "$out")
  grp=$(jq '.hooks.SessionStart|length' "$out")
  [ "$cav" = "1" ] && [ "$grp" = "1" ]
}

t_idempotency() {
  local cur new out out2
  cur='{"hooks":{"SessionStart":[
    {"matcher":"","hooks":[{"type":"command","command":"node caveman.js"}]},
    {"matcher":"","hooks":[{"type":"command","command":"node caveman.js"}]}
  ]}}'
  new='{"hooks":{"SessionStart":[{"matcher":"","hooks":[{"type":"command","command":"INLINE"}]}]}}'
  out=$(do_merge "$cur" "$new") || return 1
  printf '%s' "$new" > "$TMP/n_idem.json"
  bash "$MERGE" "$out" "$TMP/n_idem.json" > "$TMP/o2.json" 2>/dev/null || return 1
  local cav grp
  cav=$(jq '[.hooks.SessionStart[].hooks[].command]|map(select(test("caveman")))|length' "$TMP/o2.json")
  grp=$(jq '.hooks.SessionStart|length' "$TMP/o2.json")
  [ "$cav" = "1" ] && [ "$grp" = "1" ]
}

t_cur_internal_dup_collapse() {
  local cur new out
  cur='{"hooks":{"SessionStart":[{"matcher":"","hooks":[
    {"type":"command","command":"node caveman.js"},
    {"type":"command","command":"node caveman.js"},
    {"type":"command","command":"node caveman.js"}
  ]}]}}'
  new='{"hooks":{}}'
  out=$(do_merge "$cur" "$new") || return 1
  local cav; cav=$(jq '[.hooks.SessionStart[].hooks[].command]|map(select(test("caveman")))|length' "$out")
  [ "$cav" = "1" ]
}

t_new_hook_added() {
  local cur new out
  cur='{"hooks":{"PreToolUse":[{"matcher":"Write|Edit","hooks":[{"type":"command","command":"$X/hooks/enforce-test-first.sh"}]}]}}'
  new='{"hooks":{"PreToolUse":[{"matcher":"Write|Edit","hooks":[
    {"type":"command","command":"$X/hooks/enforce-test-first.sh"},
    {"type":"command","command":"$X/hooks/enforce-plan-mode.sh"}
  ]}]}}'
  out=$(do_merge "$cur" "$new") || return 1
  local n; n=$(jq '[.hooks.PreToolUse[].hooks[].command]|map(select(test("enforce-plan-mode")))|length' "$out")
  [ "$n" = "1" ]
}

t_multi_matcher_preserved() {
  local cur new out
  cur='{"hooks":{"PreToolUse":[
    {"matcher":"Write|Edit","hooks":[{"type":"command","command":"a/hooks/x.sh"}]},
    {"matcher":"Bash","hooks":[{"type":"command","command":"a/hooks/y.sh"}]}
  ]}}'
  new='{"hooks":{"PreToolUse":[{"matcher":"Write|Edit","hooks":[{"type":"command","command":"b/hooks/z.sh"}]}]}}'
  out=$(do_merge "$cur" "$new") || return 1
  local grp we_cnt
  grp=$(jq '.hooks.PreToolUse|length' "$out")
  we_cnt=$(jq '[.hooks.PreToolUse[]|select(.matcher=="Write|Edit").hooks[]]|length' "$out")
  [ "$grp" = "2" ] && [ "$we_cnt" = "2" ]
}

t_allow_deny_union_unique() {
  local cur new out
  cur='{"permissions":{"allow":["A","B"],"deny":["X"]}}'
  new='{"permissions":{"allow":["B","C"],"deny":["X","Y"]}}'
  out=$(do_merge "$cur" "$new") || return 1
  local a d
  a=$(jq -c '.permissions.allow|sort' "$out")
  d=$(jq -c '.permissions.deny|sort' "$out")
  [ "$a" = '["A","B","C"]' ] && [ "$d" = '["X","Y"]' ]
}

t_nonhooks_toplevel_cur_wins() {
  local cur new out
  cur='{"model":"opus","foo":1}'
  new='{"model":"sonnet","bar":2}'
  out=$(do_merge "$cur" "$new") || return 1
  local m; m=$(jq -r '.model' "$out")
  [ "$m" = "opus" ]
}

run "doubling 회귀 (cur 2그룹 → caveman 1/group 1)" t_doubling_regression
run "idempotency (재merge 후도 1)"                  t_idempotency
run "cur 내부 중복 collapse (3→1)"                  t_cur_internal_dup_collapse
run "new 신규 hook 추가 (1개)"                       t_new_hook_added
run "multi-matcher 보존 (2그룹)"                     t_multi_matcher_preserved
run "allow/deny union unique"                        t_allow_deny_union_unique
run "비-hooks top-level 기존 우선"                   t_nonhooks_toplevel_cur_wins

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && echo "✅ all pass" || { echo "❌ FAILED: ${FAILED[*]}"; exit 1; }
