#!/usr/bin/env bash
# Tests for hooks/notify-slice-done.sh

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$REPO/hooks/notify-slice-done.sh"

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

# 임시 부모 repo + .worktrees/test-slice 자식 worktree 셋업.
# 반환: "parent_path|worktree_path"
setup_repo_with_worktree() {
  local tmp parent wt
  tmp=$(mktemp -d)
  parent="$tmp/parent"
  mkdir -p "$parent"
  git_init_main "$parent"
  git -C "$parent" config user.email "test@example.com"
  git -C "$parent" config user.name "Test"
  git -C "$parent" -c commit.gpgsign=false commit --allow-empty -q -m "init"
  wt="$parent/.worktrees/test-slice"
  git -C "$parent" worktree add -q "$wt" -b feature/test-slice >/dev/null 2>&1
  echo "$parent|$wt"
}

# mock cmux — 호출 인자를 "<dir>/cmux.calls" 에 기록
make_mock_cmux() {
  local dir="$1"
  local bin="$dir/cmux"
  local calls="$dir/cmux.calls"
  {
    echo '#!/usr/bin/env bash'
    echo "echo \"\$@\" >> '$calls'"
    echo 'exit 0'
  } > "$bin"
  chmod +x "$bin"
  echo "$bin"
}

common_dir_of() {
  local repo="$1"
  (cd "$repo" && git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
}

marker_path_of() {
  local repo="$1" branch_sanitized="$2"
  echo "$(common_dir_of "$repo")/cbp-slice-done-${branch_sanitized}"
}

# T1: 자식 worktree + CMUX_WORKSPACE_ID/CMUX_SURFACE_ID set + ✅ transcript
#     → notify 호출에 ✅ title + marker 생성 + 내용 == CMUX_SURFACE_ID
t1_success_verdict() {
  local pair parent wt tmpdir transcript json_file cmux_bin rc=0
  pair=$(setup_repo_with_worktree)
  parent="${pair%|*}"; wt="${pair#*|}"
  tmpdir=$(mktemp -d)
  cmux_bin=$(make_mock_cmux "$tmpdir")
  transcript="$tmpdir/transcript.jsonl"
  {
    echo '{"type":"user","message":{"content":[{"type":"text","text":"do something"}]}}'
    echo '{"type":"assistant","message":{"content":[{"type":"text","text":"작업 끝. ✅ test-slice"}]}}'
  } > "$transcript"
  json_file="$tmpdir/stdin.json"
  printf '{"transcript_path":"%s"}\n' "$transcript" > "$json_file"

  (cd "$wt" && CMUX_BIN="$cmux_bin" CMUX_WORKSPACE_ID="ws1" CMUX_SURFACE_ID="surf1" \
    "$HOOK" < "$json_file" >/dev/null 2>&1)
  rc=$?

  local marker
  marker=$(marker_path_of "$parent" "feature_test-slice")

  [ "$rc" -eq 0 ] \
    && grep -q '✅' "$tmpdir/cmux.calls" 2>/dev/null \
    && [ -f "$marker" ] \
    && [ "$(cat "$marker")" = "surf1" ]
}

# T2: ❌ transcript → ❌ title + marker 생성
t2_failure_verdict() {
  local pair parent wt tmpdir transcript json_file cmux_bin rc=0
  pair=$(setup_repo_with_worktree)
  parent="${pair%|*}"; wt="${pair#*|}"
  tmpdir=$(mktemp -d)
  cmux_bin=$(make_mock_cmux "$tmpdir")
  transcript="$tmpdir/transcript.jsonl"
  {
    echo '{"type":"user","message":{"content":[{"type":"text","text":"do something"}]}}'
    echo '{"type":"assistant","message":{"content":[{"type":"text","text":"실패함. ❌ test-slice 이유"}]}}'
  } > "$transcript"
  json_file="$tmpdir/stdin.json"
  printf '{"transcript_path":"%s"}\n' "$transcript" > "$json_file"

  (cd "$wt" && CMUX_BIN="$cmux_bin" CMUX_WORKSPACE_ID="ws1" CMUX_SURFACE_ID="surf1" \
    "$HOOK" < "$json_file" >/dev/null 2>&1)
  rc=$?

  local marker
  marker=$(marker_path_of "$parent" "feature_test-slice")

  [ "$rc" -eq 0 ] \
    && grep -q '❌' "$tmpdir/cmux.calls" 2>/dev/null \
    && [ -f "$marker" ]
}

# T3: user 줄에만 ✅ (assistant 텍스트엔 없음) → 🔔 title + marker 미생성
t3_user_line_echo_ignored() {
  local pair parent wt tmpdir transcript json_file cmux_bin rc=0
  pair=$(setup_repo_with_worktree)
  parent="${pair%|*}"; wt="${pair#*|}"
  tmpdir=$(mktemp -d)
  cmux_bin=$(make_mock_cmux "$tmpdir")
  transcript="$tmpdir/transcript.jsonl"
  {
    echo '{"type":"user","message":{"content":[{"type":"text","text":"질문: ✅ 이게 맞아?"}]}}'
    echo '{"type":"assistant","message":{"content":[{"type":"text","text":"아직 작업 중입니다"}]}}'
  } > "$transcript"
  json_file="$tmpdir/stdin.json"
  printf '{"transcript_path":"%s"}\n' "$transcript" > "$json_file"

  (cd "$wt" && CMUX_BIN="$cmux_bin" CMUX_WORKSPACE_ID="ws1" CMUX_SURFACE_ID="surf1" \
    "$HOOK" < "$json_file" >/dev/null 2>&1)
  rc=$?

  local marker
  marker=$(marker_path_of "$parent" "feature_test-slice")

  [ "$rc" -eq 0 ] \
    && grep -q '🔔' "$tmpdir/cmux.calls" 2>/dev/null \
    && [ ! -f "$marker" ]
}

# T4: 부모 repo cwd (비-worktree) → 무동작
t4_parent_repo_noop() {
  local pair parent wt tmpdir transcript json_file cmux_bin rc=0
  pair=$(setup_repo_with_worktree)
  parent="${pair%|*}"; wt="${pair#*|}"
  tmpdir=$(mktemp -d)
  cmux_bin=$(make_mock_cmux "$tmpdir")
  transcript="$tmpdir/transcript.jsonl"
  echo '{"type":"assistant","message":{"content":[{"type":"text","text":"✅ done"}]}}' > "$transcript"
  json_file="$tmpdir/stdin.json"
  printf '{"transcript_path":"%s"}\n' "$transcript" > "$json_file"

  (cd "$parent" && CMUX_BIN="$cmux_bin" CMUX_WORKSPACE_ID="ws1" CMUX_SURFACE_ID="surf1" \
    "$HOOK" < "$json_file" >/dev/null 2>&1)
  rc=$?

  [ "$rc" -eq 0 ] && [ ! -f "$tmpdir/cmux.calls" ]
}

# T5: CMUX_WORKSPACE_ID unset → 무동작
t5_no_cmux_workspace_noop() {
  local pair parent wt tmpdir transcript json_file cmux_bin rc=0
  pair=$(setup_repo_with_worktree)
  parent="${pair%|*}"; wt="${pair#*|}"
  tmpdir=$(mktemp -d)
  cmux_bin=$(make_mock_cmux "$tmpdir")
  transcript="$tmpdir/transcript.jsonl"
  echo '{"type":"assistant","message":{"content":[{"type":"text","text":"✅ done"}]}}' > "$transcript"
  json_file="$tmpdir/stdin.json"
  printf '{"transcript_path":"%s"}\n' "$transcript" > "$json_file"

  (cd "$wt" && unset CMUX_WORKSPACE_ID; CMUX_BIN="$cmux_bin" CMUX_SURFACE_ID="surf1" \
    "$HOOK" < "$json_file" >/dev/null 2>&1)
  rc=$?

  [ "$rc" -eq 0 ] && [ ! -f "$tmpdir/cmux.calls" ]
}

# T6: DISABLE_SLICE_DONE_NOTIFY=1 → 무동작
t6_disabled_noop() {
  local pair parent wt tmpdir transcript json_file cmux_bin rc=0
  pair=$(setup_repo_with_worktree)
  parent="${pair%|*}"; wt="${pair#*|}"
  tmpdir=$(mktemp -d)
  cmux_bin=$(make_mock_cmux "$tmpdir")
  transcript="$tmpdir/transcript.jsonl"
  echo '{"type":"assistant","message":{"content":[{"type":"text","text":"✅ done"}]}}' > "$transcript"
  json_file="$tmpdir/stdin.json"
  printf '{"transcript_path":"%s"}\n' "$transcript" > "$json_file"

  (cd "$wt" && CMUX_BIN="$cmux_bin" CMUX_WORKSPACE_ID="ws1" CMUX_SURFACE_ID="surf1" \
    DISABLE_SLICE_DONE_NOTIFY=1 "$HOOK" < "$json_file" >/dev/null 2>&1)
  rc=$?

  [ "$rc" -eq 0 ] && [ ! -f "$tmpdir/cmux.calls" ]
}

# T7: .worktrees/ 밖 worktree → 무동작. CBP_NOTIFY_ANY_WORKTREE=1 이면 동작.
t7_outside_worktrees_dir() {
  local pair parent wt tmp other_wt tmpdir transcript json_file cmux_bin rc=0
  pair=$(setup_repo_with_worktree)
  parent="${pair%|*}"; wt="${pair#*|}"
  tmp=$(dirname "$parent")
  other_wt="$tmp/other-wt"
  git -C "$parent" worktree add -q "$other_wt" -b feature/other-wt >/dev/null 2>&1

  tmpdir=$(mktemp -d)
  cmux_bin=$(make_mock_cmux "$tmpdir")
  transcript="$tmpdir/transcript.jsonl"
  {
    echo '{"type":"user","message":{"content":[{"type":"text","text":"do"}]}}'
    echo '{"type":"assistant","message":{"content":[{"type":"text","text":"✅ done"}]}}'
  } > "$transcript"
  json_file="$tmpdir/stdin.json"
  printf '{"transcript_path":"%s"}\n' "$transcript" > "$json_file"

  (cd "$other_wt" && CMUX_BIN="$cmux_bin" CMUX_WORKSPACE_ID="ws1" CMUX_SURFACE_ID="surf1" \
    "$HOOK" < "$json_file" >/dev/null 2>&1)
  rc=$?
  local no_escape_ok=1
  [ "$rc" -eq 0 ] && [ ! -f "$tmpdir/cmux.calls" ] || no_escape_ok=0

  (cd "$other_wt" && CMUX_BIN="$cmux_bin" CMUX_WORKSPACE_ID="ws1" CMUX_SURFACE_ID="surf1" \
    CBP_NOTIFY_ANY_WORKTREE=1 "$HOOK" < "$json_file" >/dev/null 2>&1)
  rc=$?
  local escape_ok=1
  [ "$rc" -eq 0 ] && grep -q '✅' "$tmpdir/cmux.calls" 2>/dev/null || escape_ok=0

  [ "$no_escape_ok" -eq 1 ] && [ "$escape_ok" -eq 1 ]
}

# T8: jq 부재 (PATH 에서 제거한 서브셸) → 🔔 강등 + marker 미생성
t8_jq_missing_degrades() {
  local pair parent wt tmpdir transcript json_file cmux_bin fakebin rc=0
  pair=$(setup_repo_with_worktree)
  parent="${pair%|*}"; wt="${pair#*|}"
  tmpdir=$(mktemp -d)
  cmux_bin=$(make_mock_cmux "$tmpdir")
  transcript="$tmpdir/transcript.jsonl"
  {
    echo '{"type":"user","message":{"content":[{"type":"text","text":"do"}]}}'
    echo '{"type":"assistant","message":{"content":[{"type":"text","text":"완료 ✅ test-slice"}]}}'
  } > "$transcript"
  json_file="$tmpdir/stdin.json"
  printf '{"transcript_path":"%s"}\n' "$transcript" > "$json_file"

  fakebin=$(mktemp -d)
  local cmd p
  for cmd in git grep tr cut tail cat bash; do
    p=$(command -v "$cmd" 2>/dev/null) && ln -sf "$p" "$fakebin/$cmd"
  done

  (cd "$wt" && PATH="$fakebin" CMUX_BIN="$cmux_bin" CMUX_WORKSPACE_ID="ws1" CMUX_SURFACE_ID="surf1" \
    bash "$HOOK" < "$json_file" >/dev/null 2>&1)
  rc=$?

  local marker
  marker=$(marker_path_of "$parent" "feature_test-slice")

  [ "$rc" -eq 0 ] \
    && grep -q '🔔' "$tmpdir/cmux.calls" 2>/dev/null \
    && [ ! -f "$marker" ]
}

# T9: hooks.json / .claude/settings.json 배선 검증
t9_wiring_hooks_json() {
  python3 -c "
import json
d = json.load(open('$REPO/hooks/hooks.json'))
cmds = [h['command'] for blk in d['hooks']['Stop'] for h in blk['hooks']]
assert any('notify-slice-done.sh' in c for c in cmds), cmds
"
}

t10_wiring_settings_json() {
  python3 -c "
import json
d = json.load(open('$REPO/.claude/settings.json'))
cmds = [h['command'] for blk in d['hooks']['Stop'] for h in blk['hooks']]
assert any('notify-slice-done.sh' in c for c in cmds), cmds
"
}

run "T1 child worktree + success verdict -> notify+marker"  t1_success_verdict
run "T2 failure verdict -> notify+marker"                   t2_failure_verdict
run "T3 user-line echo ignored -> bell, no marker"          t3_user_line_echo_ignored
run "T4 parent repo cwd -> noop"                            t4_parent_repo_noop
run "T5 CMUX_WORKSPACE_ID unset -> noop"                    t5_no_cmux_workspace_noop
run "T6 DISABLE_SLICE_DONE_NOTIFY=1 -> noop"                 t6_disabled_noop
run "T7 outside .worktrees/ -> noop, escape works"           t7_outside_worktrees_dir
run "T8 jq missing -> bell degrade, no marker"               t8_jq_missing_degrades
run "T9 hooks.json wiring"                                   t9_wiring_hooks_json
run "T10 settings.json wiring"                               t10_wiring_settings_json

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && echo "✅ all pass" || { echo "❌ FAILED: ${FAILED[*]}"; exit 1; }
