# Spec: plan-dev Phase 1-1 명확화 룰 강화 (S1, docs/ask-rule-auto-mode-priority)

## 목표
`.claude/commands/plan-dev.md` Phase 1-1 의 "필수 명확화" 룰이 Auto Mode (system prompt) 에 silently overridden 되는 문제 해결. 4 가지 변경:

1. Phase 1-1 표 위에 **Auto Mode 우선순위** 박스 추가
2. 현 표 아래에 "정반대 가능" **trigger 예시 4 항목** 추가
3. Phase 1-2 직전에 **EnterPlanMode 진입 전 self-check** 박스 추가
4. 안티패턴 섹션에 **2줄 추가**

## 산출 파일

### 수정 (단일)
`.claude/commands/plan-dev.md`

## 변경 상세

### (a) Phase 1-1 표 위 — Auto Mode 우선순위 박스

기존 위치 (`### 1-1. 빈틈 진단 + 명확화` 헤더 다음, 체크리스트 줄 다음 줄, 표 시작 전):

```markdown
### 1-1. 빈틈 진단 + 명확화
체크리스트: Scope / Acceptance criteria / Edge case / 사용자·데이터 범위 / 의존성 / 테스트 전략.

| 분류 | 처리 |
|---|---|
```

위 표 시작 (`| 분류 |`) 직전 한 줄 비우고 다음 박스 추가:

```markdown
> ⚠️ **Auto Mode 우선순위**: system prompt 에 "Auto Mode Active" 가 있어도 — 본 룰의 "필수 명확화" 는 **항상 우선**. Auto Mode 는 오직 "재량 명확화" 의 default 만 결정 (= "묻지 말고 가정 후 Assumptions 기록"). 결과가 의도 정반대 일 수 있는 결정은 Auto Mode 무관 반드시 AskUserQuestion.
```

### (b) 표 아래 — trigger 예시 4 항목

기존 표 직후 (`| **재량 명확화** ...|` 줄 다음, 빈 줄 다음):

```markdown
"정반대 가능" trigger 예시 — **이 중 하나라도 해당하면 필수 명확화**:
- 사용자가 메시지에 옵션을 **명시적으로** 제시 (예: "A 또는 B", "`.plans/` 또는 `specs/`") → 의도 있음 → ask
- 모델이 "default 가 명확하지 않다" 고 인지한 결정 (= 임의 선택)
- 해당 결정이 backward-incompatibility / 사용자 인터페이스 변경 / 데이터 손실 위험 동반
- 사용자가 이전 turn 에서 명시한 선호와 다른 선택이 나올 가능성
```

### (c) Phase 1-2 직전 — self-check 박스

기존 위치 (`### 1-2. EnterPlanMode → plan 파일 작성` 헤더 직전, 빈 줄 다음):

```markdown
> 🛑 **EnterPlanMode 진입 전 self-check**: Assumptions 에 들어갈 결정 항목 중 위 "정반대 가능" trigger 매치하는 게 있는가? 있으면 **EnterPlanMode 호출 전** AskUserQuestion 으로 확인. plan 파일 안 Assumptions 에 결정값 dump 금지 — 결정값은 ask 대상.
```

### (d) 안티패턴 섹션 끝 — 2줄 추가

기존 안티패턴 목록 마지막 줄 (`❌ dispatch spec-file 을 /tmp/...`) 다음 줄:

```markdown
- ❌ Auto Mode (system prompt) 를 "필수 명확화도 묻지 말고 가정으로 처리" 로 해석 — Auto Mode 는 "재량 명확화" 의 default 만. "정반대 가능" trigger 매치 결정은 Auto Mode 무관 반드시 AskUserQuestion.
- ❌ 사용자가 메시지에 명시한 옵션 (A 또는 B) 을 Assumptions 에서 임의 선택 후 ExitPlanMode — 사용자 의도 있음 신호. 반드시 AskUserQuestion 으로 확인.
```

## 일반화 검증
- 다른 프로젝트/회사명 절대 없음. 추상 용어만.

## Verification (구현 완료 후)

```bash
# 추가 문구 존재
grep -F "Auto Mode 우선순위" .claude/commands/plan-dev.md
grep -F "정반대 가능" .claude/commands/plan-dev.md
grep -F "EnterPlanMode 진입 전 self-check" .claude/commands/plan-dev.md
grep -F "Auto Mode (system prompt) 를" .claude/commands/plan-dev.md
grep -F "사용자가 메시지에 명시한 옵션" .claude/commands/plan-dev.md

# 안티패턴 라인 수 +2 이상 (이전 18 → 20)
N=$(grep -c '^- ❌' .claude/commands/plan-dev.md)
[ "$N" -ge 20 ] || { echo "안티패턴 부족: $N"; exit 1; }

# 회귀
bash tests/docs_sync.sh
```

모두 PASS 후 `✅ S1 complete — docs/ask-rule-auto-mode-priority`. 실패 시 `❌ <원인>`.

## 완료 조건
1. plan-dev.md 4 위치 추가
2. grep 5 종 매치
3. 안티패턴 줄 수 20 이상
4. docs_sync.sh 회귀 없음
