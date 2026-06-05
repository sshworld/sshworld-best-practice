// vuln-scan-pipeline — defending-code-reference-harness 의 find→grade→judge→report 를
// Workflow 골격(안 B)으로 재현한 정적분석 reference. RECON(vuln-class 파티션)→FIND(병렬,
// 소스 읽기만)→JUDGE(JS dedup)→GRADE(독립 skeptic 다수결 적대검증)→REPORT(severity 랭킹).
// ⚠️ 정적 한정 — 코드 실행/빌드 없음(harness gVisor 단계 제외). args/agent 출력은 신뢰경계
//    밖 — self-paste reference 라 sanitize 생략(의도). 운영 투입 시 입력 검증 추가.
// 사용: args.target = '스캔 대상(경로/설명)', args.vulnClasses = ['injection', ...] (옵션).
export const meta = {
  name: 'vuln-scan-pipeline',
  description: '타겟 소스를 vuln-class 별 정적 스캔 → 적대 검증 → severity 랭킹 리포트',
  phases: [{ title: 'Find' }, { title: 'Grade' }, { title: 'Report' }],
};

const TARGET = (args && args.target) || '현재 작업 트리의 소스.';
const VULN_CLASSES = (args && args.vulnClasses) || [
  'injection',
  'memory·bounds',
  'auth·authz',
  'secrets',
  'input-validation',
  'deserialization',
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
          line: { type: 'string' },
          rule: { type: 'string' },
          severity: { type: 'string' },
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

phase('Find');
const raw = (
  await parallel(
    VULN_CLASSES.map((c) => () =>
      agent(
        `대상 소스를 **읽기만** 하고(코드 실행/빌드 금지) '${c}' 취약점 후보를 찾아라. ` +
          `file/line/rule/severity 포함. 대상: ${TARGET}`,
        { label: `find:${c}`, phase: 'Find', schema: FINDINGS, model: 'sonnet' }
      )
    )
  )
)
  .filter(Boolean)
  .flatMap((r) => r.findings || []);

const key = (f) => `${f.file || ''}::${f.rule || ''}::${f.title}`;
const seen = new Set();
const unique = raw.filter((f) => {
  const k = key(f);
  if (seen.has(k)) return false;
  seen.add(k);
  return true;
});

phase('Grade');
const judged = await parallel(
  unique.map((f) => () =>
    parallel(
      ['exploitability', 'reachability', 'false-positive'].map((lens) => () =>
        agent(
          `이 취약점 후보를 '${lens}' 관점에서 반박 시도. 불확실하면 real=false.\n` +
            `${f.title} — ${f.detail || ''} (${f.file || ''}:${f.line || ''})`,
          { label: `grade:${lens}`, phase: 'Grade', schema: VERDICT, model: 'sonnet' }
        )
      )
    ).then((votes) => {
      const live = votes.filter(Boolean);
      const real = live.length > 0 && live.filter((v) => v.real).length > live.length / 2;
      return { ...f, real };
    })
  )
);

const confirmed = judged.filter(Boolean).filter((v) => v.real);

phase('Report');
const order = { critical: 0, high: 1, medium: 2, low: 3 };
confirmed.sort((a, b) => {
  const sa = order[a.severity] ?? 4;
  const sb = order[b.severity] ?? 4;
  return sa - sb;
});
log(`vuln-scan: confirmed ${confirmed.length} / scanned ${unique.length}`);

return { confirmed, scanned: unique.length };
