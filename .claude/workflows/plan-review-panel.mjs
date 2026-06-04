// plan-review-panel — A: Phase 1-3 Plan review 를 judge panel 로 격상.
// N개 독립 비평(서로 다른 각도) → 점수화 → 최고안 + 차선안 graft 합성.
// 사용: Workflow({scriptPath:'.claude/workflows/plan-review-panel.mjs', args:{plan:'<plan 텍스트>'}})
//   또는 inline `script:` 로 paste. args.plan = 평가할 plan 본문.
export const meta = {
  name: 'plan-review-panel',
  description: 'Plan 을 서로 다른 각도의 독립 심사위원으로 비평 후 합성',
  phases: [{ title: 'Critique' }, { title: 'Synthesize' }],
};

const PLAN = (args && args.plan) || 'No plan provided — read the active plan file.';

const LENSES = [
  { key: 'mvp', angle: 'MVP-first: 가장 작은 동작 슬라이스가 먼저인가, 과설계는 없는가' },
  { key: 'risk', angle: 'risk-first: 되돌리기 어려운/데이터 손실/호환성 파괴 지점은' },
  { key: 'deps', angle: '의존성-first: 슬라이스 간 파일 충돌·순서 의존·숨은 결합은' },
];

const VERDICT = {
  type: 'object',
  properties: {
    score: { type: 'number', description: '0-10 plan 건전성' },
    blocking: { type: 'array', items: { type: 'string' } },
    improvements: { type: 'array', items: { type: 'string' } },
  },
  required: ['score', 'blocking', 'improvements'],
};

phase('Critique');
const critiques = await parallel(
  LENSES.map((l) => () =>
    agent(
      `다음 plan 을 "${l.angle}" 관점으로만 비평하라. 칭찬 금지, 문제+수정만.\n\n${PLAN}`,
      { label: `critique:${l.key}`, phase: 'Critique', schema: VERDICT, model: 'sonnet' }
    )
  )
);

phase('Synthesize');
const valid = critiques
  .map((v, i) => (v ? { ...v, key: LENSES[i].key } : null))
  .filter(Boolean);
const summary = valid
  .map((v) => `[${v.key}] score=${v.score} blocking=${JSON.stringify(v.blocking)}`)
  .join('\n');
const synthesis = await agent(
  `심사위원 ${valid.length}명 비평을 종합하라. blocking 합집합 우선, 중복 제거, ` +
    `실행 가능한 plan 수정안 1개로 합성:\n${summary}`,
  { label: 'synthesize', phase: 'Synthesize', model: 'sonnet' }
);

return { critiques: valid, synthesis };
