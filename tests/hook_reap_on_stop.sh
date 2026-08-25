#!/usr/bin/env bash
# Tests for hooks/reap-on-stop.sh

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$REPO/hooks/reap-on-stop.sh"

PASS=0; FAIL=0; FAILED=()

run() {
  local name="$1"; shift
  if "$@" >/dev/null 2>&1; then
    PASS=$((PASS+1))
    echo "✔ $name"
  else
    FAIL=$((FAIL+1))
    FAILED+=("$name")
    echo "✘ $name" >&2
  fi
}

[ -x "$HOOK" ] || { echo "hook not executable: $HOOK" >&2; exit 1; }

git_init_main() {
  local dir="$1"
  git -c init.defaultBranch=main init "$dir" -q 2>/dev/null \
    || git init "$dir" -q
  if [ "$(git -C "$dir" symbolic-ref --short HEAD 2>/dev/null)" != "main" ]; then
    git -C "$dir" checkout -b main -q 2>/dev/null || true
  fi
}

setup_parent_repo() {
  local tmp parent
  tmp=$(mktemp -d)
  parent="$tmp/parent"
  mkdir -p "$parent"
  git_init_main "$parent"
  git -C "$parent" config user.email "test@example.com"
  git -C "$parent" config user.name "Test"
  git -C "$parent" -c commit.gpgsign=false commit --allow-empty -q -m "init"
  echo "$parent"
}

# 부모 repo + .worktrees/test-slice 자식 worktree 셋업. 반환: "parent_path|worktree_path"
setup_repo_with_worktree() {
  local parent wt
  parent=$(setup_parent_repo)
  wt="$parent/.worktrees/test-slice"
  git -C "$parent" worktree add -q "$wt" -b feature/test-slice >/dev/null 2>&1
  echo "$parent|$wt"
}

# mock CBP_PANE_BIN — 호출 인자를 $PANE_CALLS_FILE 에 기록하고 $PANE_MODE 에 따라
# 화면덤프(여러 줄) + 상태줄을 stdout(/stderr) 으로 낸다. (실 cmux-pane.sh reap 출력 형태 모사)
make_mock_pane() {
  local bin="$1"
  cat > "$bin" <<'MOCKEOF'
#!/usr/bin/env bash
[ -n "${PANE_CALLS_FILE:-}" ] && echo "$*" >> "$PANE_CALLS_FILE"
ref=""
for a in "$@"; do
  case "$a" in
    --pane=*) ref="${a#--pane=}" ;;
  esac
done
case "${PANE_MODE:-reaped}" in
  reaped)
    echo "화면 줄1"
    echo "화면 줄2"
    echo "reaped $ref"
    ;;
  died)
    echo "died — surface '$ref' not a terminal" >&2
    echo "died $ref"
    ;;
  pending)
    echo "화면 줄1"
    echo "input-pending — kept $ref (CBP_REAP_IGNORE_PENDING=1 로 강제 회수 가능)"
    ;;
  reaped_annotated)
    echo "화면 줄1"
    echo "화면 줄2"
    echo "reaped $ref (pending-input 무시: push it)"
    ;;
  notdone)
    echo "화면 줄1"
    echo "not done — kept $ref"
    ;;
esac
exit 0
MOCKEOF
  chmod +x "$bin"
}

assert_json_one_line() {
  local out="$1"
  [ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" = "1" ] || return 1
  printf '%s' "$out" | python3 -c "import json,sys; json.loads(sys.stdin.read())" 2>/dev/null
}

# T1: marker(line1=surface:7, line2=자기 ws) → mock 호출 --pane=surface:7 + stdout JSON 1줄
t1_basic_reap() {
  local parent tmpdir pane_bin calls_file out marker rc
  parent=$(setup_parent_repo)
  tmpdir=$(mktemp -d)
  pane_bin="$tmpdir/pane"; make_mock_pane "$pane_bin"
  calls_file="$tmpdir/calls"

  marker="$parent/.git/cbp-slice-done-feature_x"
  printf 'surface:7\nws1\n' > "$marker"

  out=$(cd "$parent" && CBP_PANE_BIN="$pane_bin" PANE_CALLS_FILE="$calls_file" PANE_MODE="reaped" \
    CMUX_WORKSPACE_ID="ws1" CMUX_SURFACE_ID="" "$HOOK" < /dev/null 2>/dev/null)
  rc=$?

  [ "$rc" -eq 0 ] \
    && grep -q -- '--pane=surface:7' "$calls_file" 2>/dev/null \
    && assert_json_one_line "$out"
}

# T2: marker 없음 → mock 미호출 + stdout 빈 값
t2_no_marker_noop() {
  local parent tmpdir pane_bin calls_file out rc
  parent=$(setup_parent_repo)
  tmpdir=$(mktemp -d)
  pane_bin="$tmpdir/pane"; make_mock_pane "$pane_bin"
  calls_file="$tmpdir/calls"

  out=$(cd "$parent" && CBP_PANE_BIN="$pane_bin" PANE_CALLS_FILE="$calls_file" PANE_MODE="reaped" \
    CMUX_WORKSPACE_ID="ws1" CMUX_SURFACE_ID="" "$HOOK" < /dev/null 2>/dev/null)
  rc=$?

  [ "$rc" -eq 0 ] && [ ! -f "$calls_file" ] && [ -z "$out" ]
}

# T3: line2 = 타 ws → mock 미호출
t3_foreign_ws_skip() {
  local parent tmpdir pane_bin calls_file out marker rc
  parent=$(setup_parent_repo)
  tmpdir=$(mktemp -d)
  pane_bin="$tmpdir/pane"; make_mock_pane "$pane_bin"
  calls_file="$tmpdir/calls"

  marker="$parent/.git/cbp-slice-done-feature_x"
  printf 'surface:7\nws-other\n' > "$marker"

  out=$(cd "$parent" && CBP_PANE_BIN="$pane_bin" PANE_CALLS_FILE="$calls_file" PANE_MODE="reaped" \
    CMUX_WORKSPACE_ID="ws1" CMUX_SURFACE_ID="" "$HOOK" < /dev/null 2>/dev/null)
  rc=$?

  [ "$rc" -eq 0 ] && [ ! -f "$calls_file" ]
}

# T4: line2 없는 1줄 marker → 처리됨 (mock 호출, 하위호환)
t4_legacy_one_line_marker() {
  local parent tmpdir pane_bin calls_file out marker rc
  parent=$(setup_parent_repo)
  tmpdir=$(mktemp -d)
  pane_bin="$tmpdir/pane"; make_mock_pane "$pane_bin"
  calls_file="$tmpdir/calls"

  marker="$parent/.git/cbp-slice-done-feature_x"
  printf 'surface:7\n' > "$marker"

  out=$(cd "$parent" && CBP_PANE_BIN="$pane_bin" PANE_CALLS_FILE="$calls_file" PANE_MODE="reaped" \
    CMUX_WORKSPACE_ID="ws1" CMUX_SURFACE_ID="" "$HOOK" < /dev/null 2>/dev/null)
  rc=$?

  [ "$rc" -eq 0 ] && grep -q -- '--pane=surface:7' "$calls_file" 2>/dev/null
}

# T5: line1 빈 값 → skip. line1 == 자기 CMUX_SURFACE_ID → skip. (둘 다 mock 미호출)
t5_blank_and_self_surface_skip() {
  local parent tmpdir pane_bin calls_file out marker_blank marker_self rc
  parent=$(setup_parent_repo)
  tmpdir=$(mktemp -d)
  pane_bin="$tmpdir/pane"; make_mock_pane "$pane_bin"
  calls_file="$tmpdir/calls"

  marker_blank="$parent/.git/cbp-slice-done-feature_blank"
  printf '\nws1\n' > "$marker_blank"
  marker_self="$parent/.git/cbp-slice-done-feature_self"
  printf 'surface:9\nws1\n' > "$marker_self"

  out=$(cd "$parent" && CBP_PANE_BIN="$pane_bin" PANE_CALLS_FILE="$calls_file" PANE_MODE="reaped" \
    CMUX_WORKSPACE_ID="ws1" CMUX_SURFACE_ID="surface:9" "$HOOK" < /dev/null 2>/dev/null)
  rc=$?

  [ "$rc" -eq 0 ] && [ ! -f "$calls_file" ]
}

# T6: 자식 worktree cwd (git-dir≠common) → 무동작
t6_child_worktree_noop() {
  local pair parent wt tmpdir pane_bin calls_file marker out rc
  pair=$(setup_repo_with_worktree)
  parent="${pair%|*}"; wt="${pair#*|}"
  tmpdir=$(mktemp -d)
  pane_bin="$tmpdir/pane"; make_mock_pane "$pane_bin"
  calls_file="$tmpdir/calls"

  marker="$parent/.git/cbp-slice-done-feature_x"
  printf 'surface:7\nws1\n' > "$marker"

  out=$(cd "$wt" && CBP_PANE_BIN="$pane_bin" PANE_CALLS_FILE="$calls_file" PANE_MODE="reaped" \
    CMUX_WORKSPACE_ID="ws1" CMUX_SURFACE_ID="" "$HOOK" < /dev/null 2>/dev/null)
  rc=$?

  [ "$rc" -eq 0 ] && [ ! -f "$calls_file" ]
}

# T7: DISABLE_REAP_ON_STOP=1 / CMUX_WORKSPACE_ID unset → 무동작
t7_disabled_or_unset_ws_noop() {
  local parent tmpdir pane_bin calls_file marker out rc ok=1
  parent=$(setup_parent_repo)
  tmpdir=$(mktemp -d)
  pane_bin="$tmpdir/pane"; make_mock_pane "$pane_bin"
  calls_file="$tmpdir/calls"
  marker="$parent/.git/cbp-slice-done-feature_x"
  printf 'surface:7\nws1\n' > "$marker"

  out=$(cd "$parent" && CBP_PANE_BIN="$pane_bin" PANE_CALLS_FILE="$calls_file" PANE_MODE="reaped" \
    CMUX_WORKSPACE_ID="ws1" CMUX_SURFACE_ID="" DISABLE_REAP_ON_STOP=1 "$HOOK" < /dev/null 2>/dev/null)
  rc=$?
  { [ "$rc" -eq 0 ] && [ ! -f "$calls_file" ]; } || ok=0

  # 개발 머신은 실제 Orca 세션이라 CMUX_WORKSPACE_ID 만 unset 하면 ORCA_WORKSPACE_ID
  # 앰비언트로 kind=orca 로 샌다 — 진짜 "멀티플렉서 없음" 을 보려면 같이 지운다.
  out=$(cd "$parent" && env -u CMUX_WORKSPACE_ID -u ORCA_WORKSPACE_ID -u ORCA_TERMINAL_HANDLE -u TERM_PROGRAM \
    CBP_PANE_BIN="$pane_bin" PANE_CALLS_FILE="$calls_file" PANE_MODE="reaped" \
    "$HOOK" < /dev/null 2>/dev/null)
  rc=$?
  { [ "$rc" -eq 0 ] && [ ! -f "$calls_file" ]; } || ok=0

  [ "$ok" -eq 1 ]
}

# T8: marker 6개 → mock 호출 정확히 5회 (상한)
t8_cap_five_per_run() {
  local parent tmpdir pane_bin calls_file out rc i
  parent=$(setup_parent_repo)
  tmpdir=$(mktemp -d)
  pane_bin="$tmpdir/pane"; make_mock_pane "$pane_bin"
  calls_file="$tmpdir/calls"

  for i in 1 2 3 4 5 6; do
    printf 'surface:%s\nws1\n' "$i" > "$parent/.git/cbp-slice-done-feature_s$i"
  done

  out=$(cd "$parent" && CBP_PANE_BIN="$pane_bin" PANE_CALLS_FILE="$calls_file" PANE_MODE="reaped" \
    CMUX_WORKSPACE_ID="ws1" CMUX_SURFACE_ID="" "$HOOK" < /dev/null 2>/dev/null)
  rc=$?

  [ "$rc" -eq 0 ] && [ "$(wc -l < "$calls_file" | tr -d ' ')" = "5" ]
}

# T9: mock input-pending 모드 → marker 보존 + stdout JSON 에 input-pending 문구
t9_input_pending_marker_preserved() {
  local parent tmpdir pane_bin calls_file marker out rc msg
  parent=$(setup_parent_repo)
  tmpdir=$(mktemp -d)
  pane_bin="$tmpdir/pane"; make_mock_pane "$pane_bin"
  calls_file="$tmpdir/calls"
  marker="$parent/.git/cbp-slice-done-feature_x"
  printf 'surface:7\nws1\n' > "$marker"

  out=$(cd "$parent" && CBP_PANE_BIN="$pane_bin" PANE_CALLS_FILE="$calls_file" PANE_MODE="pending" \
    CMUX_WORKSPACE_ID="ws1" CMUX_SURFACE_ID="" "$HOOK" < /dev/null 2>/dev/null)
  rc=$?

  [ "$rc" -eq 0 ] || return 1
  [ -f "$marker" ] || return 1
  assert_json_one_line "$out" || return 1
  msg=$(printf '%s' "$out" | python3 -c "import json,sys; print(json.loads(sys.stdin.read())['systemMessage'])" 2>/dev/null)
  printf '%s' "$msg" | grep -q 'input-pending'
}

# T10: jq 부재(PATH 조작 서브셸) → stdout 빈 값 + exit 0
t10_jq_missing_degrades() {
  local parent tmpdir pane_bin calls_file marker out rc fakebin cmd p
  parent=$(setup_parent_repo)
  tmpdir=$(mktemp -d)
  pane_bin="$tmpdir/pane"; make_mock_pane "$pane_bin"
  calls_file="$tmpdir/calls"
  marker="$parent/.git/cbp-slice-done-feature_x"
  printf 'surface:7\nws1\n' > "$marker"

  fakebin=$(mktemp -d)
  for cmd in git sed grep printf dirname basename bash env wc; do
    p=$(command -v "$cmd" 2>/dev/null) && ln -sf "$p" "$fakebin/$cmd"
  done
  cp "$pane_bin" "$fakebin/pane"

  out=$(cd "$parent" && PATH="$fakebin" CBP_PANE_BIN="$fakebin/pane" PANE_CALLS_FILE="$calls_file" \
    PANE_MODE="reaped" CMUX_WORKSPACE_ID="ws1" CMUX_SURFACE_ID="" bash "$HOOK" < /dev/null 2>/dev/null)
  rc=$?

  [ "$rc" -eq 0 ] && [ -z "$out" ]
}

# T11: hooks.json / .claude/settings.json 배선 검증
t11_wiring_hooks_json() {
  python3 -c "
import json
d = json.load(open('$REPO/hooks/hooks.json'))
cmds = [h['command'] for blk in d['hooks']['Stop'] for h in blk['hooks']]
assert any('reap-on-stop.sh' in c for c in cmds), cmds
"
}

t12_wiring_settings_json() {
  python3 -c "
import json
d = json.load(open('$REPO/.claude/settings.json'))
cmds = [h['command'] for blk in d['hooks']['Stop'] for h in blk['hooks']]
assert any('reap-on-stop.sh' in c for c in cmds), cmds
"
}

# T13: mock 이 "reaped ... (pending-input 무시: ...)" 반환 (done-marker 가 pending 을 trump)
# → reaped 로 분류되고(보류로 오분류 안 됨) annotation 이 systemMessage 에 그대로 병기됨.
t13_marker_trumps_pending_annotated() {
  local parent tmpdir pane_bin calls_file marker out rc msg
  parent=$(setup_parent_repo)
  tmpdir=$(mktemp -d)
  pane_bin="$tmpdir/pane"; make_mock_pane "$pane_bin"
  calls_file="$tmpdir/calls"
  marker="$parent/.git/cbp-slice-done-feature_x"
  printf 'surface:7\nws1\n' > "$marker"

  out=$(cd "$parent" && CBP_PANE_BIN="$pane_bin" PANE_CALLS_FILE="$calls_file" PANE_MODE="reaped_annotated" \
    CMUX_WORKSPACE_ID="ws1" CMUX_SURFACE_ID="" "$HOOK" < /dev/null 2>/dev/null)
  rc=$?

  [ "$rc" -eq 0 ] || return 1
  assert_json_one_line "$out" || return 1
  msg=$(printf '%s' "$out" | python3 -c "import json,sys; print(json.loads(sys.stdin.read())['systemMessage'])" 2>/dev/null)
  printf '%s' "$msg" | grep -q 'reaped surface:7' || return 1
  printf '%s' "$msg" | grep -q 'push it'
}

run "T1 basic reap -> pane called + JSON 1-line stdout"    t1_basic_reap
run "T2 no marker -> noop"                                 t2_no_marker_noop
run "T3 line2=foreign ws -> skip"                          t3_foreign_ws_skip
run "T4 legacy 1-line marker -> handled"                   t4_legacy_one_line_marker
run "T5 blank line1 / self-surface -> skip"                t5_blank_and_self_surface_skip
run "T6 child worktree cwd -> noop"                        t6_child_worktree_noop
run "T7 DISABLE / unset CMUX_WORKSPACE_ID -> noop"          t7_disabled_or_unset_ws_noop
run "T8 6 markers -> capped at 5 calls"                     t8_cap_five_per_run
run "T9 input-pending -> marker kept + JSON mentions it"    t9_input_pending_marker_preserved
run "T10 jq missing -> empty stdout, exit 0"                t10_jq_missing_degrades
run "T11 hooks.json wiring"                                 t11_wiring_hooks_json
run "T12 settings.json wiring"                              t12_wiring_settings_json
run "T13 reaped w/ pending-input annotation -> reaped classified + annotation in msg" t13_marker_trumps_pending_annotated

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && echo "✅ all pass" || { echo "❌ FAILED: ${FAILED[*]}"; exit 1; }
