#!/usr/bin/env bash
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO/scripts/cmux-title-chpwd.sh"
PASS=0; FAIL=0; FAILED=()
run() { local name="$1"; shift; if "$@" >/dev/null 2>&1; then echo "✔ $name"; PASS=$((PASS+1)); else echo "✘ $name"; FAIL=$((FAIL+1)); FAILED+=("$name"); fi; }

# mock cmux: 인자를 log 파일에 기록.
# list-pane-surfaces 호출 시 MOCK_SURFACE_COUNT(디폴트 1) 만큼 stdout 줄 출력
# (hook 의 single-surface 판정용). 그 외 인자는 log 에 기록.
make_mock() {
  local tmp="$1"
  local mock="$tmp/cmux-mock.sh"
  cat > "$mock" <<MEOF
#!/bin/bash
echo "\$*" >> "$tmp/cmux.log"
if [ "\$1" = "list-pane-surfaces" ]; then
  cnt="\${MOCK_SURFACE_COUNT:-1}"
  i=1
  while [ "\$i" -le "\$cnt" ]; do
    echo "  surface:\$i  somedir"
    i=\$((i+1))
  done
fi
exit 0
MEOF
  chmod +x "$mock"
  echo "$mock"
}

t_renames_in_cmux_env() {
  local tmp; tmp=$(mktemp -d)
  local mock; mock=$(make_mock "$tmp")
  local workdir="$tmp/my-project"
  mkdir -p "$workdir"
  CMUX_SURFACE_ID=surface:9 CMUX_BIN=$mock \
    bash -c "cd '$workdir' && bash '$SCRIPT'"
  local logged; logged=$(cat "$tmp/cmux.log" 2>/dev/null || echo "")
  rm -rf "$tmp"
  # rename-tab --surface surface:9 my-project 호출됨
  echo "$logged" | grep -q "rename-tab --surface surface:9 my-project"
}

t_noop_outside_cmux() {
  local tmp; tmp=$(mktemp -d)
  local mock; mock=$(make_mock "$tmp")
  local workdir="$tmp/proj2"
  mkdir -p "$workdir"
  # CMUX_SURFACE_ID unset
  env -u CMUX_SURFACE_ID CMUX_BIN=$mock \
    bash -c "cd '$workdir' && bash '$SCRIPT'"
  local exists=0
  [ -f "$tmp/cmux.log" ] && exists=1
  rm -rf "$tmp"
  # 비-cmux → cmux 호출 0 (log 파일 없음)
  [ "$exists" = "0" ]
}

t_title_is_basename_only() {
  local tmp; tmp=$(mktemp -d)
  local mock; mock=$(make_mock "$tmp")
  local workdir="$tmp/deep/nested/leaf-dir"
  mkdir -p "$workdir"
  CMUX_SURFACE_ID=surface:3 CMUX_BIN=$mock \
    bash -c "cd '$workdir' && bash '$SCRIPT'"
  local logged; logged=$(cat "$tmp/cmux.log" 2>/dev/null || echo "")
  rm -rf "$tmp"
  # title = leaf-dir (전체 경로 아님)
  echo "$logged" | grep -q "rename-tab --surface surface:3 leaf-dir" && \
    ! echo "$logged" | grep -q "nested"
}

t_survives_rename_failure() {
  local tmp; tmp=$(mktemp -d)
  # mock 이 exit 1 (rename 실패)
  local mock="$tmp/cmux-fail.sh"
  cat > "$mock" <<'MEOF'
#!/bin/bash
exit 1
MEOF
  chmod +x "$mock"
  local workdir="$tmp/p"
  mkdir -p "$workdir"
  CMUX_SURFACE_ID=surface:1 CMUX_BIN=$mock \
    bash -c "cd '$workdir' && bash '$SCRIPT'"
  local ec=$?
  rm -rf "$tmp"
  # rename 실패해도 script exit 0
  [ "$ec" = "0" ]
}

t_zsh_registers_chpwd_hook() {
  # zsh 있으면 add-zsh-hook chpwd 등록 확인. 없으면 skip (pass).
  command -v zsh >/dev/null 2>&1 || return 0
  local tmp; tmp=$(mktemp -d)
  local mock; mock=$(make_mock "$tmp")
  local out
  out=$(CMUX_SURFACE_ID=surface:5 CMUX_BIN=$mock zsh -c "
    source '$SCRIPT'
    print -l \${chpwd_functions[@]}
  " 2>/dev/null)
  rm -rf "$tmp"
  echo "$out" | grep -q "_cmux_title_chpwd"
}

t_single_surface_renames_workspace() {
  local tmp; tmp=$(mktemp -d)
  local mock; mock=$(make_mock "$tmp")
  local workdir="$tmp/my-project"
  mkdir -p "$workdir"
  CMUX_SURFACE_ID=surface:9 CMUX_WORKSPACE_ID=workspace:2 MOCK_SURFACE_COUNT=1 CMUX_BIN=$mock \
    bash -c "cd '$workdir' && bash '$SCRIPT'"
  local logged; logged=$(cat "$tmp/cmux.log" 2>/dev/null || echo "")
  rm -rf "$tmp"
  # single-surface → workspace-action rename + basename title
  echo "$logged" | grep -q "workspace-action --action rename --workspace workspace:2 --title my-project"
}

t_multi_surface_skips_workspace() {
  local tmp; tmp=$(mktemp -d)
  local mock; mock=$(make_mock "$tmp")
  local workdir="$tmp/my-project"
  mkdir -p "$workdir"
  CMUX_SURFACE_ID=surface:9 CMUX_WORKSPACE_ID=workspace:2 MOCK_SURFACE_COUNT=2 CMUX_BIN=$mock \
    bash -c "cd '$workdir' && bash '$SCRIPT'"
  local logged; logged=$(cat "$tmp/cmux.log" 2>/dev/null || echo "")
  rm -rf "$tmp"
  # multi-surface → workspace-action 호출 없음, rename-tab 은 존재
  echo "$logged" | grep -q "rename-tab --surface surface:9 my-project" && \
    ! echo "$logged" | grep -q "workspace-action"
}

t_no_workspace_id_tab_only() {
  local tmp; tmp=$(mktemp -d)
  local mock; mock=$(make_mock "$tmp")
  local workdir="$tmp/my-project"
  mkdir -p "$workdir"
  # CMUX_WORKSPACE_ID unset → tab 만, workspace-action 없음
  env -u CMUX_WORKSPACE_ID CMUX_SURFACE_ID=surface:9 CMUX_BIN=$mock \
    bash -c "cd '$workdir' && bash '$SCRIPT'"
  local logged; logged=$(cat "$tmp/cmux.log" 2>/dev/null || echo "")
  rm -rf "$tmp"
  echo "$logged" | grep -q "rename-tab --surface surface:9 my-project" && \
    ! echo "$logged" | grep -q "workspace-action"
}

run "cmux env 에서 rename-tab 호출 (basename title)" t_renames_in_cmux_env
run "비-cmux 셸 no-op (cmux 호출 0)" t_noop_outside_cmux
run "title = basename 만 (전체 경로 아님)" t_title_is_basename_only
run "rename-tab 실패해도 exit 0" t_survives_rename_failure
run "zsh chpwd_functions 에 hook 등록" t_zsh_registers_chpwd_hook
run "single-surface → workspace-action rename (basename)" t_single_surface_renames_workspace
run "multi-surface → workspace rename skip, tab 만" t_multi_surface_skips_workspace
run "CMUX_WORKSPACE_ID unset → tab 만" t_no_workspace_id_tab_only

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && echo "✅ all pass" || { echo "❌ FAILED: ${FAILED[*]}"; exit 1; }
