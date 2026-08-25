#!/usr/bin/env bash
# Slice 1 — dispatch-slice-pane.sh 의 디폴트 --mode 결정 회귀 가드.
# 디폴트는 env DISPATCH_DEFAULT_MODE > "auto". auto 는 detect-pane-env 결과로 분기.
#
# DISPATCH_DRY_RUN=1 로 실제 spawn 없이 driver 결정만 검증.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DISPATCH="$REPO/scripts/dispatch-slice-pane.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
step() { echo; echo "[$1] $2"; }

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
echo "tmpdir=$tmpdir"

(
  cd "$tmpdir"
  git init -q
  echo dummy > README
  git add README
  git -c user.email=t@t -c user.name=t -c commit.gpgsign=false commit -q -m base
) || fail "git init failed"

echo "spec body" > "$tmpdir/spec.md"

# 공통 호출 헬퍼 — DRY_RUN, env 격리 (TMUX/CMUX_*/ORCA_*/TERM_PROGRAM 모두 unset 후 필요 시 set)
# ORCA_BIN 은 실제 orca 설치 머신에서 orca status probe 가 성공해 auto 감지가 'orca' 로
# 새는 것(오탐)을 막기 위해 존재하지 않는 경로로 고정한다 (CMUX_BIN=/bin/false 와 동일 목적).
run() {
  # $1 = "extra env"  $2 = "extra args"
  local extra_env="$1"
  local extra_args="$2"
  cd "$tmpdir"
  # shellcheck disable=SC2086
  env -u TMUX -u CMUX_WORKSPACE_ID -u CMUX_SURFACE_ID -u CMUX_SOCKET -u CMUX_SOCKET_PASSWORD \
      -u ORCA_TERMINAL_HANDLE -u ORCA_WORKSPACE_ID -u TERM_PROGRAM \
      CMUX_BIN=/bin/false \
      ORCA_BIN=/nonexistent/orca-bin-not-installed \
      DISPATCH_DRY_RUN=1 \
      $extra_env \
      "$DISPATCH" \
      --slice=mode-test \
      --spec-file="$tmpdir/spec.md" \
      $extra_args 2>&1
}

extract_driver() {
  python3 -c "import json,sys; d=json.loads(sys.stdin.read().strip().splitlines()[-1]); print(d['driver'])"
}

step A "디폴트 (env unset) + TMUX 환경 → driver=tmux"
out=$(run "TMUX=/tmp/x" "")
drv=$(echo "$out" | extract_driver) || fail "JSON parse: $out"
[ "$drv" = "tmux" ] || fail "expected driver=tmux, got '$drv' (out=$out)"
echo "  driver=$drv OK"

step B "디폴트 (env unset) + CMUX_WORKSPACE_ID 환경 → driver=cmux"
out=$(run "CMUX_WORKSPACE_ID=ws-1" "")
drv=$(echo "$out" | extract_driver) || fail "JSON parse: $out"
[ "$drv" = "cmux" ] || fail "expected driver=cmux, got '$drv' (out=$out)"
echo "  driver=$drv OK"

step C "디폴트 + 환경 모두 unset (default) → exit 2 (die)"
out=$(run "" "" 2>&1) && ec=0 || ec=$?
[ "$ec" = 2 ] || fail "expected exit 2 (default 환경 die), got $ec (out=$out)"
# "auto 감지" 만으로는 catch-all(알 수 없는 결과) 분기도 매치되어 오탐을 놓친다.
# "환경 아님" 은 진짜 "멀티플렉서 아님" 분기에만 있는 고유 문구.
echo "$out" | grep -q "환경 아님" || fail "expected '환경 아님' (tmux/cmux/orca 미감지 die) in stderr, got: $out"
echo "$out" | grep -q "알 수 없는 결과" && fail "catch-all(알 수 없는 결과) 분기로 샌 것으로 보임 — orca 오탐 가능성: $out"
echo "  exit=2 + '환경 아님' OK"

step D "--mode=tmux 명시 → driver=tmux (env 무시)"
out=$(run "CMUX_WORKSPACE_ID=ws-1" "--mode=tmux")
drv=$(echo "$out" | extract_driver) || fail "JSON parse: $out"
[ "$drv" = "tmux" ] || fail "expected driver=tmux (override), got '$drv'"
echo "  driver=$drv OK"

step E "DISPATCH_DEFAULT_MODE=tmux env (기존 동작 복원) → driver=tmux"
out=$(run "DISPATCH_DEFAULT_MODE=tmux CMUX_WORKSPACE_ID=ws-1" "")
drv=$(echo "$out" | extract_driver) || fail "JSON parse: $out"
[ "$drv" = "tmux" ] || fail "expected driver=tmux (env default), got '$drv'"
echo "  driver=$drv OK"

step F "--mode 명시가 DISPATCH_DEFAULT_MODE env 보다 우선"
out=$(run "DISPATCH_DEFAULT_MODE=tmux CMUX_WORKSPACE_ID=ws-1" "--mode=cmux")
drv=$(echo "$out" | extract_driver) || fail "JSON parse: $out"
[ "$drv" = "cmux" ] || fail "expected driver=cmux (arg over env), got '$drv'"
echo "  driver=$drv OK"

echo
echo "PASS"
