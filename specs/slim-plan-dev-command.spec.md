# S2 — slim-plan-dev-command (refactor)

## 목표
`commands/plan-dev.md`(382줄, 비대) → **린 코어(≤200줄)** + 레퍼런스 3파일 분할. 내용 손실 0, 이동만. 매 세션 로드 토큰↓.

## TDD: 먼저 테스트 (Red)
신규 `tests/unit/plan-dev-split.test.sh`:
- `[ "$(wc -l < commands/plan-dev.md)" -le 200 ]`
- `commands/plan-dev/cmux-dispatch.md`, `commands/plan-dev/workflow-integration.md`, `commands/plan-dev/antipatterns.md` 3파일 존재.
- 코어가 3개 레퍼런스를 링크/참조(`grep -q "plan-dev/cmux-dispatch" commands/plan-dev.md` 등).
- 핵심 키워드 보존: 코어+레퍼런스 합쳐 `Phase 0`~`Phase 6`, `Goal Statement`, `machine-checks`, `Slice File Map`, `AskUserQuestion` 전부 grep 매치.
실행 → Red 확인 후 구현.

## 구현 (Green)

### 분할 대상 (현재 commands/plan-dev.md 섹션)
**코어 유지** (`commands/plan-dev.md`):
- 헤더/철학, Phase 0, Phase 1 (1-0 Explore, **1-1 빈틈진단+명확화 전체** — Auto Mode/필수명확화/AskUserQuestion 룰은 핵심이라 코어 유지), 1-2 (plan 파일 섹션 + Goal Statement 형식/제약/우회 — 코어 유지), 1-3 요약, 1-4, Phase 2 **요지만**(상세는 레퍼런스 링크), Phase 3/3.5/4/5/6, 안전 규칙.
- Phase 2 모드 선택 표는 코어에 1줄 요약 + "상세: `${CLAUDE_PLUGIN_ROOT}` 기준 `commands/plan-dev/cmux-dispatch.md`" 링크.

**`commands/plan-dev/cmux-dispatch.md`** 로 이동 (현 146~218):
- `### Phase 2 모드 선택` 표 상세 + `#### cmux dispatch 동작 모델` + `#### Dispatch wrapper 가용성 검증` + `#### Spec 파일 위치` + 호출 예/회수 예.

**`commands/plan-dev/workflow-integration.md`** 로 이동 (현 287~349):
- `## Workflow 통합` 전체(⚠️ 상호배타 / opt-in / A / B / C / 안티패턴(Workflow)).

**`commands/plan-dev/antipatterns.md`** 로 이동 (현 355~끝):
- `## 안티패턴 — 절대 하지 말 것` 전체 리스트.

### 링크 방식
- 코어 각 분할 지점에 1줄: `> 📎 상세: [cmux dispatch 가이드](./plan-dev/cmux-dispatch.md)` (상대경로). 모델이 필요 시 Read.
- 경로 토큰 `${CLAUDE_PLUGIN_ROOT}/scripts/...` 는 이동 중에도 보존(S1 결과 유지).

### 분할 원칙
- **내용 한 글자도 삭제 금지** — 통째 이동. 안티패턴 항목/Workflow 템플릿/진단 시퀀스 전부 레퍼런스로 옮기되 보존.
- 코어 ≤200줄 안 되면 Phase 3/3.5/4 의 장황한 예시 블록도 cmux-dispatch.md 로 추가 이동.

## 문서 동기화
- `README.md`: plan-dev 구조 설명에 "코어+레퍼런스 분할" 반영(있으면).

## Verify
- `bash tests/unit/plan-dev-split.test.sh` PASS.
- `bash tests/**/*.sh` 전체 PASS (회귀).
- `wc -l commands/plan-dev.md` ≤200 확인.
- 레퍼런스 3파일 합 + 코어 = 원본 내용 보존(육안: 안티패턴 개수, Workflow A/B/C 보존).

## 금지
- 플러그인 manifest/hooks.json 건드리기 금지(S1 결과).
- 내용 삭제·요약으로 인한 룰 손실 금지(이동만).

## 완료 신호
Verify PASS → 마지막 줄 `✅ slim-plan-dev-command`. 실패 → `❌ <이유>`.
