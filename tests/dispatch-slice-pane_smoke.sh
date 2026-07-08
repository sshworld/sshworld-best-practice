#!/usr/bin/env bash
# Slice E smoke — dispatch-slice-pane.sh 의 worktree + pane spawn 동작 검증.
# DISPATCH_CHILD_CMD=zsh 로 실제 claude 호출 회피.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DISPATCH="$REPO/scripts/dispatch-slice-pane.sh"
WRAPPER="$REPO/scripts/tmux-pane.sh"

step() { echo ""; echo "[$1] $2"; }
fail() { echo "❌ FAIL: $1" >&2; exit 1; }

step 0 "DRY_RUN trust_seeded 필드 검증 (tmux 불필요)"
DRY_JSON=$(DISPATCH_DRY_RUN=1 DISPATCH_SKIP_CLEANUP=1 CMUX_BIN=echo \
  bash "$DISPATCH" \
    --slice=trust-dry-test \
    --spec-file="/dev/null" \
    --mode=cmux 2>/dev/null) || fail "DRY_RUN 실패"
echo "  dry_json=$DRY_JSON"
echo "$DRY_JSON" | python3 -c "
import json,sys
d=json.loads(sys.stdin.read())
assert 'trust_seeded' in d, 'trust_seeded 필드 없음'
assert d['trust_seeded'] == True, 'trust_seeded 가 true 아님: ' + str(d['trust_seeded'])
print('  trust_seeded=true OK')
" || fail "trust_seeded 체크 실패"

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
  --worktree="$tmpdir/.worktrees/test-slice" \
  --mode=tmux) || fail "dispatcher failed"
echo "  json=$JSON"

step 4 "JSON 파싱"
PANE=$(echo "$JSON" | python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print(d['pane'])")
WT=$(echo "$JSON" | python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print(d['worktree'])")
BR=$(echo "$JSON" | python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print(d['branch'])")
[ -n "$PANE" ] || fail "pane empty"
[ "$BR" = "feature/test-slice" ] || fail "branch mismatch: $BR"

step 5 "worktree 존재"
[ -d "$WT" ] || fail "worktree dir missing: $WT"

step 6 "feature/test-slice 브랜치 존재 (feat→feature 매핑)"
(cd "$tmpdir" && git branch --list feature/test-slice | grep -q test-slice) || fail "branch not listed"

step 7 "pane 에 cd + 자식 실행 흔적 (capture)"
sleep 1
OUT=$("$WRAPPER" capture --pane="$PANE") || fail "capture failed"
# 디렉토리명 또는 spec 내용 일부 grep
echo "$OUT" | grep -E "test-slice|spec\.md|\\\$" > /dev/null || fail "pane shows no expected trace: $OUT"

step 8 "공백 포함 worktree 경로 — cd 전송 인자가 shell-quote 됨 (mock wrapper 로 수신 문자열 검증)"
FAKE_DIR2=$(mktemp -d)
TRACE2="$FAKE_DIR2/trace.txt"
cat > "$FAKE_DIR2/tmux-cli" <<EOF
#!/usr/bin/env bash
case "\$1" in
  launch) echo "fake:1.0" ;;
  send)
    shift
    text="\$1"
    printf 'SEND-TEXT:%s\n' "\$text" >> "$TRACE2"
    ;;
  wait-idle) exit 0 ;;
  capture)  echo "" ;;
  kill)     exit 0 ;;
  *)        exit 0 ;;
esac
EOF
chmod +x "$FAKE_DIR2/tmux-cli"

tmpdir2=$(mktemp -d)
cleanup2() {
  (cd "$tmpdir2" && git worktree remove --force "$tmpdir2/.worktrees/space test-slice" 2>/dev/null || true)
  rm -rf "$FAKE_DIR2" "$tmpdir2"
}
trap 'cleanup2; cleanup' EXIT
(
  cd "$tmpdir2"
  git init -b main -q
  git config user.email t@e.local
  git config user.name tester
  echo dummy > README
  git add README
  git -c commit.gpgsign=false commit -m base -q
) || fail "git init 2 failed"
echo spec > "$tmpdir2/spec.md"

WT2="$tmpdir2/.worktrees/space test-slice"
(cd "$tmpdir2" && PATH="$FAKE_DIR2:$PATH" CBP_CLAUDE_CONFIG="$tmpdir2/claude.json" DISPATCH_CHILD_CMD=zsh "$DISPATCH" \
  --slice=space-test-slice --spec-file="$tmpdir2/spec.md" \
  --worktree="$WT2" \
  --mode=tmux > /dev/null) || fail "quoting dispatcher failed"

WT2_ABS=$(cd "$WT2" && pwd)
EXPECTED_Q=$(printf '%q' "$WT2_ABS")
grep -Fq "SEND-TEXT:cd $EXPECTED_Q" "$TRACE2" || { echo "--- trace ---"; cat "$TRACE2"; fail "cd 전송이 quote 안 됨 (expected: cd $EXPECTED_Q)"; }

echo ""
echo "OK"
