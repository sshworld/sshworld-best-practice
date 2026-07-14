#!/usr/bin/env bash
# Tests for hooks/record-commit-advised.sh

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$REPO/hooks/record-commit-advised.sh"

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

git_init_main() {
  local dir="$1"
  git -c init.defaultBranch=main init "$dir" -q 2>/dev/null \
    || git init "$dir" -q
  if [ "$(git -C "$dir" symbolic-ref --short HEAD 2>/dev/null)" != "main" ]; then
    git -C "$dir" checkout -b main -q 2>/dev/null || true
  fi
}

setup_tmp_repo() {
  local tmp
  tmp=$(mktemp -d)
  local repo="$tmp/repo"
  mkdir -p "$repo"
  git_init_main "$repo"
  git -C "$repo" config user.email "test@example.com"
  git -C "$repo" config user.name "Test"
  git -C "$repo" -c commit.gpgsign=false commit --allow-empty -q -m "init"
  echo "$repo"
}

MARKER_NAME="plan-dev-commit-advised"

# T1: Task + sshworld:commit-advisor → marker 생성, exit 0
t1_task_plugin_namespaced() {
  local repo rc=0
  repo=$(setup_tmp_repo)
  local out
  out=$(cd "$repo" && printf '%s' '{"tool_name":"Task","tool_input":{"subagent_type":"sshworld:commit-advisor","description":"..."}}' | "$HOOK" 2>&1) || rc=$?
  [ "$rc" -eq 0 ] && [ -f "$repo/.git/$MARKER_NAME" ]
}

# T2: Agent + commit-advisor (no namespace) → marker 생성
t2_agent_bare_name() {
  local repo rc=0
  repo=$(setup_tmp_repo)
  local out
  out=$(cd "$repo" && printf '%s' '{"tool_name":"Agent","tool_input":{"subagent_type":"commit-advisor"}}' | "$HOOK" 2>&1) || rc=$?
  [ "$rc" -eq 0 ] && [ -f "$repo/.git/$MARKER_NAME" ]
}

# T3: Task + sshworld:implementor → 미생성, exit 0
t3_non_commit_advisor_no_marker() {
  local repo rc=0
  repo=$(setup_tmp_repo)
  local out
  out=$(cd "$repo" && printf '%s' '{"tool_name":"Task","tool_input":{"subagent_type":"sshworld:implementor"}}' | "$HOOK" 2>&1) || rc=$?
  [ "$rc" -eq 0 ] && [ ! -f "$repo/.git/$MARKER_NAME" ]
}

# T4: 비-git cwd → 조용히 exit 0 (stderr 출력 없음)
t4_non_git_cwd_silent() {
  local tmp rc=0
  tmp=$(mktemp -d)
  local out err
  out=$(cd "$tmp" && printf '%s' '{"tool_name":"Task","tool_input":{"subagent_type":"sshworld:commit-advisor"}}' | "$HOOK" 2>/tmp/record_commit_advised_t4_err.$$) || rc=$?
  err=$(cat "/tmp/record_commit_advised_t4_err.$$" 2>/dev/null)
  rm -f "/tmp/record_commit_advised_t4_err.$$"
  [ "$rc" -eq 0 ] && [ -z "$err" ]
}

# T5: 빈 stdin / 깨진 JSON → exit 0
t5_empty_and_broken_json() {
  local repo rc=0 rc2=0
  repo=$(setup_tmp_repo)
  (cd "$repo" && printf '' | "$HOOK" >/dev/null 2>&1) || rc=$?
  (cd "$repo" && printf '%s' '{not valid json' | "$HOOK" >/dev/null 2>&1) || rc2=$?
  [ "$rc" -eq 0 ] && [ "$rc2" -eq 0 ]
}

run "T1 Task sshworld:commit-advisor -> marker"   t1_task_plugin_namespaced
run "T2 Agent commit-advisor -> marker"           t2_agent_bare_name
run "T3 Task sshworld:implementor -> no marker"   t3_non_commit_advisor_no_marker
run "T4 non-git cwd -> silent exit 0"              t4_non_git_cwd_silent
run "T5 empty/broken json -> exit 0"               t5_empty_and_broken_json

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && echo "✅ all pass" || { echo "❌ FAILED: ${FAILED[*]}"; exit 1; }
