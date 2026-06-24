# S4 — marketplace-curation-and-deps (feat)

## 목표
marketplace.json 에 큐레이트 외부 플러그인 aggregate + plan-dev 의존 선언 → `/plugin install plan-dev` 시 fresh 환경에서도 자동 동반설치. caveman 은 opt-in(가역).

## 확정 값 (검증 완료 — 그대로 사용, 재조사 불필요)
- marketplace 내부 이름: **`sshworld-best-practice`** (기존 `sshworld`=open-coleslaw 와 충돌 회피). repo add 경로는 `sshworld/sshworld-best-practice` 그대로 동작.
- aggregate 외부 (전부 `.claude-plugin/` 유효 plugin, branch main 확인됨):
  - `taste-skill` ← github `Leonxlnx/taste-skill`
  - `andrej-karpathy-skills` ← github `multica-ai/andrej-karpathy-skills`
  - `caveman` ← github `JuliusBrussee/caveman`

## TDD: 먼저 테스트 (Red)
신규 `tests/unit/marketplace-deps.test.sh`:
- `.claude-plugin/marketplace.json` JSON valid + `name == "sshworld-best-practice"`.
- marketplace plugins 에 plan-dev, taste-skill, andrej-karpathy-skills, caveman 4엔트리 존재.
- caveman 엔트리 `defaultEnabled == false`.
- `allowCrossMarketplaceDependenciesOn` 필드 존재.
- `.claude-plugin/plugin.json` `dependencies` 에 taste-skill, andrej-karpathy-skills 포함(≥2). caveman 은 dependencies 에 **없음**(opt-in).
실행 → Red.

## 구현 (Green)

### .claude-plugin/marketplace.json (덮어쓰기)
```json
{
  "name": "sshworld-best-practice",
  "owner": { "name": "sshworld", "url": "https://github.com/sshworld" },
  "allowCrossMarketplaceDependenciesOn": ["caveman"],
  "plugins": [
    { "name": "plan-dev", "source": ".", "description": "Plan-driven TDD dev workflow (Phase 0~6, dispatch, goal-gate)." },
    { "name": "taste-skill", "source": { "source": "github", "repo": "Leonxlnx/taste-skill", "ref": "main" }, "description": "Anti-slop frontend UI skills (큐레이트)." },
    { "name": "andrej-karpathy-skills", "source": { "source": "github", "repo": "multica-ai/andrej-karpathy-skills", "ref": "main" }, "description": "Karpathy LLM 코딩 가이드라인 (큐레이트)." },
    { "name": "caveman", "source": { "source": "github", "repo": "JuliusBrussee/caveman", "ref": "main" }, "description": "출력 압축 모드 (opt-in).", "defaultEnabled": false }
  ]
}
```

### .claude-plugin/plugin.json (dependencies 추가)
기존 plan-dev plugin.json 에 추가(다른 필드 보존):
```json
"dependencies": ["taste-skill", "andrej-karpathy-skills"]
```
- **caveman 은 dependencies 에 넣지 말 것** — 하드 의존이면 강제 enable 됨. caveman 은 카탈로그 엔트리(defaultEnabled:false)로만 둬서 opt-in 유지.
- taste-skill/andrej-karpathy-skills 는 additive(UI/가이드) → 자동 동반설치+enable 의도.

### 설계 의도 (주석/문서용)
- 하드 deps(taste-skill, karpathy) = fresh `/plugin install plan-dev` 시 자동. additive 라 안전.
- caveman = 같은 marketplace 카탈로그에 있어 `/plugin install caveman@sshworld-best-practice` 한 줄로 opt-in. 강제 enable 아님.
- 가역: `claude plugin uninstall <p> --prune` / `claude plugin prune`.

## 문서 동기화 (README.md)
"동반설치 + 가역" 섹션 추가:
- `/plugin marketplace add sshworld/sshworld-best-practice` → `/plugin install plan-dev` → taste-skill·karpathy 자동.
- caveman opt-in: `/plugin install caveman@sshworld-best-practice` (또는 enable).
- 제거: `claude plugin uninstall <plugin> --prune`, 고아 정리 `claude plugin prune`.
- caveman 은 출력 스타일 바꾸므로 기본 비활성(원하면 enable).

## Verify
- `bash tests/unit/marketplace-deps.test.sh` PASS.
- `bash tests/**/*.sh` 전체 PASS.
- `python3 -c "import json;json.load(open('.claude-plugin/marketplace.json'));json.load(open('.claude-plugin/plugin.json'))"` valid.

## 금지
- caveman 을 dependencies 에 넣기 금지(opt-in 유지).
- hooks/컴포넌트 파일 건드리기 금지(S1~S3 결과).
- mcpServers 추가 금지(S5).

## 완료 신호
Verify PASS → `✅ marketplace-curation-and-deps`. 실패 → `❌ <이유>`.
