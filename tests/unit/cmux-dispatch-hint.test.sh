#!/usr/bin/env bash
# cmux-dispatch-hint.sh SessionStart hook 단위 테스트.
# cmux env 면 dispatch-first advisory stdout, 비-cmux 면 무출력. 둘 다 exit 0.
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="$REPO/hooks/cmux-dispatch-hint.sh"
PASS=0; FAIL=0; FAILED=()
run() { local name="$1"; shift; if "$@" >/dev/null 2>&1; then echo "✔ $name"; PASS=$((PASS+1)); else echo "✘ $name"; FAIL=$((FAIL+1)); FAILED+=("$name"); fi; }

t_cmux_emits_advisory() {
  local out ec
  out=$(CMUX_WORKSPACE_ID=ws-1 bash "$HOOK" 2>/dev/null); ec=$?
  [ "$ec" = "0" ] && echo "$out" | grep -qi "dispatch"
}

t_cmux_exit0() {
  CMUX_WORKSPACE_ID=ws-1 bash "$HOOK" >/dev/null 2>&1
}

t_non_cmux_no_output() {
  local out ec
  # 개발 머신이 실제 Orca 세션이라 CMUX_WORKSPACE_ID 만 지우면 ORCA_* 앰비언트로 새
  # kind=orca 배너가 나온다 — 진짜 "비-mux" 를 보려면 같이 지운다.
  out=$(env -u CMUX_WORKSPACE_ID -u CMUX_SURFACE_ID -u CMUX_SOCKET -u CMUX_SOCKET_PASSWORD \
    -u ORCA_TERMINAL_HANDLE -u ORCA_WORKSPACE_ID -u TERM_PROGRAM -u TMUX \
    bash "$HOOK" 2>/dev/null); ec=$?
  [ "$ec" = "0" ] && [ -z "$out" ]
}

run "cmux env → dispatch advisory 출력 + exit 0"  t_cmux_emits_advisory
run "cmux env → exit 0"                           t_cmux_exit0
run "비-cmux → 무출력 + exit 0"                    t_non_cmux_no_output

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && echo "✅ all pass" || { echo "❌ FAILED: ${FAILED[*]}"; exit 1; }
