# Spec — plan-dev.md 룰: Goal Statement + AskUserQuestion 의무 (S1)

## Context (자식 implementor 용)

plan-dev workflow 를 native `/goal` 처럼 자체 loop 가능하게 만드는 작업의 1번 슬라이스.
본 슬라이스는 `.claude/commands/plan-dev.md` 의 룰 변경 + spec 보존.
다음 슬라이스(S2)가 Stop hook (`enforce-plan-dev-goal.sh`) 구현 — 본 spec 이 hook 의 contract.

큰 그림:
- Stop hook 가 plan 파일의 `## Goal Statement` 섹션 안 `<!-- machine-checks -->` bash block 을 매 turn 종료 시 실행
- 전부 exit 0 → Stop 허용 / 하나라도 fail → exit 2 + stderr reason → 모델 자동 다음 turn 재진입
- 사용자 `/goal` 입력 0

## TDD Red → Green

### Red (현재 상태)
```bash
grep -c "Goal Statement" .claude/commands/plan-dev.md       # → 0
grep -c "machine-checks" .claude/commands/plan-dev.md       # → 0
grep -c "AskUserQuestion 의무" .claude/commands/plan-dev.md  # → 0
grep -c "사용자 선택을 요구하는" .claude/commands/plan-dev.md  # → 0
grep -c "측정 가능" .claude/commands/plan-dev.md             # → 0
```

### Green (목표)
```bash
grep -c "Goal Statement" .claude/commands/plan-dev.md       # ≥ 3
grep -c "machine-checks" .claude/commands/plan-dev.md       # ≥ 1
grep -c "AskUserQuestion 의무" .claude/commands/plan-dev.md  # ≥ 1
grep -c "사용자 선택을 요구하는" .claude/commands/plan-dev.md  # ≥ 1
grep -c "측정 가능" .claude/commands/plan-dev.md             # ≥ 1
wc -l .claude/commands/plan-dev.md                          # ≤ 330
```

## 수정 영역 (3 영역)

### A. Phase 1-1 강화

"정반대 가능" trigger list (현 line 48~52) 끝에 한 줄 추가:
```
- **사용자 선택을 요구하는 option list** (A/B/C 중 고르세요 형태) 를 제시하는 응답 — 반드시 AskUserQuestion 으로 전달 (plain text dump 금지). 단순 정보 enumeration ("다음 2가지 결과가 나옴: ...") 은 해당 없음.
```

그리고 self-check 박스 (현 line 54) 바로 뒤에 Phase 1-1 ↔ 1-2 연결 한 줄:
```
> 💡 **Phase 1-1 ↔ Phase 1-2 연결**: 1-1 의 Acceptance criteria 가 1-2 의 Goal Statement 의 source. 같은 항목을 측정 가능 form (grep/test/명령) 으로만 transform.
```

### B. Phase 1-2 필수 섹션 + Goal Statement 정의 박스

기존 필수 섹션 라인 (현 line 57):
```
필수 섹션: Context / Explored Files / Assumptions / Vertical Slices / **Slice File Map** / TDD Strategy / Verification.
```

변경:
```
필수 섹션: Context / Explored Files / Assumptions / Vertical Slices / **Slice File Map** / TDD Strategy / Verification / **Goal Statement**.
```

그리고 Slice 정의 시 type 줄 (현 line 69) 다음에 정의 박스 삽입:

```markdown
#### Goal Statement — plan-dev 자체 loop 의 gate

**목적**: plan-dev workflow 가 native `/goal` 처럼 자체 loop 하는 mechanism. Stop hook (`enforce-plan-dev-goal.sh`) 가 매 model turn 종료 시점에 plan 파일의 `<!-- machine-checks -->` bash block 실행. 전부 PASS → Stop 허용. 하나라도 fail → exit 2 + stderr reason → 모델 자동 다음 turn (보완 작업). 사용자 `/goal` 입력 0.

**출처**: Phase 1-1 의 Acceptance criteria 를 측정 가능 form 으로 transform.

**형식** (plan 파일 마지막 섹션):
~~~markdown
## Goal Statement

<!-- machine-checks -->
~~~bash
grep -c "X" file | awk '$1>=3{exit 0}{exit 1}'
test -x scripts/foo.sh
~~~
<!-- /machine-checks -->

**Semantic goal**: 한 문장 자연어 — commit-advisor 메시지 + 사람 가독성. hook 평가 대상 X.
~~~

**제약**:
- machine-checks 라인 = bash one-liner (exit 0 = PASS)
- **측정 가능** 만 — `grep` / `test` / `jq` / shell command 결과 기반
- 추상 표현 금지 (e.g. "품질 향상" ✗, `grep -c "X" file` ≥ 3 ✓)
- 전체 길이 ≤4000 chars (native /goal condition 한도 호환)

**우회** (예외): `SKIP_PLAN_DEV_GOAL=1` (1회) / `DISABLE_PLAN_DEV_GOAL_HOOK=1` (영구)
```

### C. 안티패턴 list 끝에 3건 append

기존 안티패턴 list 의 마지막 항목 다음에:
```
- ❌ 옵션 list (A/B/C) 를 plain text 로 응답 끝에 dump 하고 turn 종료 — selection chip UI 안 떠 사용자 입력 비용 증가, plan-dev 흐름 끊김. **AskUserQuestion 의무**.
- ❌ Goal Statement 에 측정 불가 추상 표현 ("품질 향상", "안정성 강화") 만 박기 — Stop hook 가 평가 못 함. grep/test/명령 결과로 확인 가능한 항목만 허용.
- ❌ Goal Statement 섹션에 `<!-- machine-checks -->` 블록 누락 — hook 가 평가할 입력 없음 → exit 0 통과로 loop 의미 상실. 형식 박스 그대로 따를 것.
```

## 주의 사항

- Phase 6 변경 없음 — 사용자 입력 0 정책. `/goal` 명령 출력 룰 박지 말 것.
- 들여쓰기·번호·기존 표 위치 유지.
- 안티패턴 list 의 emoji `❌` 유지.

## 산출 파일

- `.claude/commands/plan-dev.md` (위 3영역 패치)
- `.claude/specs/plan-dev-goal-integration.spec.md` (본 spec — 이미 작성됨, 자식은 건드릴 필요 없음)

## 자식이 끝나기 전 verification

```bash
set -e
[ "$(grep -c 'Goal Statement' .claude/commands/plan-dev.md)" -ge 3 ]
[ "$(grep -c 'machine-checks' .claude/commands/plan-dev.md)" -ge 1 ]
[ "$(grep -c 'AskUserQuestion 의무' .claude/commands/plan-dev.md)" -ge 1 ]
[ "$(grep -c '사용자 선택을 요구하는' .claude/commands/plan-dev.md)" -ge 1 ]
[ "$(grep -c '측정 가능' .claude/commands/plan-dev.md)" -ge 1 ]
[ "$(wc -l < .claude/commands/plan-dev.md)" -le 330 ]
echo "✅ all green"
```

위 verification 마지막 라인이 `✅ all green` 출력하면 슬라이스 완료. 자식은 응답 마지막에 `✅` 출력.
