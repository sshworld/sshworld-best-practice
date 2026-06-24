# Slice S3 — workflow .mjs sonnet 모델 + dogfood 실버그 수정 (type=fix)

대상: `.claude/workflows/{plan-review-panel,slice-pipeline,codebase-audit}.mjs`,
`tests/workflow_integration_lint.sh`, `.claude/commands/plan-dev.md`.

## 1. 모든 agent() 에 model:'sonnet' (비용)
배경: Workflow `agent()` 가 model 미지정 시 main-loop(Opus 1M) 상속 → dogfood 가 24.9M 토큰 소진.
3개 .mjs 의 **모든** `agent(prompt, { ... })` 호출 opts 에 `model: 'sonnet'` 추가.
예: `agent(p, { label:'x', phase:'Find', schema: S })` → `agent(p, { label:'x', phase:'Find', schema: S, model: 'sonnet' })`.
(synthesize 등 schema 없는 호출도 포함.)

## 2. plan-review-panel.mjs — filter 인덱스 오정렬 버그 (dogfood 확인)
현재:
```js
const valid = critiques.filter(Boolean);
const summary = valid.map((v, i) => `[${LENSES[i]?.key}] score=${v.score} ...`).join('\n');
```
`critiques` 는 `parallel(LENSES.map(...))` 결과라 LENSES 와 위치 정렬. 근데 `.filter(Boolean)` 로
중간 null 제거 후 **compacted 인덱스 i** 로 `LENSES[i]` 재참조 → 중간 critique 가 null 이면
이후 라벨이 한 칸씩 밀려 엉뚱한 lens 로 표기(예: deps 결과가 [risk] 로).

수정: filter **전에** lens key 를 결과에 bind.
```js
const valid = critiques
  .map((v, i) => (v ? { ...v, key: LENSES[i].key } : null))
  .filter(Boolean);
const summary = valid.map((v) => `[${v.key}] score=${v.score} blocking=${JSON.stringify(v.blocking)}`).join('\n');
```
(synthesis prompt 에 들어가는 summary 가 올바른 lens 라벨 갖도록.)

## 3. codebase-audit.mjs — 두 가지
(a) **budget 가드**: 현재 `const cap = budget && budget.total ? () => budget.remaining() > 40000 : () => true;`
→ `.total` 없는 런타임서 가드 무력화. 변경:
```js
const cap = (budget && typeof budget.remaining === 'function')
  ? () => budget.remaining() > 40000
  : () => true;
```
(b) **생존-다수결**: 현재 `const real = votes.filter(Boolean).filter(v => v.real).length >= 2;`
→ lens agent 실패(null) 시 false-negative 편향. 변경:
```js
const live = votes.filter(Boolean);
const real = live.length > 0 && live.filter(v => v.real).length > live.length / 2;
```
(c) **injection 주석**: TARGET/args 보간부(`대상: ${TARGET}`) 위에 한 줄:
`// NOTE: args/1차 agent 출력은 신뢰경계 밖 — self-paste reference 템플릿이라 sanitize 생략(의도). 운영 투입 시 입력 검증 추가.`

## 4. tests/workflow_integration_lint.sh
- 파일 상단 주석의 `.claude/workflows/*.js` → `*.mjs` 로 정정 (line 4 부근).
- step 2 에 assert 추가: 각 `.mjs` 가 `model: 'sonnet'` 최소 1회 포함.
  ```bash
  for f in "${wf_files[@]}"; do grep -q "model: *'sonnet'" "$f" || fail "model sonnet 누락: $f"; done
  ```
- 기존 wrap+syntax(node --check) 로직은 유지.

## 5. plan-dev.md — Workflow 통합 섹션 (1줄)
"### B. Phase 2 workflow 실행 모드" 또는 opt-in 단락에 비용 주의 1줄 추가:
"워크플로 `agent()` 는 `model:'sonnet'` 명시 권장 — 미지정 시 main-loop(Opus 1M) 상속해 토큰 폭증(dogfood 24.9M 사례). reference `.mjs` 는 이미 sonnet 고정."
(plan-dev.md 의 placeholder 변환은 S4 담당 — 여기선 이 1줄만, script 경로 표현 건드리지 말 것.)

## 검증
```bash
for f in .claude/workflows/*.mjs; do node --check <(sed 's/^export const meta/const meta/' "$f" | (echo '(async function(agent,parallel,pipeline,phase,log,args,budget,workflow){'; cat; echo '});')) ; done  # 또는 lint 의 wrap 방식
for f in .claude/workflows/*.mjs; do grep -q "model: *'sonnet'" "$f" || echo "MISSING model $f"; done
bash tests/workflow_integration_lint.sh   # OK
grep -qi "sonnet" .claude/commands/plan-dev.md
```

## 완료 시
lint OK + 3 .mjs 전부 model:'sonnet' + plan-dev.md sonnet 언급 → `✅ S3 done`. 실패 → `❌`+원인.
주의: plan-dev.md 의 `scripts/...` 경로 표현은 변경 금지(S4 영역).
