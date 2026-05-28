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


t_hook_skips_in_child_worktree() {
  # tmp 디렉토리에 fake worktree 구조 만들고 hook 가 거기서 skip 하는지 확인
  local tmp=$(mktemp -d)
  local fake_repo=$tmp/repo
  mkdir -p $fake_repo
  git -C $fake_repo init -q
  git -C $fake_repo commit --allow-empty -q -m init 2>/dev/null
  git -C $fake_repo worktree add -q $tmp/child 2>/dev/null
  # hook 호출 - 자식 worktree 안에서
  local before_count=0
  local count_file=$tmp/burst.count
  echo $before_count > $count_file
  # PAYLOAD = Edit tool
  local payload='{"tool_name":"Edit"}'
  CMUX_WORKSPACE_ID=test-ws \
  CBP_BURST_FILE=$count_file \
  CMUX_EDIT_BURST_STRICT=1 \
    bash -c "cd $tmp/child && printf '%s' '$payload' | $REPO/.claude/hooks/track-cmux-edit-burst.sh"
  local exit_code=$?
  local after_count=$(cat $count_file)
  rm -rf $tmp
  # exit 0 + counter 증가 안 됨
  [ "$exit_code" = "0" ] && [ "$after_count" = "0" ]
}

t_hook_active_in_main_worktree() {
  # 부모 main worktree (git-dir == git-common-dir) 에서 hook 정상 작동
  local tmp=$(mktemp -d)
  local fake_repo=$tmp/repo
  mkdir -p $fake_repo
  git -C $fake_repo init -q
  git -C $fake_repo commit --allow-empty -q -m init 2>/dev/null
  local count_file=$tmp/burst.count
  echo 1 > $count_file  # 이미 1
  local payload='{"tool_name":"Edit"}'
  CMUX_WORKSPACE_ID=test-ws \
  CBP_BURST_FILE=$count_file \
  CMUX_EDIT_BURST_STRICT=1 \
    bash -c "cd $fake_repo && printf '%s' '$payload' | $REPO/.claude/hooks/track-cmux-edit-burst.sh" 2>/dev/null
  local exit_code=$?
  local after_count=$(cat $count_file)
  rm -rf $tmp
  # 부모: counter 증가 후 임계치 2 도달 → strict 차단 (exit 2)
  [ "$exit_code" = "2" ] && [ "$after_count" = "2" ]
}

run "자식 worktree 안에서 hook skip (exit 0 + counter 증가 안 함)" t_hook_skips_in_child_worktree
run "부모 main worktree 에서 hook 정상 작동 (회귀 없음)" t_hook_active_in_main_worktree

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && echo "✅ all pass" || { echo "❌ FAILED: ${FAILED[*]}"; exit 1; }
