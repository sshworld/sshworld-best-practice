#!/usr/bin/env bash
# orca_worktree_mode.sh — S6 orca 워크트리 카드 모드 계약 테스트.
#
# ⚠️ 실제 orca 를 절대 호출하지 않는다 — tmpdir 에 fake orca 스크립트를 만들고
# ORCA_BIN 으로 override 한다. 개발 머신 자체가 실제 Orca 세션이므로 매 케이스에서
# ORCA_*/TERM_PROGRAM/TMUX/CMUX_* 를 scrub 한다.
export SKIP_CMUX_REAP=1
export SKIP_PLAN_DEV_CMUX_CLEANUP=1

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WRAPPER="$REPO/scripts/orca-pane.sh"
DISPATCH="$REPO/scripts/dispatch-slice-pane.sh"

step() { echo ""; echo "[$1] $2"; }
fail() { echo "❌ FAIL: $1" >&2; exit 1; }

[ -x "$WRAPPER" ] || fail "$WRAPPER 없음 또는 실행권한 없음"
[ -f "$DISPATCH" ] || fail "$DISPATCH 없음"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# repoId="repo1", kind 는 env ORCA_FAKE_REPO_KIND 로 제어. worktree create 는
# ORCA_FAKE_WT_CREATE_OK=false 로 실패(ok:false) 시뮬레이션 가능.
# 모든 받은 인자를 ORCA_FAKE_ARGS_LOG 에 한 줄로 기록 (--comment 검증용).
make_fake_orca() {
  local dir="$1"
  cat > "$dir/orca" <<'MOCKEOF'
#!/usr/bin/env bash
if [ -n "${ORCA_FAKE_ARGS_LOG:-}" ]; then
  printf '%s\n' "$*" >> "$ORCA_FAKE_ARGS_LOG"
fi

group="${1:-}"; action="${2:-}"

# 실제 orca CLI 의 미지-플래그 거부를 흉내낸다.
# 목이 아무 플래그나 받아주면 "실재하지 않는 플래그" 계열 버그를 영영 못 잡는다 —
# 실제로 `worktree create --workspace-status` (worktree set 전용 플래그)가 이 방식으로
# 계약 테스트를 전부 통과한 뒤 라이브에서 `Unknown flag` 로 죽었다.
# 서브커맨드별 허용 플래그는 실제 `orca <sub> --help` 의 Usage 줄에서 옮겨온 것.
_allowed=""
case "$group $action" in
  "worktree create") _allowed="--repo --name --project --host --project-host-setup --agent --prompt --setup --base-branch --issue --linear-issue --comment --parent-worktree --no-parent --run-hooks --activate --json" ;;
  "worktree set")    _allowed="--worktree --display-name --issue --linear-issue --comment --workspace-status --parent-worktree --no-parent --json" ;;
  "worktree current"|"worktree list") _allowed="--repo --limit --json" ;;
  "terminal create") _allowed="--worktree --title --command --focus --json" ;;
  "terminal send")   _allowed="--terminal --text --enter --interrupt --json" ;;
  "terminal read")   _allowed="--terminal --cursor --limit --json" ;;
  "terminal wait")   _allowed="--for --terminal --timeout-ms --json" ;;
  "terminal show"|"terminal close") _allowed="--terminal --tab --json" ;;
  "terminal list")   _allowed="--worktree --limit --json" ;;
  "repo list"|"repo add") _allowed="--path --json" ;;
esac
if [ -n "$_allowed" ]; then
  for _a in "$@"; do
    case "$_a" in
      --*)
        case " $_allowed " in
          *" $_a "*) ;;
          *) printf '{"id":"local","ok":false,"error":{"code":"invalid_argument","message":"Unknown flag %s for command: %s %s"}}\n' "$_a" "$group" "$action"; exit 0 ;;
        esac ;;
    esac
  done
fi

case "$group $action" in
  "worktree current")
    printf '{"id":"1","ok":true,"result":{"worktree":{"repoId":"repo1","path":"/parent","id":"repo1::/parent"}}}\n'
    exit 0
    ;;
  "repo list")
    kind="${ORCA_FAKE_REPO_KIND:-git}"
    if [ "$kind" = "missing" ]; then
      printf '{"id":"1","ok":true,"result":{"repos":[]}}\n'
    else
      printf '{"id":"1","ok":true,"result":{"repos":[{"id":"repo1","path":"/parent","kind":"%s"}]}}\n' "$kind"
    fi
    exit 0
    ;;
  "repo add")
    echo "FAKE_ORCA: repo add 호출됨 — 절대 금지된 동작" >&2
    printf '{"id":"1","ok":false,"error":{"code":"forbidden","message":"repo add must never be called"}}\n'
    exit 0
    ;;
  "worktree create")
    if [ "${ORCA_FAKE_WT_CREATE_OK:-true}" != "true" ]; then
      printf '{"id":"1","ok":false,"error":{"code":"boom","message":"worktree create boom"}}\n'
      exit 0
    fi
    handle_field="${ORCA_FAKE_WT_HANDLE_FIELD:-agentTerminalHandle}"
    handle="${ORCA_FAKE_WT_HANDLE:-term_wt_abc}"
    case "$handle_field" in
      agentTerminalHandle)
        printf '{"id":"1","ok":true,"result":{"worktree":{"id":"repo1::/new","path":"/parent/.worktrees/x","branch":"shsong/feature-x"},"agentTerminalHandle":"%s"}}\n' "$handle"
        ;;
      startupTerminal)
        printf '{"id":"1","ok":true,"result":{"worktree":{"id":"repo1::/new","path":"/parent/.worktrees/x","branch":"shsong/feature-x"},"startupTerminal":{"handle":"%s"}}}\n' "$handle"
        ;;
      none)
        printf '{"id":"1","ok":true,"result":{"worktree":{"id":"repo1::/new","path":"/parent/.worktrees/x","branch":"shsong/feature-x"}}}\n'
        ;;
    esac
    exit 0
    ;;
  "terminal list")
    list="${ORCA_FAKE_LIST_JSON:-[]}"
    printf '{"id":"1","ok":true,"result":{"terminals":%s}}\n' "$list"
    exit 0
    ;;
  "terminal create")
    handle="${ORCA_FAKE_TAB_HANDLE:-term_tab_xyz}"
    printf '{"id":"1","ok":true,"result":{"terminal":{"handle":"%s"}}}\n' "$handle"
    exit 0
    ;;
  "terminal send")
    printf '{"id":"1","ok":true,"result":{"send":{"accepted":true,"bytesWritten":1}}}\n'
    exit 0
    ;;
  *)
    printf '{"id":"1","ok":false,"error":{"code":"unknown_command"}}\n'
    exit 0
    ;;
esac
MOCKEOF
  chmod +x "$dir/orca"
  echo "$dir/orca"
}

# 공통 env scrub — 개발 머신이 실제 Orca 세션이라 ORCA_*/TERM_PROGRAM/TMUX/CMUX_* 오염 방지.
scrub_env() {
  env -u TMUX -u CMUX_WORKSPACE_ID -u CMUX_SURFACE_ID -u CMUX_SOCKET -u CMUX_SOCKET_PASSWORD \
      -u ORCA_TERMINAL_HANDLE -u ORCA_WORKSPACE_ID -u TERM_PROGRAM "$@"
}

# ============================================================================
step 1 "kind=git → launch --worktree-mode 가 worktree create 호출, stdout=term_* 단일 토큰"
d1="$TMP/c1"; mkdir -p "$d1"
orca1=$(make_fake_orca "$d1")
argslog1="$d1/args.log"; : > "$argslog1"

out1=$(scrub_env ORCA_BIN="$orca1" ORCA_FAKE_REPO_KIND=git ORCA_FAKE_ARGS_LOG="$argslog1" \
  "$WRAPPER" launch --worktree-mode --name=slice-x 2>"$d1/err")
rc1=$?
[ "$rc1" -eq 0 ] || fail "launch(--worktree-mode, git) 실패 rc=$rc1 stderr=$(cat "$d1/err")"
[ "$out1" = "term_wt_abc" ] || fail "stdout 불일치: '$out1'"
lines1=$(printf '%s\n' "$out1" | wc -l | tr -d ' ')
[ "$lines1" -eq 1 ] || fail "stdout 이 한 줄이 아님 (lines=$lines1)"
case "$out1" in
  *[[:space:]]*) fail "stdout 에 공백 포함: '$out1'" ;;
esac
grep -q '^worktree create' "$argslog1" || fail "worktree create 호출 안 됨: $(cat "$argslog1")"
echo "ok: launch(--worktree-mode, git-kind) → $out1"

# ============================================================================
step 2 "같은 상황에서 stderr 에 worktree=<path> / branch=<branch> 각 1줄"
grep -qx 'worktree=/parent/.worktrees/x' "$d1/err" || fail "stderr 에 worktree= 없음: $(cat "$d1/err")"
grep -qx 'branch=shsong/feature-x' "$d1/err" || fail "stderr 에 branch= 없음: $(cat "$d1/err")"
echo "ok: stderr worktree=/branch= 확인"

# ============================================================================
step 3 "kind=folder → worktree create 호출 안 함, 탭 모드 폴백, exit0, stdout=term_*, 폴백사유 stderr"
d3="$TMP/c3"; mkdir -p "$d3"
orca3=$(make_fake_orca "$d3")
argslog3="$d3/args.log"; : > "$argslog3"

out3=$(scrub_env ORCA_BIN="$orca3" ORCA_FAKE_REPO_KIND=folder ORCA_FAKE_ARGS_LOG="$argslog3" \
  ORCA_FAKE_TAB_HANDLE=term_tabfallback \
  "$WRAPPER" launch --worktree-mode --name=slice-y 2>"$d3/err")
rc3=$?
[ "$rc3" -eq 0 ] || fail "launch(--worktree-mode, folder) 실패 rc=$rc3 stderr=$(cat "$d3/err")"
[ "$out3" = "term_tabfallback" ] || fail "stdout 불일치(탭 폴백): '$out3'"
case "$out3" in
  term_*) : ;;
  *) fail "탭 폴백 stdout 이 term_ 로 시작 안 함: '$out3'" ;;
esac
grep -q '^worktree create' "$argslog3" && fail "folder-kind 인데 worktree create 가 호출됨"
[ -s "$d3/err" ] || fail "폴백 사유 stderr 없음"
echo "ok: launch(--worktree-mode, folder-kind) → 탭 폴백 $out3, stderr=$(cat "$d3/err")"

# ============================================================================
step 4 "worktree create 가 ok:false(exit0) → wrapper 는 실패(비0) 판정"
d4="$TMP/c4"; mkdir -p "$d4"
orca4=$(make_fake_orca "$d4")

# 전제: fake orca 자체는 exit0 인데 ok:false 인지 확인
ORCA_FAKE_WT_CREATE_OK=false "$orca4" worktree create --repo id:repo1 --name z --json >/dev/null 2>&1
[ $? -eq 0 ] || fail "전제 실패: fake orca 가 ok:false 인데 exit0 아님"

set +e
out4=$(scrub_env ORCA_BIN="$orca4" ORCA_FAKE_REPO_KIND=git ORCA_FAKE_WT_CREATE_OK=false \
  "$WRAPPER" launch --worktree-mode --name=slice-z 2>"$d4/err")
rc4=$?
set -e
[ "$rc4" -ne 0 ] || fail "worktree create ok:false(exit0) 인데 wrapper 가 성공(rc0) 처리함: stdout='$out4'"
echo "ok: worktree create ok:false → wrapper rc=$rc4 (비0)"

# ============================================================================
step 5 "agentTerminalHandle 없고 startupTerminal.handle 만 있음 → 그 핸들 사용"
d5="$TMP/c5"; mkdir -p "$d5"
orca5=$(make_fake_orca "$d5")

out5=$(scrub_env ORCA_BIN="$orca5" ORCA_FAKE_REPO_KIND=git \
  ORCA_FAKE_WT_HANDLE_FIELD=startupTerminal ORCA_FAKE_WT_HANDLE=term_startup1 \
  "$WRAPPER" launch --worktree-mode --name=slice-s 2>"$d5/err")
rc5=$?
[ "$rc5" -eq 0 ] || fail "startupTerminal 케이스 실패 rc=$rc5 stderr=$(cat "$d5/err")"
[ "$out5" = "term_startup1" ] || fail "startupTerminal.handle 미사용: '$out5'"
echo "ok: agentTerminalHandle 없음 → startupTerminal.handle 사용"

# 5-b: 둘 다 없음 → terminal list 로 찾음
d5b="$TMP/c5b"; mkdir -p "$d5b"
orca5b=$(make_fake_orca "$d5b")

out5b=$(scrub_env ORCA_BIN="$orca5b" ORCA_FAKE_REPO_KIND=git \
  ORCA_FAKE_WT_HANDLE_FIELD=none \
  ORCA_FAKE_LIST_JSON='[{"handle":"term_fromlist","title":"x"}]' \
  "$WRAPPER" launch --worktree-mode --name=slice-l 2>"$d5b/err")
rc5b=$?
[ "$rc5b" -eq 0 ] || fail "terminal list 폴백 실패 rc=$rc5b stderr=$(cat "$d5b/err")"
[ "$out5b" = "term_fromlist" ] || fail "terminal list 핸들 미사용: '$out5b'"
echo "ok: 둘 다 없음 → terminal list 로 발견"

# 5-c: 셋 다 없음 → die
d5c="$TMP/c5c"; mkdir -p "$d5c"
orca5c=$(make_fake_orca "$d5c")

set +e
out5c=$(scrub_env ORCA_BIN="$orca5c" ORCA_FAKE_REPO_KIND=git \
  ORCA_FAKE_WT_HANDLE_FIELD=none ORCA_FAKE_LIST_JSON='[]' \
  "$WRAPPER" launch --worktree-mode --name=slice-n 2>"$d5c/err")
rc5c=$?
set -e
[ "$rc5c" -ne 0 ] || fail "핸들 3중 폴백 모두 실패인데 wrapper 가 성공(rc0): '$out5c'"
echo "ok: 핸들 3중 폴백 모두 실패 → die (rc=$rc5c)"

# ============================================================================
step 6 "--worktree-mode 없이 launch → worktree create 절대 호출 안 함 (회귀 가드)"
d6="$TMP/c6"; mkdir -p "$d6"
orca6=$(make_fake_orca "$d6")
argslog6="$d6/args.log"; : > "$argslog6"

out6=$(scrub_env ORCA_BIN="$orca6" ORCA_FAKE_ARGS_LOG="$argslog6" ORCA_FAKE_TAB_HANDLE=term_plain \
  "$WRAPPER" launch 2>"$d6/err")
rc6=$?
[ "$rc6" -eq 0 ] || fail "일반 launch 실패 rc=$rc6 stderr=$(cat "$d6/err")"
[ "$out6" = "term_plain" ] || fail "일반 launch stdout 불일치: '$out6'"
grep -q '^worktree create' "$argslog6" && fail "--worktree-mode 없는데 worktree create 호출됨"
grep -q '^worktree current' "$argslog6" && fail "--worktree-mode 없는데 worktree current 호출됨"
echo "ok: --worktree-mode 없음 → worktree 관련 호출 전혀 없음"

# ============================================================================
step 7 "dispatch: DISPATCH_DRY_RUN=1 + orca + git-kind → worktree_mode=orca"
d7="$TMP/c7"; mkdir -p "$d7"
orca7=$(make_fake_orca "$d7")
echo "spec body" > "$d7/spec.md"

out7=$(scrub_env ORCA_BIN="$orca7" ORCA_FAKE_REPO_KIND=git \
  DISPATCH_DRY_RUN=1 DISPATCH_SKIP_CLEANUP=1 \
  "$DISPATCH" --slice=orca-wt-test --spec-file="$d7/spec.md" --mode=orca 2>"$d7/err")
rc7=$?
[ "$rc7" -eq 0 ] || fail "dispatch dry-run(git-kind) 실패 rc=$rc7 stderr=$(cat "$d7/err")"
wm7=$(printf '%s' "$out7" | python3 -c "import json,sys; print(json.loads(sys.stdin.read().strip().splitlines()[-1]).get('worktree_mode',''))")
[ "$wm7" = "orca" ] || fail "expected worktree_mode=orca, got '$wm7' (out=$out7)"
echo "ok: dispatch dry-run(orca+git-kind) → worktree_mode=orca"

# ============================================================================
step 8 "dispatch: DISPATCH_DRY_RUN=1 + orca + folder-kind → worktree_mode=git"
d8="$TMP/c8"; mkdir -p "$d8"
orca8=$(make_fake_orca "$d8")
echo "spec body" > "$d8/spec.md"

out8=$(scrub_env ORCA_BIN="$orca8" ORCA_FAKE_REPO_KIND=folder \
  DISPATCH_DRY_RUN=1 DISPATCH_SKIP_CLEANUP=1 \
  "$DISPATCH" --slice=orca-wt-test --spec-file="$d8/spec.md" --mode=orca 2>"$d8/err")
rc8=$?
[ "$rc8" -eq 0 ] || fail "dispatch dry-run(folder-kind) 실패 rc=$rc8 stderr=$(cat "$d8/err")"
wm8=$(printf '%s' "$out8" | python3 -c "import json,sys; print(json.loads(sys.stdin.read().strip().splitlines()[-1]).get('worktree_mode',''))")
[ "$wm8" = "git" ] || fail "expected worktree_mode=git, got '$wm8' (out=$out8)"
echo "ok: dispatch dry-run(orca+folder-kind) → worktree_mode=git"

# ============================================================================
step 9 "dispatch: ORCA_WORKTREE_MODE=0 → git-kind 여도 worktree_mode=git"
d9="$TMP/c9"; mkdir -p "$d9"
orca9=$(make_fake_orca "$d9")
echo "spec body" > "$d9/spec.md"

out9=$(scrub_env ORCA_BIN="$orca9" ORCA_FAKE_REPO_KIND=git ORCA_WORKTREE_MODE=0 \
  DISPATCH_DRY_RUN=1 DISPATCH_SKIP_CLEANUP=1 \
  "$DISPATCH" --slice=orca-wt-test --spec-file="$d9/spec.md" --mode=orca 2>"$d9/err")
rc9=$?
[ "$rc9" -eq 0 ] || fail "dispatch dry-run(ORCA_WORKTREE_MODE=0) 실패 rc=$rc9 stderr=$(cat "$d9/err")"
wm9=$(printf '%s' "$out9" | python3 -c "import json,sys; print(json.loads(sys.stdin.read().strip().splitlines()[-1]).get('worktree_mode',''))")
[ "$wm9" = "git" ] || fail "expected worktree_mode=git(ORCA_WORKTREE_MODE=0), got '$wm9' (out=$out9)"
echo "ok: ORCA_WORKTREE_MODE=0 → worktree_mode=git (기능 전체 off)"

# ============================================================================
step 10 "dispatch: --mode=cmux / --mode=tmux → worktree_mode=git (회귀 가드)"
d10="$TMP/c10"; mkdir -p "$d10"
echo "spec body" > "$d10/spec.md"

out10c=$(scrub_env DISPATCH_DRY_RUN=1 DISPATCH_SKIP_CLEANUP=1 \
  "$DISPATCH" --slice=orca-wt-test --spec-file="$d10/spec.md" --mode=cmux 2>"$d10/err_c")
rc10c=$?
[ "$rc10c" -eq 0 ] || fail "dispatch dry-run(--mode=cmux) 실패 rc=$rc10c stderr=$(cat "$d10/err_c")"
wm10c=$(printf '%s' "$out10c" | python3 -c "import json,sys; print(json.loads(sys.stdin.read().strip().splitlines()[-1]).get('worktree_mode',''))")
[ "$wm10c" = "git" ] || fail "--mode=cmux 인데 worktree_mode='$wm10c' (기대: git)"

out10t=$(scrub_env DISPATCH_DRY_RUN=1 DISPATCH_SKIP_CLEANUP=1 \
  "$DISPATCH" --slice=orca-wt-test --spec-file="$d10/spec.md" --mode=tmux 2>"$d10/err_t")
rc10t=$?
[ "$rc10t" -eq 0 ] || fail "dispatch dry-run(--mode=tmux) 실패 rc=$rc10t stderr=$(cat "$d10/err_t")"
wm10t=$(printf '%s' "$out10t" | python3 -c "import json,sys; print(json.loads(sys.stdin.read().strip().splitlines()[-1]).get('worktree_mode',''))")
[ "$wm10t" = "git" ] || fail "--mode=tmux 인데 worktree_mode='$wm10t' (기대: git)"
echo "ok: cmux/tmux → worktree_mode=git 회귀 없음"

# ============================================================================
step 11 "--worktree-mode 로 만들 때 worktree create 인자에 --comment <slice> 포함"
d11="$TMP/c11"; mkdir -p "$d11"
orca11=$(make_fake_orca "$d11")
argslog11="$d11/args.log"; : > "$argslog11"

scrub_env ORCA_BIN="$orca11" ORCA_FAKE_REPO_KIND=git ORCA_FAKE_ARGS_LOG="$argslog11" \
  "$WRAPPER" launch --worktree-mode --name=my-slice-name >/dev/null 2>"$d11/err"

wt_create_line=$(grep '^worktree create' "$argslog11" || true)
[ -n "$wt_create_line" ] || fail "worktree create 호출 기록 없음"
printf '%s' "$wt_create_line" | grep -q -- '--comment my-slice-name' \
  || fail "worktree create 인자에 --comment my-slice-name 없음: $wt_create_line"
echo "ok: worktree create 인자에 --comment 포함 확인"

# ============================================================================
step 12 "현재 repo 가 orca 에 미등록(repo list 에 없음) → 탭 폴백, repo add 절대 호출 안 함"
d12="$TMP/c12"; mkdir -p "$d12"
orca12=$(make_fake_orca "$d12")
argslog12="$d12/args.log"; : > "$argslog12"

out12=$(scrub_env ORCA_BIN="$orca12" ORCA_FAKE_REPO_KIND=missing ORCA_FAKE_ARGS_LOG="$argslog12" \
  ORCA_FAKE_TAB_HANDLE=term_unregfallback \
  "$WRAPPER" launch --worktree-mode --name=slice-unreg 2>"$d12/err")
rc12=$?
[ "$rc12" -eq 0 ] || fail "미등록 repo 케이스 실패 rc=$rc12 stderr=$(cat "$d12/err")"
[ "$out12" = "term_unregfallback" ] || fail "미등록 repo 탭 폴백 stdout 불일치: '$out12'"
grep -q '^worktree create' "$argslog12" && fail "미등록 repo 인데 worktree create 가 호출됨"
grep -q '^repo add' "$argslog12" && fail "미등록 repo 인데 repo add 가 호출됨 (절대 금지)"
echo "ok: 미등록 repo → 탭 폴백, repo add 미호출 확인"

# ============================================================================
step 13 "worktree create 에 실재하지 않는 플래그를 보내지 않는다 (Unknown flag 회귀 가드)"

# 2026-08-31 실측 회귀: --workspace-status 는 `worktree set` 전용인데 `worktree create` 에
# 붙어 있었다. 가짜 orca 가 아무 플래그나 받아줘 계약 테스트 12개가 전부 통과했고,
# 실제 orca 에서만 `Unknown flag --workspace-status for command: worktree create` 로 죽었다.
# 이제 목이 실제 CLI 처럼 미지 플래그를 거부하므로, 잘못된 플래그가 다시 들어오면
# worktree create 가 ok:false 를 반환해 launch 가 비0 으로 끝난다.
d13="$TMP/c13"; mkdir -p "$d13"
orca13=$(make_fake_orca "$d13")
argslog13="$d13/args.log"; : > "$argslog13"
set +e
out13=$(scrub_env ORCA_BIN="$orca13" ORCA_FAKE_ARGS_LOG="$argslog13" \
  ORCA_FAKE_REPO_KIND=git \
  "$WRAPPER" launch --worktree-mode --name=slice-flag 2>"$d13/err")
rc13=$?
set -e
[ "$rc13" -eq 0 ] || fail "정상 플래그만 쓰는데 launch 가 실패했다 rc=$rc13 stderr=$(cat "$d13/err" 2>/dev/null)"
[ "${out13#term_}" != "$out13" ] || fail "stdout 이 term_* 가 아님: '$out13'"

# 실제로 보낸 create 인자에 --workspace-status 가 없어야 한다 (원인 자체를 고정)
create_line=$(grep '^worktree create' "$argslog13" | head -1)
case "$create_line" in
  *--workspace-status*) fail "worktree create 에 --workspace-status 가 다시 들어갔다: $create_line" ;;
esac
# 목이 실제로 미지 플래그를 거부하는지 (가드 자체가 살아있는지) 확인
probe=$("$orca13" worktree create --repo id:x --bogus-flag v --json 2>/dev/null)
case "$probe" in
  *"Unknown flag --bogus-flag"*) ;;
  *) fail "가짜 orca 의 미지-플래그 거부가 동작하지 않는다 — 이 가드는 무의미해진다: $probe" ;;
esac
echo "ok: create 인자에 미지 플래그 없음 + 목의 거부 가드 동작 확인"

# ============================================================================
echo ""
echo "✅ orca_worktree_mode: 13개 케이스 모두 PASS"
