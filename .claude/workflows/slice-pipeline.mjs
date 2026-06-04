// slice-pipeline — B: Phase 2 의존성-없는 슬라이스 fan-out 을 pipeline 으로.
// 각 슬라이스 implement → verify 를 독립 통과(배리어 없음). worktree 격리 네이티브.
// opt-in 전용 (기본 아님). cmux 시각화 불필요 + 슬라이스 多 + 자동 verify gate 원할 때.
// 사용: args.slices = [{slug, type, specPath}] (spec 은 .claude/specs/<slug>.spec.md).
export const meta = {
  name: 'slice-pipeline',
  description: '의존성 없는 슬라이스를 worktree 격리 pipeline 으로 구현+검증',
  phases: [{ title: 'Implement' }, { title: 'Verify' }],
};

const SLICES = (args && args.slices) || [];

const IMPL = {
  type: 'object',
  properties: {
    slug: { type: 'string' },
    ok: { type: 'boolean' },
    files: { type: 'array', items: { type: 'string' } },
    notes: { type: 'string' },
  },
  required: ['slug', 'ok'],
};
const VERDICT = {
  type: 'object',
  properties: {
    slug: { type: 'string' },
    pass: { type: 'boolean' },
    failure: { type: 'string' },
  },
  required: ['slug', 'pass'],
};

if (!SLICES.length) {
  log('slice-pipeline: args.slices 비어 있음 — 호출자가 [{slug,type,specPath}] 전달 필요.');
  return { done: [], note: 'no slices' };
}

const done = await pipeline(
  SLICES,
  (s) =>
    agent(
      `TDD Red→Green→Refactor 로 슬라이스 "${s.slug}" 를 구현하라. ` +
        `spec: ${s.specPath || '(인라인)'}. 브랜치 ${s.type || 'feat'}/${s.slug}. ` +
        `완료 시 결과를 schema 로 반환.`,
      { label: `impl:${s.slug}`, phase: 'Implement', isolation: 'worktree', schema: IMPL }
    ),
  (r, s) =>
    agent(
      `슬라이스 "${(r && r.slug) || s.slug}" 의 build + test 를 실행해 PASS 여부 판정하라.`,
      { label: `verify:${s.slug}`, phase: 'Verify', schema: VERDICT }
    )
);

const results = done.filter(Boolean);
const failed = results.filter((v) => v && v.pass === false);
log(`slice-pipeline: ${results.length}개 처리, 실패 ${failed.length}`);
return { results, failed };
