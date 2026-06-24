# Slice S1 — plan-dev.md + README 강화

너는 implementor 다. TDD R→G→R. 작업 끝에 `✅ plan-dev-enhance:` 또는 `❌ plan-dev-enhance:` 출력.

## 작업 디렉토리

`/Users/sshworld/develop/claude-best-practice/.worktrees/plan-dev-enhance`

시작 즉시 `pwd` 출력 → 이 경로와 일치 안 하면 즉시 `❌ plan-dev-enhance: cwd mismatch` 보고 후 중단. `cd` / `pushd` 금지.

## 산출 파일

- `.claude/commands/plan-dev.md`
- `README.md`

다른 파일 수정 금지 (다른 슬라이스가 동시 수정 중일 수 있음).

## 변경 명세

### A. `.claude/commands/plan-dev.md`

**A-1. Phase 1-0 Explore 섹션 보강** (지금은 "관련 파일 5~10개 스캔" 만 있음)
다음 체크리스트 추가:
- 단축키 / 라우팅 / 전역 listener 류 작업은 `page.tsx` / `layout.tsx` 같은 **상위 컨테이너 컴포넌트** 를 explore 기본 포함.
- 관찰된 패턴: 자식 컴포넌트만 보고 단축키를 새로 구현 → 상위에 같은 단축키가 이미 있어 회귀 발생. plan 단계에서 catch 못하면 implementor 단계 비용 N 배.

**A-2. 1-2 Slice File Map 표 컬럼 확장**
현재 표:
```
| Slice | Files |
|---|---|
| S1 | scripts/foo.sh, README.md |
| S2 | .claude/agents/bar.md |
```
다음 컬럼을 **추가** (Files 옆에 Mode, DOC_IMPACT 추가, 예시 행도 같이):
- `Mode` — `dispatch` / `direct-edit` 중 슬라이스 처리 방식 미리 결정.
- `DOC_IMPACT` — `none` / `updated` 중 plan 단계에 미리 결정 (commit 시점에 발견하면 hook 차단 후 재시도 비용).

**A-3. Phase 2 시작 부분 — "진단 기록 가이드" 단락 추가**
"의존성 없는 슬라이스는 병렬..." 바로 위 또는 아래에 새 문단:
- Phase 2 진행 중 발견한 진단·결정·우회는 plan 파일 (200줄 한도면 별도 `<plan>-notes.md`) 에 즉시 기록.
- 세션이 중간에 끊겨도 다음 세션이 1턴 만에 컨텍스트 복원 가능.

**A-4. 안티패턴 목록에 2개 추가** (`## 안티패턴 — 절대 하지 말 것` 섹션):
- ❌ Phase 1-0 Explore 에서 `page.tsx` / `layout.tsx` 같은 상위 컨테이너 컴포넌트 제외 — 단축키·라우팅·전역 listener 중복 구현 회귀로 비용 폭증.
- ❌ plan 에 cmux dispatch 의도된 슬라이스를 Phase 2 진입 후 "가벼우니 직접 Edit" 로 강등하면서 사용자에게 명시 공지 안 함 — Slice File Map 의 `Mode` 컬럼과 어긋남.

### B. `README.md`

A-1 / A-2 / A-3 와 동일 키워드가 README 의 plan-dev 흐름 설명에 들어가도록 동기화. 추가된 키워드 (`page.tsx` / `Mode` / `진단 기록`) 가 README 에 최소 한 번씩 등장. 필요 분량만 추가 — README 폭증 금지.

## TDD 검증 (Red → Green)

### Red (반드시 실패해야 함)

작업 시작 직후 다음을 실행해 **모두 매칭 없음** 인지 확인:
```bash
grep -E 'page\.tsx|layout\.tsx' .claude/commands/plan-dev.md
grep -E '^\|\s*Slice\s*\|\s*Files\s*\|\s*Mode' .claude/commands/plan-dev.md
grep -E '진단 기록' .claude/commands/plan-dev.md
grep -E 'page\.tsx' README.md
```

매칭이 1개라도 있으면 즉시 `❌ plan-dev-enhance: pre-state mismatch` 보고 후 중단.

### Green (반드시 통과해야 함)

변경 적용 후 위 grep 모두 매칭 1개 이상.

### 회귀 가드

- 변경 후 `awk '/^##/' .claude/commands/plan-dev.md` 로 헤더 트리 깨짐 없는지.
- `wc -l .claude/commands/plan-dev.md` 가 250 줄을 넘지 않는지 (현재 ~215 + 추가).
- 다른 슬라이스 파일 (`.claude/agents/*`, `.claude/skills/*`, `CLAUDE.md`) 절대 수정 안 함 — `git diff --stat HEAD` 로 확인.

## 출력 형식

성공:
```
✅ plan-dev-enhance: <변경 줄 수> lines changed, 2 files (plan-dev.md, README.md)
Branch: feat/plan-dev-enhance
```

실패:
```
❌ plan-dev-enhance: <원인 한 줄>
단계: [Red/Green/Refactor]
```
