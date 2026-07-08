#!/usr/bin/env bash
# Slice I — dispatch-slice-pane.sh 가 main 진입 시 cleanup 자동 호출 검증.
# DISPATCH_SKIP_CLEANUP=1 시 skip 검증.

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

unset TMUX

# 기존 tmux-pane-mgr 정리
tmux kill-session -t tmux-pane-mgr 2>/dev/null || true

# 더미 git repo
tmpdir=$(mktemp -d)
cleanup_tmp() {
  tmux kill-session -t tmux-pane-mgr 2>/dev/null || true
  if [ -d "$tmpdir/.worktrees/auto-cleanup-test" ]; then
    (cd "$tmpdir" && git worktree remove --force .worktrees/auto-cleanup-test 2>/dev/null || true)
  fi
  rm -rf "$tmpdir"
}
trap cleanup_tmp EXIT

(
  cd "$tmpdir"
  git init -b main -q
  git config user.email t@e.local
  git config user.name tester
  echo dummy > README
  git add README
  git -c commit.gpgsign=false commit -m base -q
)
echo "spec" > "$tmpdir/spec.md"

step 1 "사전 자식 pane 2개 spawn"
"$WRAPPER" launch zsh > /dev/null
"$WRAPPER" launch zsh > /dev/null
BEFORE=$(tmux list-panes -s -t tmux-pane-mgr -F '#{pane_id}' 2>/dev/null | wc -l | tr -d ' ')
[ "$BEFORE" -ge 2 ] || fail "사전 pane 부족: $BEFORE"

step 2 "dispatcher 호출 (DISPATCH_CHILD_CMD=zsh) — cleanup 자동 발동"
JSON=$(cd "$tmpdir" && DISPATCH_CHILD_CMD=zsh "$DISPATCH" \
  --slice=auto-cleanup-test --spec-file="$tmpdir/spec.md" \
  --worktree="$tmpdir/.worktrees/auto-cleanup-test" \
  --mode=tmux 2> /tmp/disp-err-$$) || fail "dispatcher fail"
echo "  json=$JSON"
grep -E "cleaning [0-9]+ child pane" /tmp/disp-err-$$ > /dev/null || { cat /tmp/disp-err-$$; fail "auto-cleanup 보고 누락"; }

step 3 "dispatcher 후엔 사전 pane 들이 정리되고 새 자식만 남음"
AFTER=$(tmux list-panes -s -t tmux-pane-mgr -F '#{pane_id}' 2>/dev/null | wc -l | tr -d ' ')
# mgr session 은 dispatcher 가 새 자식 launch 하면서 다시 생성 — sleep pane + launched pane = 보통 2
# 사전 spawn 된 2개의 pane id 가 더 이상 없어야 함 (다른 id 라도 OK)
[ "$AFTER" -le 2 ] || fail "auto-cleanup 후 잔존 pane 비정상: $AFTER (사전 정리 안 됨)"

step 4 "DISPATCH_SKIP_CLEANUP=1 — cleanup skip"
# 추가 자식 띄움 (현재 dispatcher 자식 + 추가 1 = 2)
"$WRAPPER" launch zsh > /dev/null
BEFORE2=$(tmux list-panes -s -t tmux-pane-mgr -F '#{pane_id}' 2>/dev/null | wc -l | tr -d ' ')
# 두 번째 dispatcher (다른 slice) — SKIP_CLEANUP 으로
(cd "$tmpdir" && DISPATCH_SKIP_CLEANUP=1 DISPATCH_CHILD_CMD=zsh "$DISPATCH" \
  --slice=auto-cleanup-test-2 --spec-file="$tmpdir/spec.md" \
  --worktree="$tmpdir/.worktrees/auto-cleanup-test-2" \
  --mode=tmux 2> /tmp/disp-err-$$) > /dev/null || fail "dispatcher 2 fail"
# SKIP 면 cleaning 보고 안 나옴
if grep -E "cleaning [0-9]+ child pane" /tmp/disp-err-$$ > /dev/null; then
  cat /tmp/disp-err-$$
  fail "SKIP 인데 cleanup 발동"
fi

# 정리 (테스트 격리 깨지 않게)
(cd "$tmpdir" && git worktree remove --force .worktrees/auto-cleanup-test-2 2>/dev/null || true)
rm -f /tmp/disp-err-$$

step 5 "plan-dev marker 존재 + 동일 start_ts 2회 dispatch — stamp 로 cleanup 1회만"
GITCOMMON_REL=$(cd "$tmpdir" && git rev-parse --git-common-dir)
case "$GITCOMMON_REL" in
  /*) GITCOMMON_ABS="$GITCOMMON_REL" ;;
  *)  GITCOMMON_ABS="$tmpdir/$GITCOMMON_REL" ;;
esac
MARKER="$GITCOMMON_ABS/plan-dev-session.json"
STAMP="$GITCOMMON_ABS/plan-dev-dispatch-cleaned"
rm -f "$STAMP"
cat > "$MARKER" <<'JSON'
{"start_ts":"2024-01-01T00:00:00Z","start_ref":"deadbeef","base_branch":"main","work_branch":"main","start_pid":99999,"auto_branch":"false"}
JSON

"$WRAPPER" launch zsh > /dev/null

(cd "$tmpdir" && DISPATCH_CHILD_CMD=zsh "$DISPATCH" \
  --slice=auto-cleanup-test-3 --spec-file="$tmpdir/spec.md" \
  --worktree="$tmpdir/.worktrees/auto-cleanup-test-3" \
  --mode=tmux 2> /tmp/disp-err3-$$) > /dev/null || fail "dispatcher 3 fail"
grep -E "cleaning [0-9]+ child pane" /tmp/disp-err3-$$ > /dev/null || { cat /tmp/disp-err3-$$; fail "1차 dispatch(stamp 최초 생성) 인데 cleanup 미발동"; }
[ -f "$STAMP" ] || fail "stamp 파일 생성 안 됨: $STAMP"
[ "$(cat "$STAMP")" = "2024-01-01T00:00:00Z" ] || fail "stamp 내용 mismatch: $(cat "$STAMP")"

(cd "$tmpdir" && DISPATCH_CHILD_CMD=zsh "$DISPATCH" \
  --slice=auto-cleanup-test-4 --spec-file="$tmpdir/spec.md" \
  --worktree="$tmpdir/.worktrees/auto-cleanup-test-4" \
  --mode=tmux 2> /tmp/disp-err4-$$) > /dev/null || fail "dispatcher 4 fail"
if grep -E "cleaning [0-9]+ child pane" /tmp/disp-err4-$$ > /dev/null; then
  cat /tmp/disp-err4-$$
  fail "2차 dispatch (동일 start_ts) 인데 cleanup 재발동 — stamp 1회성 위반"
fi

(cd "$tmpdir" && git worktree remove --force .worktrees/auto-cleanup-test-3 2>/dev/null || true)
(cd "$tmpdir" && git worktree remove --force .worktrees/auto-cleanup-test-4 2>/dev/null || true)
rm -f "$MARKER" "$STAMP" /tmp/disp-err3-$$ /tmp/disp-err4-$$

echo ""
echo "OK"
