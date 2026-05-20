# Slice S2 — reviewer/implementor 가드 + CLAUDE.md 안티패턴

너는 implementor 다. TDD R→G→R. 작업 끝에 `✅ dead-code-bash-guard:` 또는 `❌ dead-code-bash-guard:` 출력.

## 작업 디렉토리

`/Users/sshworld/develop/claude-best-practice/.worktrees/dead-code-bash-guard`

시작 즉시 `pwd` 출력 → 이 경로와 일치 안 하면 즉시 `❌ dead-code-bash-guard: cwd mismatch` 보고 후 중단.

## 산출 파일

- `.claude/agents/reviewer.md`
- `.claude/agents/implementor.md`
- `CLAUDE.md`

다른 파일 수정 금지.

## 변경 명세

### A. `.claude/agents/reviewer.md`

**A-1. "치명적 이슈" 또는 "제안 이슈" 섹션에 dead code 판정 가드 추가**

관찰된 케이스: "도달 불가 dead code" 라고 판단한 분기가 실제로는 부모 컴포넌트가 prop 으로 직접 주입하는 경로였음. 삭제 후 기존 테스트가 회귀로 catch.

"제안 이슈 (논블로킹)" 섹션에 새 항목:
- **Dead code 의심 분기 삭제** — 삭제 전 다음 2가지 확인 권고:
  1. **사용처 grep** — 해당 prop / 분기 조건이 호출하는 코드 전체에서 어디서 set 되는지 (`Grep` 으로 prop 이름 + 분기 조건 키워드).
  2. **테스트 prop 직접 주입 패턴** — 기존 테스트가 부모 컴포넌트를 거치지 않고 prop 을 직접 주입하는 경우, 분기는 도달 가능. 테스트 파일에서 해당 prop 직접 set 여부 확인.

reviewer 가 diff 에서 "분기 삭제" 패턴 (if 문 + 본문 같이 제거) 발견 시 위 검증이 명세에 명시됐는지 확인 — 없으면 `⚠️` 제안.

### B. `.claude/agents/implementor.md`

**B-1. "안 하는 것" 섹션 또는 별도 "검증 명령" 섹션에 Bash 동기 결과 패턴 추가**

관찰된 케이스: 단순 `curl -sf http://localhost:3000/login` 도 timeout protection 으로 background task 가 되어 동기적 응답 못 받음.

추가 내용:
- 검증용 짧은 HTTP/CLI 명령은 다음 둘 중 하나:
  - 명시적 `timeout 5 curl ...` (또는 적절한 짧은 timeout 수치) — Bash 자동 background 회피.
  - 또는 cmux browser eval — 결과를 String(JSON.stringify(...)) 로 강제.
- 단순 `curl` / `sleep` 단독 호출 금지 — background 진입으로 동기적 검증 흐름 끊김.

### C. `CLAUDE.md`

**C-1. 안티패턴 표에 2개 추가** (이 repo CLAUDE.md 의 `## 안티패턴` 섹션):
- ❌ Dead code 판정 시 사용처 grep + 테스트 prop 직접 주입 확인 누락 — 부모가 prop 으로 set 하는 분기를 "도달 불가" 로 오판해 삭제하면 기존 테스트가 회귀로 catch.
- ❌ 검증용 단순 `curl` / `sleep` — Bash 자동 background 진입으로 동기 결과 못 받음. `timeout 5 curl ...` 또는 cmux browser eval 사용.

## TDD 검증

### Red (반드시 실패해야 함)

```bash
grep -E '사용처 grep|테스트 prop 직접 주입' .claude/agents/reviewer.md
grep -E 'timeout [0-9]+ curl|cmux browser eval' .claude/agents/implementor.md
grep -E 'Dead code 판정|단순 curl' CLAUDE.md
```

매칭이 1개라도 있으면 즉시 `❌ dead-code-bash-guard: pre-state mismatch` 보고 후 중단.

### Green (반드시 통과해야 함)

변경 적용 후 위 grep 모두 매칭 1개 이상.

### 회귀 가드

- 각 파일 헤더 트리 깨짐 없는지 `awk '/^#/' <file>` 확인.
- `git diff --stat HEAD` 로 산출 파일 3개만 수정 — 다른 파일 0.
- reviewer.md 의 출력 형식 블록 (```… ```) 깨지지 않았는지.

## 출력 형식

성공:
```
✅ dead-code-bash-guard: <변경 줄 수> lines changed, 3 files
Branch: feat/dead-code-bash-guard
```

실패:
```
❌ dead-code-bash-guard: <원인 한 줄>
단계: [Red/Green/Refactor]
```
