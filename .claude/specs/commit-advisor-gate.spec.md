# Slice S1 — commit-advisor-gate (type: fix)

## 목표
plan-dev Phase 4 `commit-advisor` 가 조용히 스킵되는 결함을 하네스로 막는다. push(Phase 5, `finish-plan-dev.sh`) 직전에 "commit-advisor 가 실행됐는가"를 marker 로 검사 → 없으면 push 차단(exit 2). 우회 env 제공.

근본 원인: plan-dev 의 부작용 단계는 전부 hook 백스톱이 있는데 Phase 4 commit-advisor 만 순수 prose → 머지 후 "끝나 보임" → 스킵. push 라는 기계적 다음 동작을 막아 의식적 호출을 강제한다.

## 절대 규칙
- **TDD Red→Green→Refactor**. 테스트 먼저 작성해서 FAIL 확인 후 구현.
- **커밋 메시지에 `S1`, `슬라이스`, `merge:` 등 내부 계획 라벨 절대 금지**. 깨끗한 한글 Conventional Commit (`fix: …`) 으로만. 예: `fix: commit-advisor 미실행 시 push 차단하는 게이트 추가`.
- 작업 완료 시 마지막 줄에 `✅` 또는 실패 시 `❌` 출력.

## 변경 대상 파일
1. `tests/finish_plan_dev_commit_advised_gate.sh` (신규, RED 먼저)
2. `scripts/finish-plan-dev.sh` (게이트 구현)
3. `agents/commit-advisor.md` (marker 기록 지시 추가)
4. 기존 finish 테스트 fixture 패치 (회귀 방지)
5. `CLAUDE.md`, `README.md` (문서 동기화)

---

## 1. 테스트 (RED 먼저) — `tests/finish_plan_dev_commit_advised_gate.sh`
`tests/finish_plan_dev_cmux_cleanup.test.sh` 의 fixture/스타일을 그대로 미러(같은 `git_init_main`, `setup_fixture`, `GIT_PUSH_CMD=true`, `PLAN_DEV_SESSION_BIN=/bin/false` 패턴). marker 경로는 `<repo>/.git/plan-dev-commit-advised`.

검증 케이스:
- **Case 1**: 세션 marker 활성 + 커밋 존재 + **commit-advised marker 부재** → `finish-plan-dev.sh` exit **2**, stderr 에 `commit-advisor` 문자열 포함.
- **Case 2**: commit-advised marker `touch` 후 → push 진행 → exit **0**, stdout `pushed`.
- **Case 3**: marker 부재 + `SKIP_COMMIT_ADVISOR_GATE=1` → exit **0** (1회 우회, push 진행).
- **Case 4**: marker 부재 + `DISABLE_COMMIT_ADVISOR_GATE=1` → exit **0** (영구 우회).
- **Case 5**: Case 2 처럼 push 성공 후 → commit-advised marker 가 **삭제**되어 있어야 함 (`clear_marker` 가 같이 제거). `[ ! -f .git/plan-dev-commit-advised ]`.

마지막 줄 `PASS`. 실행 권한 `chmod +x`.

## 2. 구현 — `scripts/finish-plan-dev.sh`
- marker 경로 상수 추가 (기존 `MARKER="${COMMON_DIR}/plan-dev-session.json"` 옆): `MARKER_ADVISED="${COMMON_DIR}/plan-dev-commit-advised"`.
- **게이트 위치**: `NEW_COMMITS` 체크(`if [ "$NEW_COMMITS" = "0" ]` 블록) **직후**, "develop 또는 main-only 분기" **이전**. 즉 "푸시할 커밋이 있다" 가 확정된 지점.
- 게이트 로직 (`check_commit_advised` 함수 또는 인라인):
  ```
  if [ "${DISABLE_COMMIT_ADVISOR_GATE:-0}" != "1" ] && [ "${SKIP_COMMIT_ADVISOR_GATE:-0}" != "1" ]; then
    if [ ! -f "$MARKER_ADVISED" ]; then
      echo "⛔ commit-advisor (Phase 4) 미실행 — push 차단." >&2
      echo "   commit-advisor 에이전트를 먼저 호출해 커밋 메시지/브랜치명을 정리하라." >&2
      echo "   우회: SKIP_COMMIT_ADVISOR_GATE=1 (1회) / DISABLE_COMMIT_ADVISOR_GATE=1 (영구)" >&2
      exit 2
    fi
  fi
  ```
- `clear_marker()` 함수에 `rm -f "$MARKER_ADVISED"` 추가 (session marker 와 함께 제거).
- 게이트는 cmux 무관 보편. marker 없는 경로(`FINISH_AUTO_PUSH_WITHOUT_MARKER`, `no marker — skip`)는 이미 게이트 앞에서 return/exit 하므로 영향 없음 — 변경 금지.

## 3. `agents/commit-advisor.md`
"책임" 섹션에 항목 추가 (실제 commit/push 는 여전히 안 함을 유지):
- 분석·추천을 마친 직후 marker 를 기록한다: `touch "$(git rev-parse --git-common-dir)/plan-dev-commit-advised"`. 이는 "Phase 4 commit-advisor 가 실행됨" 증거로 `finish-plan-dev.sh` 의 push 게이트를 통과시킨다.
- "안 하는 것" 의 `git commit`/`git push` 비실행 원칙은 유지 (marker touch 는 commit/push 아님).

## 4. 기존 finish 테스트 회귀 방지 (중요)
새 게이트 때문에 marker 활성 + 커밋 존재 상태에서 push 를 기대하는 기존 테스트가 exit 2 로 깨진다. 다음 테스트들의 fixture 가 push 를 기대하는 케이스에 `touch "$repo/.git/plan-dev-commit-advised"` 를 추가하거나 invocation 에 `SKIP_COMMIT_ADVISOR_GATE=1` 를 넣어 통과시켜라:
- `tests/finish_plan_dev_cmux_cleanup.test.sh` (setup_fixture 가 marker+commit 생성 → push 기대 케이스 1,5 등)
- `tests/plan_dev_finish.sh`
- `tests/finish_plan_dev_auto_push.sh` 는 marker 없는 경로(FINISH_AUTO_PUSH_WITHOUT_MARKER)라 영향 없을 가능성 높음 — 실행해 확인만.
권장: fixture 의 `setup_fixture` 에 marker touch 를 추가하면 한 곳 수정으로 해결. **반드시 해당 테스트 전부 실행해 PASS 확인.**

## 5. 문서 동기화
- `CLAUDE.md`:
  - `finish-plan-dev.sh` 행에 "push 직전 commit-advised marker 게이트(commit-advisor 미실행 차단)" 추가.
  - 환경변수 표에 `SKIP_COMMIT_ADVISOR_GATE`, `DISABLE_COMMIT_ADVISOR_GATE` 두 행 추가 (기본 unset, 효과 설명).
- `README.md`: 환경변수 표에 동일 두 env 추가.

## 검증 (완료 전 필수 실행)
```bash
bash tests/finish_plan_dev_commit_advised_gate.sh        # PASS
bash tests/finish_plan_dev_cmux_cleanup.test.sh          # PASS (회귀 없음)
bash tests/plan_dev_finish.sh                            # PASS
bash tests/finish_plan_dev_auto_push.sh                  # PASS
```
모두 PASS 해야 ✅. grep 자가검증: `grep -q COMMIT_ADVISOR_GATE scripts/finish-plan-dev.sh && grep -q plan-dev-commit-advised agents/commit-advisor.md`.

## 커밋
깨끗한 단일 커밋 (S/슬라이스 라벨 없이):
`DOC_IMPACT=updated git commit -m "fix: commit-advisor 미실행 시 push 차단하는 게이트 추가"`
