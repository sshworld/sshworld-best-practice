#!/usr/bin/env bash
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0; FAILED=()
run() { local name="$1"; shift; if "$@" >/dev/null 2>&1; then echo "✔ $name"; PASS=$((PASS+1)); else echo "✘ $name"; FAIL=$((FAIL+1)); FAILED+=("$name"); fi; }

t_settings_no_inline_strict() {
  # settings.json hook command 에 CMUX_EDIT_BURST_STRICT=1 inline 없음
  ! grep -F 'CMUX_EDIT_BURST_STRICT=1' "$REPO/.claude/settings.json"
}

t_hook_threshold_default_50() {
  grep -F 'CMUX_EDIT_BURST_THRESHOLD:-50' "$REPO/.claude/hooks/track-cmux-edit-burst.sh" >/dev/null
}

t_skip_advisory_message() {
  grep -F "의식적으로 검토" "$REPO/.claude/hooks/track-cmux-edit-burst.sh" >/dev/null
}

t_hook_skips_in_child_worktree() {
  local tmp=$(mktemp -d)
  local fake_repo=$tmp/repo
  mkdir -p $fake_repo
  git -C $fake_repo init -q
  git -C $fake_repo commit --allow-empty -q -m init 2>/dev/null
  git -C $fake_repo worktree add -q $tmp/child 2>/dev/null
  local before_count=0
  local count_file=$tmp/burst.count
  echo $before_count > $count_file
  local payload='{"tool_name":"Edit"}'
  CMUX_WORKSPACE_ID=test-ws \
  CBP_BURST_FILE=$count_file \
  CMUX_EDIT_BURST_STRICT=1 \
    bash -c "cd $tmp/child && printf '%s' '$payload' | $REPO/.claude/hooks/track-cmux-edit-burst.sh"
  local exit_code=$?
  local after_count=$(cat $count_file)
  rm -rf $tmp
  [ "$exit_code" = "0" ] && [ "$after_count" = "0" ]
}

t_hook_pass_under_threshold() {
  local tmp=$(mktemp -d)
  local fake_repo=$tmp/repo
  mkdir -p $fake_repo
  git -C $fake_repo init -q
  git -C $fake_repo commit --allow-empty -q -m init 2>/dev/null
  local count_file=$tmp/burst.count
  echo 30 > $count_file
  local payload='{"tool_name":"Edit"}'
  CMUX_WORKSPACE_ID=test-ws \
  CBP_BURST_FILE=$count_file \
    bash -c "cd $fake_repo && printf '%s' '$payload' | $REPO/.claude/hooks/track-cmux-edit-burst.sh" 2>/dev/null
  local exit_code=$?
  local after_count=$(cat $count_file)
  rm -rf $tmp
  # 4회: 임계치 5 미만 → 메시지 없이 exit 0
  [ "$exit_code" = "0" ] && [ "$after_count" = "31" ]
}

t_hook_advisory_only_default() {
  local tmp=$(mktemp -d)
  local fake_repo=$tmp/repo
  mkdir -p $fake_repo
  git -C $fake_repo init -q
  git -C $fake_repo commit --allow-empty -q -m init 2>/dev/null
  local count_file=$tmp/burst.count
  echo 50 > $count_file  # 이미 5
  local payload='{"tool_name":"Edit"}'
  CMUX_WORKSPACE_ID=test-ws \
  CBP_BURST_FILE=$count_file \
    bash -c "cd $fake_repo && printf '%s' '$payload' | $REPO/.claude/hooks/track-cmux-edit-burst.sh" 2>/dev/null
  local exit_code=$?
  local after_count=$(cat $count_file)
  rm -rf $tmp
  # 6회째: advisory (stderr) + exit 0 (차단 아님)
  [ "$exit_code" = "0" ] && [ "$after_count" = "51" ]
}

t_hook_strict_env_still_blocks() {
  local tmp=$(mktemp -d)
  local fake_repo=$tmp/repo
  mkdir -p $fake_repo
  git -C $fake_repo init -q
  git -C $fake_repo commit --allow-empty -q -m init 2>/dev/null
  local count_file=$tmp/burst.count
  echo 50 > $count_file
  local payload='{"tool_name":"Edit"}'
  CMUX_WORKSPACE_ID=test-ws \
  CBP_BURST_FILE=$count_file \
  CMUX_EDIT_BURST_STRICT=1 \
    bash -c "cd $fake_repo && printf '%s' '$payload' | $REPO/.claude/hooks/track-cmux-edit-burst.sh" 2>/dev/null
  local exit_code=$?
  rm -rf $tmp
  # strict env 명시 → exit 2
  [ "$exit_code" = "2" ]
}

run "settings.json inline strict 부재" t_settings_no_inline_strict
run "hook 디폴트 임계치 50" t_hook_threshold_default_50
run "SKIP 메시지 권고 보존" t_skip_advisory_message
run "자식 worktree skip" t_hook_skips_in_child_worktree
run "임계치 미만 silently pass" t_hook_pass_under_threshold
run "임계치 초과 advisory only (차단 없음)" t_hook_advisory_only_default
run "STRICT env 명시 시 차단 보존" t_hook_strict_env_still_blocks

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && echo "✅ all pass" || { echo "❌ FAILED: ${FAILED[*]}"; exit 1; }
