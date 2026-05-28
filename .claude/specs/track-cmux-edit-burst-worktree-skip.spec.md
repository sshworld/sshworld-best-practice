# Spec — track-cmux-edit-burst.sh 자식 worktree skip (S1)

## Context (자식 implementor 용)

cmux 환경에서 `.claude/hooks/track-cmux-edit-burst.sh` 가 워크스페이스 단위 카운터로 작동.
부모 + 자식 (worktree dispatch 받은 implementor) 가 같은 workspace ID 공유 → 카운터 공유 → 자식 Edit 누적 시 strict 차단 = false-positive.

자식은 이미 dispatch 안 surface 에서 작업 중. "dispatch 강제" 의미 없음. → **자식 worktree 환경 감지 시 skip** 필요.

자식 worktree 감지: `git rev-parse --git-dir` (worktree 안에선 `<repo>/.git/worktrees/<slug>`) vs `--git-common-dir` (`<repo>/.git`). 두 값 다름 = 자식 worktree.

## 산출 파일

- `.claude/hooks/track-cmux-edit-burst.sh` (line 12 다음에 skip 로직 추가)
- `tests/track_cmux_edit_burst_strict_default.sh` (신규 시나리오 2건 추가)

## ⚠️ 자식 작업 순서 주의

본 작업은 자식이 hook 자체를 수정. 자식의 첫 Edit (hook 수정) 후 즉시 새 로직 적용 → 두 번째 Edit (test 수정) 부터 자동 skip 받음.

순서 권장:
1. **첫 Edit**: `.claude/hooks/track-cmux-edit-burst.sh` 수정 (counter 1 → strict 임계치 2 미달 → advisory only 통과)
2. **두 번째 Edit**: `tests/track_cmux_edit_burst_strict_default.sh` 수정 (자식 worktree 감지 skip 적용 → 통과)

만약 첫 Edit 도 차단되는 경우 (counter 가 carry-over): `SKIP_CMUX_EDIT_BURST=1` env 1회 우회.

## 구현 명세

### A. hook 수정

line 12 (`[ -z "${CMUX_WORKSPACE_ID:-}" ] && exit 0`) 다음에 추가:

```bash
# 자식 worktree 환경 감지 — false-positive 회피
# git-dir != git-common-dir 이면 worktree 안 (자식 dispatch surface). 자식은 이미 dispatch 안에서
# 작업 중이므로 hook 의 'dispatch 강제' 의미 없음 → skip.
GIT_DIR=$(git rev-parse --git-dir 2>/dev/null || true)
GIT_COMMON=$(git rev-parse --git-common-dir 2>/dev/null || true)
if [ -n "$GIT_DIR" ] && [ -n "$GIT_COMMON" ] && [ "$GIT_DIR" != "$GIT_COMMON" ]; then
  exit 0
fi
```

### B. test 신규 시나리오 2건

`tests/track_cmux_edit_burst_strict_default.sh` 마지막 `echo "PASS=$PASS FAIL=$FAIL"` 줄 앞에 추가:

```bash
t_hook_skips_in_child_worktree() {
  # tmp 디렉토리에 fake worktree 구조 만들고 hook 가 거기서 skip 하는지 확인
  local tmp=$(mktemp -d)
  local fake_repo=$tmp/repo
  mkdir -p $fake_repo
  git -C $fake_repo init -q
  git -C $fake_repo commit --allow-empty -q -m init 2>/dev/null
  git -C $fake_repo worktree add -q $tmp/child 2>/dev/null
  # hook 호출 - 자식 worktree 안에서
  local before_count=0
  local count_file=$tmp/burst.count
  echo $before_count > $count_file
  # PAYLOAD = Edit tool
  local payload='{"tool_name":"Edit"}'
  CMUX_WORKSPACE_ID=test-ws \
  CBP_BURST_FILE=$count_file \
  CMUX_EDIT_BURST_STRICT=1 \
    bash -c "cd $tmp/child && printf '%s' '$payload' | $REPO/.claude/hooks/track-cmux-edit-burst.sh"
  local exit_code=$?
  local after_count=$(cat $count_file)
  rm -rf $tmp
  # exit 0 + counter 증가 안 됨
  [ "$exit_code" = "0" ] && [ "$after_count" = "0" ]
}

t_hook_active_in_main_worktree() {
  # 부모 main worktree (git-dir == git-common-dir) 에서 hook 정상 작동
  local tmp=$(mktemp -d)
  local fake_repo=$tmp/repo
  mkdir -p $fake_repo
  git -C $fake_repo init -q
  git -C $fake_repo commit --allow-empty -q -m init 2>/dev/null
  local count_file=$tmp/burst.count
  echo 1 > $count_file  # 이미 1
  local payload='{"tool_name":"Edit"}'
  CMUX_WORKSPACE_ID=test-ws \
  CBP_BURST_FILE=$count_file \
  CMUX_EDIT_BURST_STRICT=1 \
    bash -c "cd $fake_repo && printf '%s' '$payload' | $REPO/.claude/hooks/track-cmux-edit-burst.sh" 2>/dev/null
  local exit_code=$?
  local after_count=$(cat $count_file)
  rm -rf $tmp
  # 부모: counter 증가 후 임계치 2 도달 → strict 차단 (exit 2)
  [ "$exit_code" = "2" ] && [ "$after_count" = "2" ]
}

run "자식 worktree 안에서 hook skip (exit 0 + counter 증가 안 함)" t_hook_skips_in_child_worktree
run "부모 main worktree 에서 hook 정상 작동 (회귀 없음)" t_hook_active_in_main_worktree
```

## TDD Red → Green

### Red (현재)
```bash
grep -qE "(git-common-dir|worktree)" .claude/hooks/track-cmux-edit-burst.sh  # 0 (없음)
bash tests/track_cmux_edit_burst_strict_default.sh > /dev/null  # 3 PASS (기존만)
```

### Green
```bash
grep -qE "(git-common-dir|worktree)" .claude/hooks/track-cmux-edit-burst.sh  # 매치
bash tests/track_cmux_edit_burst_strict_default.sh > /dev/null  # 5 PASS (기존 3 + 신규 2)
```

## 자식이 끝나기 전 verification

```bash
set -e
grep -qE "(git-common-dir|worktree)" .claude/hooks/track-cmux-edit-burst.sh
bash tests/track_cmux_edit_burst_strict_default.sh
[ "$(grep -c '^run' tests/track_cmux_edit_burst_strict_default.sh)" -eq 5 ]
echo "✅ all green"
```

자식 응답 마지막에 `✅` 출력.
