#!/usr/bin/env bash
# Slice E smoke — dispatch-slice-pane.sh 의 worktree + pane spawn 동작 검증.
# DISPATCH_CHILD_CMD=zsh 로 실제 claude 호출 회피.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DISPATCH="$REPO/scripts/dispatch-slice-pane.sh"
WRAPPER="$REPO/scripts/tmux-pane.sh"

step() { echo ""; echo "[$1] $2"; }
fail() { echo "❌ FAIL: $1" >&2; exit 1; }

if ! command -v tmux > /dev/null 2>&1; then
  echo "SKIP: tmux not installed"
  exit 0
fi
if [ ! -x "$WRAPPER" ]; then
  echo "SKIP: $WRAPPER not present (Slice A 머지 전)"
  exit 0
fi
if [ ! -x "$DISPATCH" ]; then
  fail "dispatcher not executable: $DISPATCH"
fi

unset TMUX

tmpdir=$(mktemp -d)
cleanup() {
  [ -n "${PANE:-}" ] && "$WRAPPER" kill --pane="$PANE" 2>/dev/null || true
  if [ -d "$tmpdir/.worktrees/test-slice" ]; then
    (cd "$tmpdir" && git worktree remove --force .worktrees/test-slice 2>/dev/null || true)
  fi
  rm -rf "$tmpdir"
}
trap cleanup EXIT

step 1 "더미 git repo 준비"
(
  cd "$tmpdir"
  git init -b main -q
  git config user.email t@e.local
  git config user.name tester
  echo dummy > README
  git add README
  git -c commit.gpgsign=false commit -m base -q
) || fail "git init failed"

step 2 "더미 spec 파일"
echo "test slice spec body for dispatcher" > "$tmpdir/spec.md"

step 3 "dispatcher 호출 (DISPATCH_CHILD_CMD=zsh)"
JSON=$(cd "$tmpdir" && DISPATCH_CHILD_CMD=zsh "$DISPATCH" \
  --slice=test-slice --spec-file="$tmpdir/spec.md" \
  --worktree="$tmpdir/.worktrees/test-slice") || fail "dispatcher failed"
echo "  json=$JSON"

step 4 "JSON 파싱"
PANE=$(echo "$JSON" | python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print(d['pane'])")
WT=$(echo "$JSON" | python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print(d['worktree'])")
BR=$(echo "$JSON" | python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print(d['branch'])")
[ -n "$PANE" ] || fail "pane empty"
[ "$BR" = "slice/test-slice" ] || fail "branch mismatch: $BR"

step 5 "worktree 존재"
[ -d "$WT" ] || fail "worktree dir missing: $WT"

step 6 "slice/test-slice 브랜치 존재"
(cd "$tmpdir" && git branch --list slice/test-slice | grep -q test-slice) || fail "branch not listed"

step 7 "pane 에 cd + 자식 실행 흔적 (capture)"
sleep 1
OUT=$("$WRAPPER" capture --pane="$PANE") || fail "capture failed"
# 디렉토리명 또는 spec 내용 일부 grep
echo "$OUT" | grep -E "test-slice|spec\.md|\\\$" > /dev/null || fail "pane shows no expected trace: $OUT"

echo ""
echo "OK"
