---
description: Explore → Plan(빈틈 진단) → Plan Review → TDD Execute(비동기 슬라이스) → Verify → Review → 한글 Commit → Context 정리 6단계 워크플로우
argument-hint: <짧은 요구사항 한 줄>
---

# Plan-Dev Workflow

> **철학**: 계획에 에너지를 쏟아 implementor 가 **1-shot 으로 성공**하게 한다. plan 이 부실하면 implementor 비용이 N 배로 돌아온다.

요청: $ARGUMENTS

<!-- TODO: 아래 빌드/테스트 명령을 프로젝트에 맞게 교체
     BUILD_CMD  예: ./gradlew build | npm run build | cargo build
     TEST_CMD   예: ./gradlew test  | npm test      | cargo test
-->

## Phase 1 — Plan & Slice

> **🚨 절대 규칙**: 이 단계는 **반드시 plan mode 안에서 작성하고 ExitPlanMode 로 사용자 승인을 받는다**. plan 을 인라인 메시지로만 출력하고 바로 implementor 띄우는 것은 **위반**.
>
> 위반 시 비용: 사용자가 슬라이스 분해 / 의존성 / 테스트 명세를 plan-mode UI 에서 검토하고 redirect 할 명확한 체크포인트를 잃게 됨. implementor 가 잘못 분해된 슬라이스로 작업 시작하면 되돌리기 비용 큼.

### 1-0. Explore (필수, 30초~2분)

요구사항을 받자마자 **반드시** 관련 코드 컨텍스트를 짧게 잡는다. 빈틈 진단의 전제가 되는 단계.

- 작은 변경(파일 1~3개 수준): 메인 세션에서 직접 `Glob` / `Grep` / `Read` 로 관련 파일 5~10개 확인
- 큰 변경(여러 모듈, 패턴 파악 필요): `Explore` 서브에이전트(`subagent_type: Explore`) 에 위임

산출 (메모 형태, plan 파일에 옮겨질 재료):
- 관련 파일 5~10개 경로
- 기존 패턴 한 줄 요약 (예: "AuthService는 Spring Security + JWT, 토큰 검증은 JwtFilter:42")
- 재사용 가능한 함수/유틸 식별

> Explore 없이 1-1로 직행하면 빈틈 질문이 추상적이 되어 사용자가 답하기 어렵다. 컨텍스트가 있어야 질문이 구체화된다.

### 1-1. 요구사항 빈틈 진단 + 명확화 (필수)

**전제**: 받은 요구사항은 항상 빈틈이 있다. 사용자가 명시 안 한 부분을 임의로 결정하지 말고, 그 빈틈을 명시적으로 식별해서 사용자에게 채워줄 기회를 준다.

#### 빈틈 체크리스트 (요구사항을 받으면 다음 항목을 점검)
- **Scope 경계**: 무엇이 포함이고 무엇이 제외인가? (예: "삭제 기능 추가" — soft delete? hard delete? cascade?)
- **Acceptance criteria**: 무엇이 "완료" 의 기준인가? (예: "빠르게" — 어느 정도? "잘 보여야" — 어디까지?)
- **Edge case**: 빈 상태 / 권한 없음 / 동시성 / 실패 시 동작은?
- **사용자 / 데이터 범위**: 본인만? 팀? 전체? 옛 데이터 호환?
- **의존성**: 기존 기능과의 충돌, 데이터 마이그레이션 필요 여부
- **테스트 전략**: 단위/통합/E2E 중 어디까지? 어느 케이스 보장?

#### 분류
체크리스트 결과 발견된 빈틈을 두 분류로 나눈다:

| 분류 | 처리 |
|---|---|
| **필수 명확화** (이걸 모르면 결과물이 사용자 의도와 정반대 일 수 있음) | **반드시 AskUserQuestion 으로 묻기** — "묻지 말고 진행" 지시가 있어도 예외. 묻지 않고 결정한 게 잘못이면 implementor 비용이 더 큼. |
| **재량 명확화** (어느 쪽이든 합리적 결과가 나옴) | "묻지 말고 진행" 지시 있으면 합리적 디폴트를 골라 plan 의 **Assumptions** 섹션에 명시. 없으면 AskUserQuestion. |

#### AskUserQuestion 사용 규칙
- **횟수 무제한** — 한 번에 1~4개씩, 빈틈이 모두 메워질 때까지 반복.
  - 답변을 받고 새 빈틈이 보이면 또 묻는다.
  - "이 정도면 충분하겠지" 로 임의 마감 금지 — Phase 1-2 진입 전에 1-1 체크리스트의 모든 항목이 명시/확정되어 있어야 한다.
- 각 질문은 선택지 2~4개로 구성 (사용자가 자유 입력하지 않게).
- 선택지에 trade-off 한 줄 description.
- 같은 turn 에 여러 질문 필요하면 한 메시지에 묶어서 (AskUserQuestion 의 questions 배열로) 호출.

> ⚠️ "질문 생략 지시" 를 "plan mode 생략" 으로 확장 해석하지 말 것. 1-2, 1-3, 1-4 는 별개이며 절대 생략 금지.

### 1-2. EnterPlanMode → plan 파일 작성 (MANDATORY)

`EnterPlanMode` 와 `ExitPlanMode` 는 deferred tool 이다. 먼저 다음을 호출해 schema 를 로드:
```
ToolSearch query="select:EnterPlanMode,ExitPlanMode"
```
그 후 `EnterPlanMode` 호출 → plan 파일 작성. 필수 섹션:

- **Context**: 왜 / 무엇을
- **Explored Files**: Phase 1-0에서 식별한 관련 파일 + 재사용 대상
- **Assumptions** (필수): Phase 1-1 에서 사용자가 명시 안 한 부분에 대해 내가 내린 결정.
  - 각 항목: `[가정] — 근거 — 사용자 의도와 다르면 redirect 필요` 형식.
  - 사용자가 plan 검토할 때 가장 먼저 보고 reject 할 수 있어야 함.
- **Open Questions** (선택): 빈틈이 남아있지만 구현 중에도 결정 가능한 항목.
- **Vertical Slices**: 작업을 독립 빌드·테스트 가능한 단위로 쪼개기
  - 각 슬라이스: 이름 / 산출 파일 / 의존 슬라이스 / 작성할 테스트 목록
  - 의존성 그래프 (병렬 가능 슬라이스 식별용)
  - **⛔ 안티패턴: Horizontal phases 금지** — "1단계: DB만, 2단계: service만, 3단계: UI만" 같은 layer 단위 분해는 금지. 각 슬라이스는 **cross-layer feature** 여야 한다.
  - 예 (OK): "회원가입 슬라이스" = UserEntity + SignupService + SignupController + signup.html + 단위/통합 테스트
  - 예 (NOK): "1단계 모든 entity, 2단계 모든 service" — 1단계 완료해도 end-to-end 동작 안 함
- **TDD Strategy**: 슬라이스별 Red 단계에서 작성할 테스트 명세
- **Verification**: 통합 검증 절차

**Plan 파일 간결성**: 200줄 이하 권장. implementor 가 자식 컨텍스트에서 통째로 읽기 좋게. 길어지면 슬라이스 추가 분해 신호.

### 1-3. Staff Engineer Plan Review (강력 권장, 단 1회)

ExitPlanMode 직전에 작성한 plan 을 **별도 컨텍스트의 Plan 서브에이전트**에 보여 비평 받는다.

- 호출: `Agent(subagent_type="Plan", prompt="다음 plan을 staff engineer 관점에서 비평. 슬라이스 분해/의존성/테스트 명세/Assumptions 검토. 5분 내, 치명적 결함 3개 이내로 추려서 보고.")`
- 비평 결과는 **메인 세션의 응답에 인용**해 사용자가 plan 과 함께 보고 reject/redirect 결정할 수 있게.
- 1회만. max 5분. 비평이 plan 보다 길어지면 가치 없음.
- 생략 가능 — 초소형 변경(슬라이스 1개, 파일 2~3개)이면 1-3 바로 1-4 로.

### 1-4. ExitPlanMode → 사용자 승인 (MANDATORY)

`ExitPlanMode` 호출로 plan 을 사용자에게 제출. **승인 받기 전에 Phase 2 진입 금지**.
- 사용자가 plan 을 수정 지시하면 Phase 1-2 로 회귀.
- 사용자가 명시적으로 "바로 진행" 등 승인하면 Phase 2 진입.

### 안티패턴 — 절대 하지 말 것
- ❌ plan 내용을 인라인 메시지로만 출력하고 implementor 호출
- ❌ "질문 생략 지시" 를 받았다고 plan mode 자체도 생략
- ❌ `EnterPlanMode` 가 deferred tool 이라는 호출 마찰을 이유로 단계 생략
- ❌ "사용자가 빨리 결과 보길 원할 것" 이라는 추측으로 승인 단계 단축
- ❌ Phase 1-0 Explore 생략하고 빈틈 질문을 추상적으로 던지기
- ❌ Horizontal phases 로 슬라이스 분해
- ❌ pane 모드에서 자식 pane 의 결과(✅ / ❌) **회수 전 머지** 시도 — 자식 작업이 완료되지 않은 worktree 머지 = 손실

## Phase 2 — TDD Execute (비동기)

**의존성 없는 슬라이스는 병렬, 의존 있는 것은 순차.**

권장 모델 구성: Plan 단계는 Opus, implementor 는 Sonnet. (선택사항 — 기본 설정으로도 OK)

병렬 슬라이스: 한 메시지에 여러 `Agent` 호출 (`subagent_type="implementor"`, `run_in_background=true`, `isolation="worktree"`).
- 각 implementor 는 `slice/<kebab-slice-name>` 브랜치 worktree 에서 Red→Green→Refactor 흐름 수행 후 `✅` 리턴.
- 완료 알림 받을 때마다 다음 의존 슬라이스 spawn.

순차 슬라이스: 동기 호출 (`run_in_background=false`).

**implementor 실패 시 (`❌` 리턴):**
1. **우선: Rewind → 재시도** — 실패 시도가 메인 컨텍스트에 남아 다음 reasoning 을 오염시키지 않게. rewind 후 동일 슬라이스 재호출 (자동, 1회).
2. rewind 가 가능하지 않거나 재시도도 `❌` → 해당 슬라이스 중단 + 사용자에게 원인 보고 후 지시 대기.

### Phase 2 모드 선택

| 모드 | 효과 |
|---|---|
| (미지정) / `--mode=subagent` | Agent(implementor) — 토큰 추적 ✓, 디폴트 |
| `--mode=pane` / `--mode=tmux` | tmux pane dispatch (기존 `--mode=pane` 그대로) |
| `--mode=cmux` | cmux workspace dispatch (신규) |
| `--mode=auto` | 환경 자동 감지 (TMUX 안 → tmux, cmux 안 → cmux, 둘 다 아니면 에러) |

기본은 위 흐름 (병렬 subagent + worktree). `--mode=pane` / `--mode=tmux` 옵션 시 implementor 를 **tmux pane** 으로, `--mode=cmux` 시 **cmux workspace** 로 dispatch — 사용자가 자식 작업에 직접 attach/모니터링/개입 가능.

호출:
```bash
scripts/dispatch-slice-pane.sh --slice=<kebab> --spec-file=<spec.md> \
  --mode=pane   [--model=<alias>]   # tmux pane
  --mode=cmux   [--model=<alias>]   # cmux workspace
  --mode=auto   [--model=<alias>]   # 환경 자동 감지
# stdout: {"pane":"<id>","worktree":"<path>","branch":"slice/<kebab>","driver":"tmux|cmux"}
```

`--model` 미지정 시 `DISPATCH_DEFAULT_MODEL` env → 그것도 없으면 `sonnet`. 보조 작업에 Opus 강제 회피.

사용자가 자식 pane 에 attach (직접 대화 가능):
```bash
tmux attach -t tmux-pane-mgr   # tmux: wrapper 가 알려준 세션명
```

부모는 완료 회수 (tmux, wrapper 는 변수로 추상화):
```bash
$wrapper wait-idle --pane=$pane --idle=10 --timeout=1800
$wrapper capture   --pane=$pane | tail -50 | grep -E '^(✅|❌)'
```

`✅` 회수 후에만 `git merge --no-ff slice/<kebab>`. 호출 예: `/plan-dev --mode=pane "<task>"`, `/plan-dev --mode=cmux "<task>"`, `/plan-dev --mode=auto "<task>"`.

**장점**: 사용자가 자식 작업 중간 개입 가능 / **단점**: 자식 토큰·비용은 부모 `token-stats` 로 추적 안 됨, 자식 pane/workspace 수만큼 머신 부하 → `CLAUDE_MAX_CHILD_PANES` (기본 5) 가드.

> ⚠️ 안티패턴: cmux 도 tmux 와 동일 — 자식 결과(`✅` / `❌`) **회수 전 머지** 금지.

## Phase 3 — Verify (loop)

완료된 slice worktree 를 순서대로 main 에 머지 후 verifier 호출.

**worktree 머지 방법:**
```bash
git merge --no-ff slice/<name>   # 각 완료 슬라이스마다
```
충돌 발생 시: 즉시 중단 → 충돌 파일 목록 사용자 보고 → 수동 해결 요청.

**verifier 루프:**
- 머지 완료 후 `verifier` 에이전트 호출.
- 실패 시 verifier 가 원인 + 수정안 제안 → 메인이 적용 → 재호출. 최대 5회.
- 5회 이상 실패 시 사용자에게 상황 보고하고 중단.

## Phase 3.5 — Review (선택)

verifier PASS 후 commit 전 코드 리뷰를 원하면 `reviewer` 에이전트 호출.

- 치명적 이슈 (SQL injection / 하드코딩 시크릿 / 민감 데이터 외부 송신 / `@Disabled`) 발견 시 해당 구현을 Phase 2 로 회귀.
- 제안 (논블로킹) 은 사용자가 판단.
- 생략 가능 — 빠른 이터레이션 시 Phase 4 로 바로.

## Phase 4 — Git 추천

- `commit-advisor` 에이전트 호출: `git diff` 분석 후 브랜치명 + **한글 커밋 메시지** 추천.
- 사용자 승인 후 `git add` + `git commit`. push 는 명시 요청 시에만.

## Phase 5 — Context 정리 (작업 종료 후)

작업이 끝나면 다음 입력을 한 줄로 추천한다 (사용자가 그대로 복사해 쓸 수 있게):

- **완전히 새 작업으로 넘어감 → `/clear`** (정석)
- **같은 도메인 후속 작업 이어감 → `/compact <남길 핵심 + 다음 방향>`**
- **부수 조사/탐색을 자식에서 격리 처리 → `/fork`** (부모 컨텍스트 보호)

응답 마지막 줄에 `다음 추천: <명령>` 형태로 항상 포함.

## 안전 규칙

- 슬라이스 의존성 분석 결과 의심스러우면 병렬 X, 순차로 강등.
- worktree 격리 활용 — 슬라이스 간 같은 파일 수정 가능성 있을 때 특히 중요.
- 테스트가 격리된 컨테이너/환경을 기동한다면 worktree 별 독립 인스턴스 필요 여부 확인.
- 공유 인프라 (DB, 큐 등) 를 점유하는 실행 명령은 worktree 병렬 사용 금지 — verify 는 build/test 만.
