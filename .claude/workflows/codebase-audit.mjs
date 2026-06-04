// codebase-audit — C: 대규모 escape hatch + Phase 3.5 multi-dimension 적대 verify.
// dimension 별 finder → 각 finding 을 독립 skeptic 다수결로 적대 검증(refute 시도).
// loop-until-dry: K 라운드 연속 새 발견 0 이면 종료. budget 으로 깊이 동적 조절.
// 사용: args.target = '리뷰 대상(파일 목록/diff/디렉토리 설명)'.
export const meta = {
  name: 'codebase-audit',
  description: '대상을 dimension 별로 훑고 finding 을 적대 다수결로 검증',
  phases: [{ title: 'Find' }, { title: 'Verify' }],
};

const TARGET = (args && args.target) || '현재 작업 트리의 변경분(git diff HEAD).';

const DIMENSIONS = [
  { key: 'correctness', prompt: '정합성·로직 버그·경계 조건' },
  { key: 'security', prompt: '인젝션·권한·시크릿 노출·검증 누락' },
  { key: 'reuse', prompt: '중복·기존 유틸 미사용·단순화 여지' },
];

const FINDINGS = {
  type: 'object',
  properties: {
    findings: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          title: { type: 'string' },
          file: { type: 'string' },
          detail: { type: 'string' },
        },
        required: ['title'],
      },
    },
  },
  required: ['findings'],
};
const VERDICT = {
  type: 'object',
  properties: { real: { type: 'boolean' }, reason: { type: 'string' } },
  required: ['real'],
};

const key = (f) => `${f.file || ''}::${f.title}`;
const seen = new Set();
const confirmed = [];
let dry = 0;
const cap = budget && budget.total ? () => budget.remaining() > 40000 : () => true;

while (dry < 2 && cap()) {
  phase('Find');
  const found = (
    await parallel(
      DIMENSIONS.map((d) => () =>
        agent(`대상에서 "${d.prompt}" 문제를 찾아라.\n\n대상: ${TARGET}`, {
          label: `find:${d.key}`,
          phase: 'Find',
          schema: FINDINGS,
        })
      )
    )
  )
    .filter(Boolean)
    .flatMap((r) => r.findings || []);

  const fresh = found.filter((f) => !seen.has(key(f)));
  if (!fresh.length) {
    dry += 1;
    continue;
  }
  dry = 0;
  fresh.forEach((f) => seen.add(key(f)));

  phase('Verify');
  const judged = await parallel(
    fresh.map((f) => () =>
      parallel(
        ['correctness', 'security', 'repro'].map((lens) => () =>
          agent(
            `다음 finding 을 "${lens}" 관점에서 반박 시도하라. 불확실하면 real=false.\n` +
              `${f.title} — ${f.detail || ''} (${f.file || ''})`,
            { label: `verify:${lens}`, phase: 'Verify', schema: VERDICT }
          )
        )
      ).then((votes) => {
        const real = votes.filter(Boolean).filter((v) => v.real).length >= 2;
        return { ...f, real };
      })
    )
  );
  confirmed.push(...judged.filter(Boolean).filter((v) => v.real));
  log(`audit: confirmed ${confirmed.length} (round dry=${dry})`);
}

return { confirmed };
