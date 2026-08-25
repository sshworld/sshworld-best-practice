#!/usr/bin/env bash
# detect-pane-env.sh 의 Orca 감지 계약 테스트.
#
# ⚠️ 개발 환경 자체가 Orca 안에서 돈다 — ORCA_* / TERM_PROGRAM=Orca 가
#    ambient 로 이미 set 되어 있다. 매 케이스를 clean env(env -i)로 실행해
#    ambient 값이 새어 들어가 우연히 통과하는 일을 막는다.
# ⚠️ 실제 orca/cmux 바이너리를 호출하지 않는다 — ORCA_BIN/CMUX_BIN 을
#    /nonexistent 로 돌려 probe 가 항상 실패하게 만든다.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO/scripts/detect-pane-env.sh"

step() { echo ""; echo "[$1] $2"; }
fail() { echo "❌ FAIL: $1" >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# clean env 로 detect_pane_env 실행. 인자로 넘긴 VAR=val 쌍만 추가로 export.
run_clean() {
  env -i PATH="$PATH" HOME="$HOME" ORCA_BIN=/nonexistent CMUX_BIN=/nonexistent \
    "$@" bash "$SCRIPT"
}

step 1 "ORCA_TERMINAL_HANDLE 단독 → orca"
OUT=$(run_clean ORCA_TERMINAL_HANDLE=term_x)
[ "$OUT" = "orca" ] || fail "ORCA_TERMINAL_HANDLE 단독인데 결과=$OUT"

step 2 "TERM_PROGRAM=Orca 단독 → orca"
OUT=$(run_clean TERM_PROGRAM=Orca)
[ "$OUT" = "orca" ] || fail "TERM_PROGRAM=Orca 단독인데 결과=$OUT"

step 3 "ORCA_WORKSPACE_ID 단독 → orca"
OUT=$(run_clean ORCA_WORKSPACE_ID=ws)
[ "$OUT" = "orca" ] || fail "ORCA_WORKSPACE_ID 단독인데 결과=$OUT"

step 4 "TMUX + orca 신호 동시 → tmux (우선순위 보존)"
OUT=$(run_clean TMUX=/tmp/tmux-x ORCA_TERMINAL_HANDLE=term_x TERM_PROGRAM=Orca ORCA_WORKSPACE_ID=ws)
[ "$OUT" = "tmux" ] || fail "TMUX+orca 신호 동시인데 결과=$OUT (tmux 여야 함)"

step 5 "CMUX_WORKSPACE_ID + orca 신호 동시 → cmux (회귀 방지 — 가장 중요)"
OUT=$(run_clean CMUX_WORKSPACE_ID=cws ORCA_TERMINAL_HANDLE=term_x TERM_PROGRAM=Orca ORCA_WORKSPACE_ID=ws)
[ "$OUT" = "cmux" ] || fail "CMUX_WORKSPACE_ID+orca 신호 동시인데 결과=$OUT (cmux 여야 함)"

step 6 "신호 없음 + 양쪽 probe 바이너리 부재 → default"
OUT=$(run_clean)
[ "$OUT" = "default" ] || fail "신호 없음인데 결과=$OUT (default 여야 함)"

step 7 "TERM_PROGRAM=OrcaSomething → orca 아님 (exact-match guard)"
OUT=$(run_clean TERM_PROGRAM=OrcaSomething)
[ "$OUT" = "orca" ] && fail "TERM_PROGRAM=OrcaSomething 인데 orca 로 오판정 (substring match 잔존?)"

OUT=$(run_clean TERM_PROGRAM=iTerm.app)
[ "$OUT" = "orca" ] && fail "TERM_PROGRAM=iTerm.app 인데 orca 로 오판정"

step 8 "source 시 main 실행 안 됨, detect_pane_env 함수는 호출 가능"
OUT=$(env -i PATH="$PATH" HOME="$HOME" ORCA_BIN=/nonexistent CMUX_BIN=/nonexistent \
  ORCA_TERMINAL_HANDLE=term_x bash -c "source '$SCRIPT'; detect_pane_env")
[ "$OUT" = "orca" ] || fail "source 후 detect_pane_env 직접 호출 결과=$OUT (orca 여야 함)"

echo ""
echo "OK"
