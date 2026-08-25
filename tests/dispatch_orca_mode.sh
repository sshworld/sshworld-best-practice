#!/usr/bin/env bash
# dispatch_orca_mode.sh — dispatch-slice-pane.sh 의 orca driver 배선 계약 테스트.
#
# ⚠️ 실제 orca/cmux/tmux 를 호출하지 않는다 (DISPATCH_DRY_RUN=1 + ORCA_BIN/CMUX_BIN mock).
export SKIP_CMUX_REAP=1
export SKIP_PLAN_DEV_CMUX_CLEANUP=1

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DISPATCH="$REPO/scripts/dispatch-slice-pane.sh"

step() { echo ""; echo "[$1] $2"; }
fail() { echo "❌ FAIL: $1" >&2; exit 1; }

[ -f "$DISPATCH" ] || fail "dispatcher 없음: $DISPATCH"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "spec body" > "$TMP/spec.md"

# 공통 env 격리 헬퍼 — 개발 머신의 실제 orca/cmux/tmux 환경이 케이스를 오염시키지 않게
# 매 호출마다 TMUX/CMUX_*/ORCA_*/TERM_PROGRAM 을 명시적으로 비운다.
run() {
  # $1 = extra env (문자열, word-split 의도)  $@나머지 = dispatch args
  local extra_env="$1"; shift
  # shellcheck disable=SC2086
  env -u TMUX -u CMUX_WORKSPACE_ID -u CMUX_SURFACE_ID -u CMUX_SOCKET -u CMUX_SOCKET_PASSWORD \
      -u ORCA_TERMINAL_HANDLE -u ORCA_WORKSPACE_ID -u TERM_PROGRAM \
      DISPATCH_DRY_RUN=1 \
      DISPATCH_SKIP_CLEANUP=1 \
      $extra_env \
      "$DISPATCH" --slice=orca-test --spec-file="$TMP/spec.md" "$@" 2>"$TMP/err"
}

extract() {
  python3 -c "import json,sys; d=json.loads(sys.stdin.read().strip().splitlines()[-1]); print(d.get('$1',''))"
}

# ─────────────────────────────────────────────────────────
step 1 "--mode=orca + DISPATCH_DRY_RUN=1 → driver=orca + wrapper=orca-pane.sh"
out=$(run "" --mode=orca) || fail "실행 실패: $(cat "$TMP/err")"
drv=$(printf '%s' "$out" | extract driver) || fail "JSON parse 실패: $out"
[ "$drv" = "orca" ] || fail "expected driver=orca, got '$drv' (out=$out)"
wrapper=$(printf '%s' "$out" | extract wrapper) || fail "wrapper 필드 parse 실패: $out"
case "$wrapper" in
  */orca-pane.sh) : ;;
  *) fail "wrapper 가 orca-pane.sh 로 안 끝남: $wrapper" ;;
esac
echo "  driver=$drv wrapper=$wrapper OK"

# ─────────────────────────────────────────────────────────
step 2 "orca 신호만 존재 + --mode=auto → exit 0 + driver=orca (과거엔 die 하던 케이스)"
out=$(run "ORCA_TERMINAL_HANDLE=term_abc123" --mode=auto) || fail "auto+orca 신호인데 실패: $(cat "$TMP/err")"
drv=$(printf '%s' "$out" | extract driver) || fail "JSON parse 실패: $out"
[ "$drv" = "orca" ] || fail "expected driver=orca (auto 감지), got '$drv' (out=$out)"
echo "  driver=$drv OK"

# ─────────────────────────────────────────────────────────
step 3 "--mode=orca 인데 scripts/orca-pane.sh 부재 → 명확한 die, exit != 0"
FAKESCRIPTS="$TMP/fake-scripts"
mkdir -p "$FAKESCRIPTS"
cp "$DISPATCH" "$FAKESCRIPTS/dispatch-slice-pane.sh"
chmod +x "$FAKESCRIPTS/dispatch-slice-pane.sh"
# 의도적으로 orca-pane.sh 를 두지 않는다 (tmux-pane.sh/cmux-pane.sh 도 없음 — orca 분기만 테스트)
set +e
out3=$(env -u TMUX -u CMUX_WORKSPACE_ID -u CMUX_SURFACE_ID -u CMUX_SOCKET -u CMUX_SOCKET_PASSWORD \
    -u ORCA_TERMINAL_HANDLE -u ORCA_WORKSPACE_ID -u TERM_PROGRAM \
    DISPATCH_DRY_RUN=1 \
    DISPATCH_SKIP_CLEANUP=1 \
    "$FAKESCRIPTS/dispatch-slice-pane.sh" --slice=orca-missing --spec-file="$TMP/spec.md" --mode=orca 2>&1)
rc3=$?
set -e
[ "$rc3" -ne 0 ] || fail "orca-pane.sh 없는데 exit 0: $out3"
printf '%s' "$out3" | grep -q "orca-pane.sh" || fail "die 메시지에 orca-pane.sh 언급 없음: $out3"
echo "  rc=$rc3 (!=0) + 'orca-pane.sh' 언급 OK"

# ─────────────────────────────────────────────────────────
step 4 "launch stdout 이 term_* 아니면 fail-fast (validate_pane_ref 경유)"
# dispatch 를 source 해서 함수만 노출 (sourcing guard 가 main 실행을 막는다)
# shellcheck disable=SC1090
source "$DISPATCH"
validate_pane_ref "not-a-valid-ref" >/dev/null 2>&1 && rc4=0 || rc4=$?
[ "$rc4" -ne 0 ] || fail "term_* 아닌 launch 결과가 통과함"
echo "  비-term_* ref 거부 OK (rc=$rc4)"

# ─────────────────────────────────────────────────────────
step 5 "validate_pane_ref — term_<uuid> 수용, surface:N / workspace:x 여전히 수용, garbage 거부"
result=$(validate_pane_ref "term_1234-abcd-uuid") || fail "term_<uuid> 거부됨"
[ "$result" = "term_1234-abcd-uuid" ] || fail "term_<uuid> 왕복 실패: $result"

result=$(validate_pane_ref "surface:4") || fail "surface:4 거부됨 (회귀)"
[ "$result" = "surface:4" ] || fail "surface:4 왕복 실패: $result"

result=$(validate_pane_ref "workspace:cbp-x") || fail "workspace:cbp-x 거부됨 (회귀)"
[ "$result" = "workspace:cbp-x" ] || fail "workspace:cbp-x 왕복 실패: $result"

validate_pane_ref "garbage" >/dev/null 2>&1 && rc5=0 || rc5=$?
[ "$rc5" -ne 0 ] || fail "garbage 가 통과함"
echo "  term_<uuid>/surface:N/workspace:x 수용, garbage 거부 OK"

# ─────────────────────────────────────────────────────────
step 6 "--mode=cmux / --mode=tmux 는 여전히 기존 wrapper 로 resolve (회귀 가드)"
out=$(run "" --mode=cmux) || fail "cmux 실행 실패: $(cat "$TMP/err")"
wrapper=$(printf '%s' "$out" | extract wrapper) || fail "wrapper parse 실패: $out"
case "$wrapper" in
  */cmux-pane.sh) : ;;
  *) fail "--mode=cmux 인데 wrapper 가 cmux-pane.sh 로 안 끝남: $wrapper" ;;
esac
drv=$(printf '%s' "$out" | extract driver) || fail "driver parse 실패: $out"
[ "$drv" = "cmux" ] || fail "expected driver=cmux, got '$drv'"

out=$(run "" --mode=tmux) || fail "tmux 실행 실패: $(cat "$TMP/err")"
wrapper=$(printf '%s' "$out" | extract wrapper) || fail "wrapper parse 실패: $out"
case "$wrapper" in
  */tmux-pane.sh|tmux-cli) : ;;
  *) fail "--mode=tmux 인데 wrapper 가 tmux-pane.sh/tmux-cli 아님: $wrapper" ;;
esac
drv=$(printf '%s' "$out" | extract driver) || fail "driver parse 실패: $out"
[ "$drv" = "tmux" ] || fail "expected driver=tmux, got '$drv'"
echo "  cmux/tmux wrapper 회귀 없음 OK"

echo ""
echo "OK"
