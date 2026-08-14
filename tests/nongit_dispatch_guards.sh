#!/usr/bin/env bash
# 비-git dispatch + 안내 불일치 4건 계약 테스트.
#
# ⚠️ 실제 cmux/tmux 를 호출하지 않는다 (DISPATCH_DRY_RUN=1 + mock).
# plan-dev-session.sh start 를 실행하므로 실제 reap-orphans 가 나가지 않도록 선언한다.
export SKIP_CMUX_REAP=1
export SKIP_PLAN_DEV_CMUX_CLEANUP=1

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DISPATCH="$REPO/scripts/dispatch-slice-pane.sh"
ENFORCE="$REPO/hooks/enforce-cmux-dispatch.sh"
HINT="$REPO/hooks/cmux-dispatch-hint.sh"
SESSION="$REPO/scripts/plan-dev-session.sh"

step() { echo ""; echo "[$1] $2"; }
fail() { echo "❌ FAIL: $1" >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mk_spec() { local f="$TMP/spec-$RANDOM.md"; echo "# spec" > "$f"; printf '%s' "$f"; }

# ─────────────────────────────────────────────────────────
step 1 "비-git 디렉토리 dispatch — die 하지 않고 cwd 로 진행"
NONGIT="$TMP/nongit"; mkdir -p "$NONGIT"
SPEC=$(mk_spec)
set +e
OUT=$(cd "$NONGIT" && DISPATCH_DRY_RUN=1 CMUX_WORKSPACE_ID=ws1 \
  "$DISPATCH" --slice=repro --type=fix --spec-file="$SPEC" --mode=cmux 2>"$TMP/err1")
RC=$?
set -e
ERR=$(cat "$TMP/err1")
[ "$RC" -eq 0 ] || fail "비-git 에서 die 함 (rc=$RC)\nstdout=$OUT\nstderr=$ERR"
printf '%s' "$OUT" | grep -q '"worktree"' || fail "dry-run JSON 에 worktree 없음: $OUT"

step 2 "worktree 가 cwd 이고 격리 없음 경고 + Slice File Map 안내"
printf '%s' "$OUT" | grep -q "$NONGIT" || fail "worktree 가 cwd 가 아님: $OUT"
printf '%s' "$ERR" | grep -q '격리' || fail "격리 없음 경고 없음: $ERR"
printf '%s' "$ERR" | grep -q 'Slice File Map' || fail "충돌 주의 안내 없음: $ERR"

step 3 "git repo 에서는 기존 격리 동작 유지 (회귀)"
GITREPO="$TMP/gitrepo"; mkdir -p "$GITREPO"
git -C "$GITREPO" init -q
git -C "$GITREPO" -c user.email=t@e -c user.name=t commit -q --allow-empty -m init
SPEC2=$(mk_spec)
set +e
OUT2=$(cd "$GITREPO" && DISPATCH_DRY_RUN=1 CMUX_WORKSPACE_ID=ws1 \
  "$DISPATCH" --slice=iso --type=fix --spec-file="$SPEC2" --mode=cmux 2>"$TMP/err3")
RC2=$?
set -e
[ "$RC2" -eq 0 ] || fail "git repo dry-run 실패 (rc=$RC2): $(cat "$TMP/err3")"
printf '%s' "$OUT2" | grep -q '.worktrees/iso' || fail "git 경로에서 worktree 격리 경로가 아님: $OUT2"
printf '%s' "$(cat "$TMP/err3")" | grep -q '격리' && fail "git repo 인데 격리 없음 경고가 떴다"

# ─────────────────────────────────────────────────────────
step 4 "enforce-cmux-dispatch — 안내 경로 == 실제 소비 경로 (단일 출처)"
grep -q '_SKIP_ONCE_FILE' "$ENFORCE" || fail "훅에 _SKIP_ONCE_FILE 없음"
# 안내 문구가 경로를 하드코딩하지 않고 변수를 출력해야 한다
grep -qE 'touch "?\$_SKIP_ONCE_FILE|touch \$\{_SKIP_ONCE_FILE\}|\$_SKIP_ONCE_FILE' "$ENFORCE" \
  || fail "안내가 \$_SKIP_ONCE_FILE 를 출력하지 않음 (하드코딩 잔존?)"
grep -q 'cbp-skip-once-cmux-dispatch"' "$ENFORCE" && \
  grep -q 'git rev-parse --git-common-dir 2>/dev/null || echo' "$ENFORCE" && \
  fail "하드코딩된 안내 경로가 남아 있음"

step 5 "cmux-dispatch-hint — read-screen 없음, capture 있음"
grep -q 'read-screen' "$HINT" && fail "훅 문구에 read-screen 잔존 (cmux-pane.sh 명령이 아님)"
grep -q 'capture' "$HINT" || fail "훅 문구에 capture 없음"

# ─────────────────────────────────────────────────────────
step 6 "비-git 에서 plan-dev-session start — git repo 아님만 출력, detached HEAD 오진단 없음"
set +e
SOUT=$(cd "$NONGIT" && "$SESSION" start 2>&1)
SRC=$?
set -e
printf '%s' "$SOUT" | grep -q 'git repo 가 아님' || fail "비-git 판정 메시지 없음: $SOUT"
printf '%s' "$SOUT" | grep -q 'detached HEAD' && fail "detached HEAD 오진단이 여전히 나옴: $SOUT"
[ "$SRC" -ne 0 ] || fail "비-git 인데 rc=0 으로 계속 진행했다"

step 7 "git repo 에서 start 정상 (회귀)"
set +e
SOUT2=$(cd "$GITREPO" && "$SESSION" start 2>&1)
SRC2=$?
set -e
[ "$SRC2" -eq 0 ] || fail "git repo start 실패 (rc=$SRC2): $SOUT2"

echo ""
echo "OK"
