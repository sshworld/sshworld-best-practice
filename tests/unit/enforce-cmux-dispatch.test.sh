#!/usr/bin/env bash
# enforce-cmux-dispatch.sh hook 단위 테스트.
# PreToolUse ExitPlanMode — cmux 환경에서 plan Slice File Map 에 direct-edit 표셀 있으면 차단.
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="$REPO/hooks/enforce-cmux-dispatch.sh"
PASS=0; FAIL=0; FAILED=()
run() { local name="$1"; shift; if "$@" >/dev/null 2>&1; then echo "✔ $name"; PASS=$((PASS+1)); else echo "✘ $name"; FAIL=$((FAIL+1)); FAILED+=("$name"); fi; }

DIRECT_EDIT_PLAN='| S1 | foo.kt | direct-edit | updated |'
DISPATCH_PLAN='| S1 | foo.kt | dispatch(cmux) | none |'

mk_payload() {
  local tool="${1:-ExitPlanMode}" plan="${2:-}"
  printf '{"tool_name":"%s","tool_input":{"plan":"%s"}}' "$tool" "$plan"
}

# (a) cmux env + direct-edit plan → exit 2
t_a_cmux_direct_edit_blocks() {
  local p; p=$(mk_payload "ExitPlanMode" "$DIRECT_EDIT_PLAN")
  CMUX_WORKSPACE_ID="ws:1" bash "$HOOK" <<<"$p"
  [ "$?" = "2" ]
}

# (b) same + CMUX_DIRECT_EDIT_OK=1 → exit 0
t_b_ok_env_allows() {
  local p; p=$(mk_payload "ExitPlanMode" "$DIRECT_EDIT_PLAN")
  CMUX_WORKSPACE_ID="ws:1" CMUX_DIRECT_EDIT_OK=1 bash "$HOOK" <<<"$p"
  [ "$?" = "0" ]
}

# (c) 멀티플렉서 신호 전부 unset + direct-edit plan → exit 0 (non-mux)
# 개발 머신이 실제 Orca 세션이라 CMUX_WORKSPACE_ID 만 지우면 ORCA_* 앰비언트로
# kind=orca 로 새서 차단되어 버린다 — 진짜 "비-mux" 를 보려면 같이 지운다.
t_c_non_cmux_allows() {
  local p; p=$(mk_payload "ExitPlanMode" "$DIRECT_EDIT_PLAN")
  env -u CMUX_WORKSPACE_ID -u CMUX_SURFACE_ID -u CMUX_SOCKET -u CMUX_SOCKET_PASSWORD \
    -u ORCA_TERMINAL_HANDLE -u ORCA_WORKSPACE_ID -u TERM_PROGRAM \
    bash "$HOOK" <<<"$p"
  [ "$?" = "0" ]
}

# (d) cmux env + dispatch(cmux) plan only → exit 0
t_d_dispatch_plan_allows() {
  local p; p=$(mk_payload "ExitPlanMode" "$DISPATCH_PLAN")
  CMUX_WORKSPACE_ID="ws:1" bash "$HOOK" <<<"$p"
  [ "$?" = "0" ]
}

# (e1) SKIP_CMUX_DISPATCH_GATE=1 → exit 0
t_e1_skip_env_allows() {
  local p; p=$(mk_payload "ExitPlanMode" "$DIRECT_EDIT_PLAN")
  CMUX_WORKSPACE_ID="ws:1" SKIP_CMUX_DISPATCH_GATE=1 bash "$HOOK" <<<"$p"
  [ "$?" = "0" ]
}

# (e2) DISABLE_CMUX_DISPATCH_GATE_HOOK=1 → exit 0
t_e2_disable_env_allows() {
  local p; p=$(mk_payload "ExitPlanMode" "$DIRECT_EDIT_PLAN")
  CMUX_WORKSPACE_ID="ws:1" DISABLE_CMUX_DISPATCH_GATE_HOOK=1 bash "$HOOK" <<<"$p"
  [ "$?" = "0" ]
}

# (f) tool_name=Write + direct-edit plan → exit 0 (ExitPlanMode 아님)
t_f_non_exitplanmode_allows() {
  local p; p=$(mk_payload "Write" "$DIRECT_EDIT_PLAN")
  CMUX_WORKSPACE_ID="ws:1" bash "$HOOK" <<<"$p"
  [ "$?" = "0" ]
}

# (g) cmux + ExitPlanMode + empty tool_input → exit 0 (conservative)
t_g_empty_plan_allows() {
  local p='{"tool_name":"ExitPlanMode","tool_input":{}}'
  CMUX_WORKSPACE_ID="ws:1" bash "$HOOK" <<<"$p"
  [ "$?" = "0" ]
}

# (h) prose with "direct-edit" word (not pipe-wrapped) → exit 0 (false-positive 방지)
t_h_prose_direct_edit_allows() {
  local plan="cmux 환경에서 direct-edit 는 CMUX_DIRECT_EDIT_OK=1 escape 를 쓴다."
  local p; p=$(mk_payload "ExitPlanMode" "$plan")
  CMUX_WORKSPACE_ID="ws:1" bash "$HOOK" <<<"$p"
  [ "$?" = "0" ]
}

# (i) skip-once: git-common-dir 에 cbp-skip-once-cmux-dispatch 존재 → 1회 소비+allow, 2번째는 다시 block
t_i_skip_once_git_common_consumed_once() {
  local tmp; tmp=$(mktemp -d)
  local repo="$tmp/repo"; mkdir -p "$repo"
  git -C "$repo" init -q; git -C "$repo" commit --allow-empty -q -m init 2>/dev/null
  touch "$repo/.git/cbp-skip-once-cmux-dispatch"
  local p; p=$(mk_payload "ExitPlanMode" "$DIRECT_EDIT_PLAN")
  local ec1=0 ec2=0
  ( cd "$repo" && CMUX_WORKSPACE_ID="ws:1" bash "$HOOK" <<<"$p" ); ec1=$?
  ( cd "$repo" && CMUX_WORKSPACE_ID="ws:1" bash "$HOOK" <<<"$p" ); ec2=$?
  rm -rf "$tmp"
  [ "$ec1" = "0" ] && [ "$ec2" = "2" ]
}

# (j) 비-git cwd 폴백: $HOME/.cache/cbp/cbp-skip-once-cmux-dispatch-<sanitized> 사용
t_j_skip_once_non_git_fallback() {
  local tmp; tmp=$(mktemp -d)
  local nongit="$tmp/nogit"; mkdir -p "$nongit"
  local fakehome="$tmp/home"; mkdir -p "$fakehome/.cache/cbp"
  touch "$fakehome/.cache/cbp/cbp-skip-once-cmux-dispatch-ws_1"
  local p; p=$(mk_payload "ExitPlanMode" "$DIRECT_EDIT_PLAN")
  local ec=0
  ( cd "$nongit" && HOME="$fakehome" CMUX_WORKSPACE_ID="ws:1" bash "$HOOK" <<<"$p" )
  ec=$?
  local left; left=$( [ -f "$fakehome/.cache/cbp/cbp-skip-once-cmux-dispatch-ws_1" ] && echo yes || echo no )
  rm -rf "$tmp"
  [ "$ec" = "0" ] && [ "$left" = "no" ]
}

run "(a) cmux + direct-edit 표셀 → block(2)"         t_a_cmux_direct_edit_blocks
run "(b) CMUX_DIRECT_EDIT_OK=1 → allow(0)"           t_b_ok_env_allows
run "(c) 비-cmux + direct-edit → allow(0)"            t_c_non_cmux_allows
run "(d) cmux + dispatch(cmux) 전용 → allow(0)"       t_d_dispatch_plan_allows
run "(e1) SKIP_CMUX_DISPATCH_GATE=1 → allow(0)"      t_e1_skip_env_allows
run "(e2) DISABLE_CMUX_DISPATCH_GATE_HOOK=1 → allow(0)" t_e2_disable_env_allows
run "(f) tool=Write(비-ExitPlanMode) → allow(0)"     t_f_non_exitplanmode_allows
run "(g) tool_input 비어있음 → allow(0) conservative" t_g_empty_plan_allows
run "(h) 산문 direct-edit(표셀 아님) → allow(0)"      t_h_prose_direct_edit_allows
run "(i) skip-once(git-common-dir) 1회 소비"         t_i_skip_once_git_common_consumed_once
run "(j) skip-once 비-git cwd 폴백"                   t_j_skip_once_non_git_fallback

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && echo "✅ all pass" || { echo "❌ FAILED: ${FAILED[*]}"; exit 1; }
