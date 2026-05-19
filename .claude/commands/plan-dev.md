---
description: Phase 0~6 워크플로 — Session Start → Plan → TDD Execute → Verify → Review → Commit → Branch & Push → Context 정리
argument-hint: <짧은 요구사항 한 줄>
---

# Plan-Dev Workflow

> **철학**: 계획에 에너지를 쏟아 implementor 가 **1-shot 으로 성공**하게 한다. plan 이 부실하면 implementor 비용이 N 배로 돌아온다.

요청: $ARGUMENTS

<!-- TODO: 아래 빌드/테스트 명령을 프로젝트에 맞게 교체
     BUILD_CMD  예: ./gradlew build | npm run build | cargo build
     TEST_CMD   예: ./gradlew test  | npm test      | cargo test
-->

## Phase 0 — Session Start (자동)

세션 시작 직후 **즉시** 실행:
```bash
scripts/plan-dev-session.sh start
```
- start_ref(HEAD SHA), base_branch, work_branch, start_ts, start_pid, auto_branch 를 `.git/plan-dev-session.json` 에 기록.
- base_branch 우선순위: `origin/develop` > `origin/main` > `origin/master` > 로컬 develop/main/master.
- 현재 branch == base_branch → 작업 branch 로 분기 권장 (develop 위면 `git switch -c <type>/<slug>` 안내).
- 우회: `SKIP_PLAN_DEV_FINISH=1` (Phase 5 skip) / detached HEAD 시 exit 2 → 사용자 안내 후 중단.

## Phase 1 — Plan & Slice

> **🚨 절대 규칙**: plan mode 안에서 작성하고 ExitPlanMode 로 사용자 승인을 받는다.

### 1-0. Explore (필수, 30초~2분)
요구사항을 받자마자 관련 파일 5~10개 스캔. 빈틈 진단의 전제.

### 1-1. 빈틈 진단 + 명확화
체크리스트: Scope / Acceptance criteria / Edge case / 사용자·데이터 범위 / 의존성 / 테스트 전략.

| 분류 | 처리 |
|---|---|
| **필수 명확화** (결과가 의도와 정반대 가능) | 반드시 AskUserQuestion |
| **재량 명확화** (어느 쪽이든 합리적) | "묻지 말고 진행" 지시 있으면 Assumptions 에 기록 |

### 1-2. EnterPlanMode → plan 파일 작성
필수 섹션: Context / Explored Files / Assumptions / Vertical Slices / TDD Strategy / Verification.
**Plan 파일 200줄 이하** — 넘으면 슬라이스 추가 분해.

Slice 정의 시 **type 도 같이 결정**: `feat|fix|refactor|test|docs|chore`.

### 1-3. Plan Review (강력 권장, 단 1회)
`Agent(subagent_type="Plan")` 으로 staff engineer 비평 수령. 5분 이내.

### 1-4. ExitPlanMode → 사용자 승인 (MANDATORY)
승인 전 Phase 2 진입 금지.

## Phase 2 — TDD Execute (비동기)

**의존성 없는 슬라이스는 병렬, 의존 있으면 순차.**

병렬 슬라이스: 한 메시지에 여러 `Agent` 호출 (`subagent_type="implementor"`, `run_in_background=true`, `isolation="worktree"`).
- implementor 는 `<type>/<slug>` 브랜치 worktree 에서 Red→Green→Refactor 수행 후 `✅` 리턴.

**implementor 실패 시 (`❌` 리턴):**
1. Rewind → 재시도 (자동, 1회).
2. 재시도도 `❌` → 슬라이스 중단 + 사용자 보고.

### Phase 2 모드 선택

> ⚠️ `dispatch-slice-pane.sh` 의 `--mode` 디폴트는 **`auto`** (env `DISPATCH_DEFAULT_MODE` override). auto = `detect-pane-env.sh` 결과로 분기 — TMUX 안 → tmux, cmux 안 → cmux, default 환경 → die (사용자가 `--mode=subagent` 명시).

| 모드 | 효과 |
|---|---|
| `--mode=auto` (기본) | 환경 자동 감지 |
| `--mode=subagent` | Agent(implementor) — 부모 token-stats 추적 ✓, cmux 화면 분할 ✗ |
| `--mode=pane` / `--mode=tmux` | tmux pane dispatch |
| `--mode=cmux` | cmux workspace dispatch (부모 workspace 안 grid split — 사용자가 attach/시각화) |

**cmux 환경 권장**: 디폴트 auto 가 자동으로 cmux dispatch 선택 → 부모 workspace 안에 자식 surface 가 grid 분할되어 사용자가 화면에서 직접 진행 확인. 자식 토큰은 부모 token-stats 로 추적 안 됨 (trade-off).

호출 예:
```bash
scripts/dispatch-slice-pane.sh \
  --slice=<kebab> \
  --type=<feat|fix|refactor|test|docs|chore> \
  --spec-file=<spec.md> \
  [--mode=auto|cmux|tmux|subagent]   [--model=<alias>]
# stdout: {"pane":"...","worktree":"...","branch":"<type>/<slug>","driver":"tmux|cmux"}
```

`--type` 미지정 시 `DISPATCH_DEFAULT_TYPE` env → 없으면 `feat`.
`--model` 미지정 시 `DISPATCH_DEFAULT_MODEL` env → 없으면 `sonnet`.
`--mode` 미지정 시 `DISPATCH_DEFAULT_MODE` env → 없으면 `auto`.

사용자가 자식 pane 에 직접 attach:
```bash
tmux attach -t tmux-pane-mgr
```

pane 모드 완료 회수:
```bash
$wrapper wait-idle --pane=$pane --idle=10 --timeout=1800
$wrapper capture   --pane=$pane | tail -50 | grep -E '^(✅|❌)'
```

## Phase 3 — Verify (loop)

완료된 slice worktree 를 순서대로 rebase 후 verifier 호출.

**worktree 머지 방법 (rebase fast-forward, merge commit 없음):**
```bash
git rebase <type>/<slug>     # 각 완료 슬라이스마다
git branch -D <type>/<slug>  # 슬라이스 브랜치 삭제
git worktree remove .worktrees/<slug>
```
충돌 발생 시: 즉시 `git rebase --abort` → 충돌 파일 목록 사용자 보고.

**verifier 루프:**
- rebase 완료 후 `verifier` 에이전트 호출.
- 실패 시 원인 + 수정안 적용 → 재호출. 최대 5회.

## Phase 3.5 — Review (선택)

verifier PASS 후 commit 전 코드 리뷰를 원하면 `reviewer` 에이전트 호출.

- 치명적 이슈 → Phase 2 회귀.
- 제안(논블로킹)은 사용자 판단.

## Phase 4 — Git 추천

`commit-advisor` 에이전트 호출:
- `start_ref..HEAD` 의 커밋 메시지 전체 분석 → 가장 비중 큰 type + 작업 요약 slug → `<type>/<slug>` 브랜치명 추천.
- **한글 Conventional Commit** 메시지 + DOC_IMPACT 추천.
- 사용자 승인 후 `git add` + `git commit`.

## Phase 5 — Branch & Push

1. commit-advisor 추천의 `<type>/<slug>` 브랜치명 적용.
2. `scripts/finish-plan-dev.sh` 실행:
   - marker 읽기 → develop 있음/없음 분기 → `git push -u origin <branch>`.
   - develop 있으면: 현재 `<type>/<slug>` branch 를 remote 에 push.
   - develop 없음(main-only): main 직접 push.
3. 실패 시 사용자에게 명령 출력 후 중단.

우회:
- `SKIP_PLAN_DEV_FINISH=1` — 1회 우회 (exit 0 + "skipped").
- `DISABLE_PLAN_DEV_FINISH=1` — 영구 비활성화.

## Phase 6 — Context 정리

작업이 끝나면 다음 입력을 한 줄로 추천:

- **완전히 새 작업 → `/clear`**
- **같은 도메인 후속 작업 → `/compact <남길 핵심 + 다음 방향>`**
- **부수 조사/탐색 격리 → `/fork`**

**종료 직전** unlocked `worktree-agent-*` 자동 cleanup:
```bash
git worktree list --porcelain
# locked 없는 worktree-agent-<hash> 만 → git worktree remove --force + git branch -D
# locked worktree 는 건드리지 않음
```

응답 마지막 줄: `다음 추천: <명령>`

## 안전 규칙

- 슬라이스 의존성 분석 결과 의심스러우면 병렬 X, 순차로 강등.
- worktree 격리 — 슬라이스 간 같은 파일 수정 가능성 있을 때 특히 중요.

## 안티패턴 — 절대 하지 말 것

- ❌ plan 내용을 인라인 메시지로만 출력하고 implementor 호출
- ❌ "질문 생략 지시" 를 받았다고 plan mode 자체도 생략
- ❌ Phase 1-0 Explore 생략하고 빈틈 질문을 추상적으로 던지기
- ❌ Horizontal phases 로 슬라이스 분해
- ❌ `slice/<kebab>` branch 명 사용 — 반드시 `<type>/<slug>` (feat/..., fix/..., etc.)
- ❌ `git merge --no-ff slice/...` — rebase fast-forward + branch -D 사용
- ❌ pane 모드에서 자식 결과(`✅` / `❌`) **회수 전 머지** 시도
- ❌ Phase 5 우회 (`SKIP_PLAN_DEV_FINISH`) 를 기본값처럼 사용
