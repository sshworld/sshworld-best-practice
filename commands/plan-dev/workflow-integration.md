## Workflow 통합 (dynamic workflows)

> **핵심**: `Workflow` 툴 = JS 스크립트로 subagent fan-out / pipeline / loop 를 **결정론 오케스트레이션**. plan-dev 의 단일 `Agent` 호출 자리를 **판단 다양성·적대 검증·대규모 처리**로 격상. `/plan-dev` 는 슬래시 커맨드 → 그 자체가 Workflow 툴 **opt-in 트리거로 적법** (툴 스펙: "user invoked a skill/command whose instructions tell you to call Workflow").

### ⚠️ cmux ⇄ workflow 상호배타 (먼저 읽을 것)

Workflow agent 는 **cmux surface 가 아니다** — 하네스 내부 Task 러너로 돌고 `/workflows` 진행 트리에 뜬다. cmux 사이드바 grid split 시각화와 **다른 런타임 → 상호배타**.
- **시각적 슬라이스 실행** (사용자가 화면에서 보고 싶음) → **cmux dispatch 유지** (`--mode=cmux`).
- **비시각·추론 집약** (Plan 비평, 코드 리뷰, verify 수렴, 대규모 audit/migration) → **Workflow**.
- 한 작업에서 둘 다 쓰려 하지 말 것. Slice 단위로 "이 슬라이스는 cmux 실행 / 이 검증 Phase 는 workflow" 로 분리.

### opt-in 발동 조건 (이 중 하나)

- 사용자가 메시지에 "workflow" / "워크플로우" / "multi-agent" / "fan out" 명시.
- 사용자가 이 Phase 에서 Workflow 사용을 명시 지시 (예: "모든 수로 검증").
- ultracode on (system-reminder 확인 시).

opt-in 없으면 호출 금지 — 기존 단일 `Agent` 흐름 유지. 비용 큼(수십 agent) → 사용자 동의 필수.

### A. Plan/Review Phase 보강 (가장 안전·고가치, cmux 실행 경로 보존)

- **Phase 1-3 Plan review → judge panel**: 단일 `Agent(Plan)` 대신 N개 독립 비평(서로 다른 각도: MVP-first / risk-first / 의존성-first)을 병렬 생성 → 점수화 → 최고안 합성 + 차선안 좋은 아이디어 graft.
- **Phase 3.5 Review → multi-dimension 적대 verify**: dimension(correctness/security/perf/repro)별 finder → 각 finding 을 **독립 skeptic 다수결**로 적대 검증(refute 시도, 과반 refute 시 kill). plausible-but-wrong 제거.

inline 템플릿 (paste as `script:`; named 파일은 `.claude/workflows/*.mjs` 에 동봉):
```js
// Phase 3.5 — review-changes.js (요약). 전체: .claude/workflows/codebase-audit.mjs
const results = await pipeline(DIMENSIONS,
  d => agent(d.prompt, {phase:'Review', schema: FINDINGS}),
  review => parallel(review.findings.map(f => () =>
    agent(`Adversarially verify: ${f.title}. Default refuted=true if uncertain.`,
      {phase:'Verify', schema: VERDICT}).then(v => ({...f, verdict:v})))))
const confirmed = results.flat().filter(Boolean).filter(f => f.verdict?.isReal)
```

### B. Phase 2 workflow 실행 모드 (opt-in, 기본 아님)

비-cmux 환경에서 의존성 없는 슬라이스 fan-out 을 수동 `Agent` 다발 대신 `pipeline(slices, implement, verify)` 로. **기본값 아님** — 환경별 기본(cmux=dispatch, 비-cmux=direct-edit/subagent)은 그대로. 시각화 불필요 + 슬라이스 多 + 자동 verify gate 원할 때 opt-in.

워크플로 `agent()` 는 `model:'sonnet'` 명시 권장 — 미지정 시 main-loop(Opus 1M) 상속해 토큰 폭증(dogfood 24.9M 사례). reference `.mjs` 는 이미 sonnet 고정.
- worktree 충돌 회피: `agent(..., {isolation:'worktree'})` (네이티브, dispatch-slice-pane 불필요).
- Slice File Map 의 `Mode` 컬럼 값으로 `workflow` 표기 가능 (cmux/direct-edit/workflow).
- 한계: cmux 사이드바 시각화 없음(`/workflows` 트리로 관찰). 토큰은 budget 공유 풀.

```js
// .claude/workflows/slice-pipeline.mjs (요약)
const done = await pipeline(SLICES,
  s => agent(s.specPrompt, {label:`impl:${s.slug}`, phase:'Implement',
                            isolation:'worktree', schema: IMPL_RESULT}),
  r => agent(`Verify build+test for ${r.slug}`, {phase:'Verify', schema: VERDICT}))
```

### C. 대규모 작업 escape hatch

audit / migration / framework swap 등 **수십~수백 슬라이스** 는 workflow 가 압도적 (loop-until-dry, multi-modal sweep, resume journal). 일반 feature(슬라이스 ≤ ~8)는 기존 흐름 유지. `budget.remaining()` 로 깊이 동적 조절, `resumeFromRunId` 로 중단 재개.

### 안티패턴 (Workflow)

- ❌ opt-in 없이 Workflow 호출 — 수십 agent 비용. 사용자 동의 없으면 단일 Agent.
- ❌ cmux 시각화 슬라이스를 workflow 로 돌려 사이드바에서 안 보이게 만들기 — 런타임 상호배타. 시각 실행은 `--mode=cmux`.
- ❌ B 의 workflow 실행 모드를 비-cmux **기본값**으로 격상 — opt-in 유지 (기본 뒤집지 말 것).
- ❌ `name:`(`.claude/workflows/*.mjs`) 해석이 harness 빌드에 의존 — 미확인 시 inline `script:` 로 paste (항상 동작).

