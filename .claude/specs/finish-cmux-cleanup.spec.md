# Spec — finish-plan-dev.sh cmux cleanup 자동화 (S3)

## 목적

`finish-plan-dev.sh` 가 push 성공 직후 cmux 자식 surface 를 자동 close. 사용자 수동 명령 0 — 작업 끝난 surface (`cbp-*`, state file surfaces) 가 자동 정리.

## 산출 파일

1. `scripts/finish-plan-dev.sh` — push 성공 후 cleanup 호출 추가
2. `tests/finish_plan_dev_cmux_cleanup.test.sh` — 신규 테스트

## 1. `scripts/finish-plan-dev.sh` 수정

기존 push 성공 분기:
- Develop case L209~211 (`if ${GIT_PUSH_CMD} ... ; then clear_marker; echo "pushed: ..."`)
- Main-only case L234~236 (`if ${GIT_PUSH_CMD} ... ; then clear_marker; echo "pushed: ..."`)

`clear_marker` 호출 직전에 cmux cleanup 헬퍼 호출:

상단 (L20 근처, GIT_PUSH_CMD 변수 정의 뒤) 추가:
```bash
CMUX_PANE_BIN="${CMUX_PANE_BIN:-$SCRIPT_DIR/cmux-pane.sh}"
```

`clear_marker()` 함수 위 (L147 위) 추가:
```bash
# ── cmux cleanup 헬퍼 (S3) ────────────────────────────────────────
do_cmux_cleanup() {
  if [ "${SKIP_PLAN_DEV_CMUX_CLEANUP:-0}" = "1" ]; then
    echo "cmux cleanup skipped (SKIP_PLAN_DEV_CMUX_CLEANUP=1)" >&2
    return 0
  fi
  if [ "${DISABLE_PLAN_DEV_CMUX_CLEANUP:-0}" = "1" ]; then
    echo "cmux cleanup disabled (DISABLE_PLAN_DEV_CMUX_CLEANUP=1)" >&2
    return 0
  fi
  if [ -z "${CMUX_WORKSPACE_ID:-}" ]; then
    return 0  # cmux 환경 아님
  fi
  if [ ! -x "$CMUX_PANE_BIN" ]; then
    echo "cmux-pane.sh 부재 — cleanup skip" >&2
    return 0
  fi
  echo "finish-plan-dev: cmux 자식 surface cleanup 실행" >&2
  "$CMUX_PANE_BIN" cleanup 2>&1 | sed 's/^/  /' >&2 || true
}
```

`clear_marker` 호출 직전에 `do_cmux_cleanup` 호출:

L210 직전 (develop case):
```bash
if ${GIT_PUSH_CMD} -u "$REMOTE" "$FINAL_BRANCH"; then
  do_cmux_cleanup
  clear_marker
  echo "pushed: $FINAL_BRANCH → $REMOTE (base=develop)"
```

L234 직전 (main-only case):
```bash
if ${GIT_PUSH_CMD} "$REMOTE" "$CUR_BRANCH"; then
  do_cmux_cleanup
  clear_marker
  echo "pushed: $CUR_BRANCH → $REMOTE (no develop)"
```

## 우회 env

- `SKIP_PLAN_DEV_CMUX_CLEANUP=1` — 1회 우회 (cleanup skip)
- `DISABLE_PLAN_DEV_CMUX_CLEANUP=1` — 영구 비활성

CMUX_WORKSPACE_ID unset 시는 자동 skip (cmux 환경 아님).

## 2. `tests/finish_plan_dev_cmux_cleanup.test.sh`

mock 전략:
- `CMUX_PANE_BIN` env 로 mock script 주입 → 호출 횟수 기록
- `GIT_PUSH_CMD` env 로 fake push (e.g. `true`)
- 가짜 marker 파일 + 가짜 work_branch

테스트 시나리오:
1. **CMUX_WORKSPACE_ID set + 모든 우회 unset → mock cmux-pane.sh cleanup 호출됨**
2. **CMUX_WORKSPACE_ID unset → cleanup 호출 안 됨** (cmux 환경 아님)
3. **SKIP_PLAN_DEV_CMUX_CLEANUP=1 → cleanup 호출 안 됨**
4. **DISABLE_PLAN_DEV_CMUX_CLEANUP=1 → cleanup 호출 안 됨**
5. **CMUX_PANE_BIN 부재 (mock executable 없음) → graceful skip + push 성공**
6. **push 실패 시 cleanup 호출 안 됨** (push 실패 분기에서 cleanup 호출 X)

테스트 fixture:
```bash
setup_fixture() {
  local tmp=$(mktemp -d)
  local repo=$tmp/repo
  mkdir -p $repo
  git -C $repo init -q -b main
  git -C $repo commit --allow-empty -q -m init
  mkdir -p $repo/.git
  cat > $repo/.git/plan-dev-session.json <<JEOF
{
  "start_ref": "$(git -C $repo rev-parse HEAD)",
  "base_branch": "main",
  "work_branch": "main",
  "start_ts": "2026-05-28T00:00:00Z",
  "start_pid": 1,
  "auto_branch": false
}
JEOF
  git -C $repo commit --allow-empty -q -m "test commit"
  echo $tmp
}

mock_cmux_pane() {
  local tmp=$1
  local mock=$tmp/cmux-pane-mock.sh
  local log=$tmp/cmux-pane.log
  cat > $mock <<MEOF
#!/bin/bash
echo "called with: \$*" >> $log
exit 0
MEOF
  chmod +x $mock
  echo $mock:$log
}
```

각 시나리오는 fixture setup → `(cd $repo && CMUX_PANE_BIN=$mock GIT_PUSH_CMD=true $REPO/scripts/finish-plan-dev.sh)` 실행 → log 파일 존재 + 내용 검증.

## TDD

- Red: 테스트 작성 후 시나리오 1 FAIL (cleanup 호출 없음, log 파일 없음)
- Green: finish-plan-dev.sh 수정 → 전 시나리오 PASS
- Refactor: `do_cmux_cleanup` 함수 분리 (이미 spec 에 분리됨)

## 완료 조건

```bash
grep -qE "do_cmux_cleanup|CMUX_PANE_BIN" scripts/finish-plan-dev.sh
grep -qE "SKIP_PLAN_DEV_CMUX_CLEANUP|DISABLE_PLAN_DEV_CMUX_CLEANUP" scripts/finish-plan-dev.sh
bash tests/finish_plan_dev_cmux_cleanup.test.sh
bash -n scripts/finish-plan-dev.sh
```

모두 PASS 시 `✅ S3 done` 출력.
