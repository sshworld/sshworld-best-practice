#!/usr/bin/env bash
# enforce-doc-sync.sh hook 단위 테스트.
# PreToolUse Bash — git commit 시 DOC_IMPACT 판단 강제. R6: command 에 SKIP_DOC_SYNC=1
# 포함 시 1회 통과 (README 가 광고하지만 미구현이었던 우회).
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="$REPO/hooks/enforce-doc-sync.sh"
PASS=0; FAIL=0; FAILED=()
run() { local name="$1"; shift; if "$@" >/dev/null 2>&1; then echo "✔ $name"; PASS=$((PASS+1)); else echo "✘ $name"; FAIL=$((FAIL+1)); FAILED+=("$name"); fi; }

mk_repo_with_staged() {
  local tmp; tmp=$(mktemp -d)
  git -C "$tmp" init -q
  git -C "$tmp" config user.email "t@e.local"
  git -C "$tmp" config user.name "tester"
  git -C "$tmp" commit --allow-empty -q -m init
  echo "x" > "$tmp/file.txt"
  git -C "$tmp" add file.txt
  echo "$tmp"
}

make_payload() {
  local cmd="$1"
  python3 -c "import json,sys; print(json.dumps({'tool_name':'Bash','tool_input':{'command': sys.argv[1]}}))" "$cmd"
}

# SKIP_DOC_SYNC=1 이 command 문자열에 포함 → 1회 통과 (DOC_IMPACT 미지정이어도)
t_skip_doc_sync_command_allows() {
  local repo; repo=$(mk_repo_with_staged)
  local p; p=$(make_payload 'SKIP_DOC_SYNC=1 git commit -m "wip"')
  local ec=0
  ( cd "$repo" && echo "$p" | bash "$HOOK" ) || ec=$?
  rm -rf "$repo"; [ "$ec" = "0" ]
}

# SKIP_DOC_SYNC=1 미포함 + DOC_IMPACT 미지정 → 기존 동작(차단, exit 2)
t_no_skip_no_doc_impact_blocks() {
  local repo; repo=$(mk_repo_with_staged)
  local p; p=$(make_payload 'git commit -m "wip"')
  local ec=0
  ( cd "$repo" && echo "$p" | bash "$HOOK" ) || ec=$?
  rm -rf "$repo"; [ "$ec" = "2" ]
}

# DOC_IMPACT=none (SKIP_DOC_SYNC 없이) → 기존 동작 유지(allow)
t_doc_impact_none_allows() {
  local repo; repo=$(mk_repo_with_staged)
  local p; p=$(make_payload 'DOC_IMPACT=none git commit -m "wip"')
  local ec=0
  ( cd "$repo" && echo "$p" | bash "$HOOK" ) || ec=$?
  rm -rf "$repo"; [ "$ec" = "0" ]
}

# 비-git commit 명령(SKIP_DOC_SYNC 포함이어도 무관) → exit 0 (매처 미일치)
t_non_commit_command_allows() {
  local repo; repo=$(mk_repo_with_staged)
  local p; p=$(make_payload 'SKIP_DOC_SYNC=1 git status')
  local ec=0
  ( cd "$repo" && echo "$p" | bash "$HOOK" ) || ec=$?
  rm -rf "$repo"; [ "$ec" = "0" ]
}

run "SKIP_DOC_SYNC=1 포함 → allow(0)"                    t_skip_doc_sync_command_allows
run "미포함 + DOC_IMPACT 미지정 → block(2) (기존 동작)"  t_no_skip_no_doc_impact_blocks
run "DOC_IMPACT=none → allow(0) (기존 동작 유지)"         t_doc_impact_none_allows
run "git commit 아님 → allow(0)"                          t_non_commit_command_allows

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && echo "✅ all pass" || { echo "❌ FAILED: ${FAILED[*]}"; exit 1; }
