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

- 단축키 / 라우팅 / 전역 listener 류 작업은 `page.tsx` / `layout.tsx` 같은 **상위 컨테이너 컴포넌트** 를 explore 기본 포함.
- 관찰된 패턴: 자식 컴포넌트만 보고 단축키를 새로 구현 → 상위에 같은 단축키가 이미 있어 회귀 발생. plan 단계에서 catch 못하면 implementor 단계 비용 N 배.

### 1-1. 빈틈 진단 + 명확화
체크리스트: Scope / Acceptance criteria / Edge case / 사용자·데이터 범위 / 의존성 / 테스트 전략.

> ⚠️ **Auto Mode 우선순위**: system prompt 에 "Auto Mode Active" 가 있어도 — 본 룰의 "필수 명확화" 는 **항상 우선**. Auto Mode 는 오직 "재량 명확화" 의 default 만 결정 (= "묻지 말고 가정 후 Assumptions 기록"). 결과가 의도 정반대 일 수 있는 결정은 Auto Mode 무관 반드시 AskUserQuestion.

| 분류 | 처리 |
|---|---|
| **필수 명확화** (결과가 의도와 정반대 가능) | 반드시 AskUserQuestion |
| **재량 명확화** (어느 쪽이든 합리적) | "묻지 말고 진행" 지시 있으면 Assumptions 에 기록 |

"정반대 가능" trigger 예시 — **이 중 하나라도 해당하면 필수 명확화**:
- 사용자가 메시지에 옵션을 **명시적으로** 제시 (예: "A 또는 B", "`.plans/` 또는 `specs/`") → 의도 있음 → ask
- 모델이 "default 가 명확하지 않다" 고 인지한 결정 (= 임의 선택)
- 해당 결정이 backward-incompatibility / 사용자 인터페이스 변경 / 데이터 손실 위험 동반
- 사용자가 이전 turn 에서 명시한 선호와 다른 선택이 나올 가능성

> 🛑 **EnterPlanMode 진입 전 self-check**: Assumptions 에 들어갈 결정 항목 중 위 "정반대 가능" trigger 매치하는 게 있는가? 있으면 **EnterPlanMode 호출 전** AskUserQuestion 으로 확인. plan 파일 안 Assumptions 에 결정값 dump 금지 — 결정값은 ask 대상.

### 1-2. EnterPlanMode → plan 파일 작성
필수 섹션: Context / Explored Files / Assumptions / Vertical Slices / **Slice File Map** / TDD Strategy / Verification.
**Plan 파일 200줄 이하** — 넘으면 슬라이스 추가 분해.

**Slice File Map** — 각 슬라이스의 산출 파일 목록 (Write/Edit 대상). rebase fast-forward 충돌 예방 목적. 형식:
| Slice | Files | Mode | DOC_IMPACT |
|---|---|---|---|
| S1 | scripts/foo.sh, README.md | dispatch | updated |
| S2 | .claude/agents/bar.md | direct-edit (단일 파일 <20줄) | none |

- `Mode` — **`Mode 컬럼 필수`**, 빈 셀 금지. `dispatch` (cmux/tmux/subagent dispatch) / `direct-edit` (부모가 직접 Edit) 중 슬라이스 처리 방식 plan 단계에 미리 결정. **`direct-edit 선택 시 1줄 justification 의무`** (예: "단일 파일 <20줄", "config 한 줄 변경", "시각화 가치 없음").
- `DOC_IMPACT` — `none` / `updated` 중 plan 단계에 미리 결정 (commit 시점에 발견하면 hook 차단 후 재시도 비용).

Slice 정의 시 **type 도 같이 결정**: `feat|fix|refactor|test|docs|chore`.

### 1-3. Plan Review (강력 권장, 단 1회)
`Agent(subagent_type="Plan")` 으로 staff engineer 비평 수령. 5분 이내.

**충돌 사전 점검**: Slice File Map 의 파일 교집합 존재 시 그 슬라이스들은 의존성 있음으로 분류 — 병렬 X, 순차로 강등하거나 단일 슬라이스로 병합.

> 🚀 **dispatch default 룰** (cmux 환경): 모든 슬라이스는 **dispatch default**. `direct-edit` 은 명시 justification 필요. 사유 카테고리:
> - 단일 파일 + 변경 <20줄 → direct-edit 허용
> - 사용자가 화면에서 자식 진행을 볼 가치 없는 mechanical 변경 → direct-edit 허용
> - 그 외 — Mode 컬럼에 `dispatch (cmux)` 명시 후 `scripts/dispatch-slice-pane.sh --mode=cmux` 호출.
>
> 본 repo 의 settings.json 은 cmux 환경에서 Edit/Write 누적 2회 시 hook 으로 차단 (`CMUX_EDIT_BURST_STRICT=1` inline). 우회는 SKIP env 명시.

### 1-4. ExitPlanMode → 사용자 승인 (MANDATORY)
승인 전 Phase 2 진입 금지.

슬라이스 수 확정 후 progress 시작:
```bash
scripts/plan-dev-progress.sh start --total=<N>
```

## Phase 2 — TDD Execute (비동기)

> **진단 기록 가이드**: Phase 2 진행 중 발견한 진단·결정·우회는 plan 파일 (200줄 한도면 별도 `<plan>-notes.md`) 에 즉시 기록. 세션이 중간에 끊겨도 다음 세션이 1턴 만에 컨텍스트 복원 가능.

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

#### cmux dispatch 동작 모델 (진단 가이드)

- `dispatch-slice-pane.sh --mode=cmux` 호출 → `scripts/cmux-pane.sh launch` 가 cmux new-split 으로 surface 생성 + zsh + 자식 `claude --permission-mode bypassPermissions` 실행 + spec prompt 송신.
- spec prompt 송신은 자동으로 **`--enter-count=2`** 적용 (Claude TUI paste mode 끝의 첫 Enter 는 newline 으로 처리되어 명령 실행 안 됨 — 추가 Enter 필요). 단, **cmux 신규 surface 가 PTY detached 인 케이스** 에서는 첫 Enter 만으로 PTY 가 활성화되고 명령 실행이 안 될 수 있음.
- 진단 시퀀스 (자식이 진행 안 하는 듯할 때):
  1. `cmux tree | grep surface:<N>` — surface 살아 있는지.
  2. `cmux read-screen --surface surface:<N>` — `Terminal surface not found` 이면 detached. `cmux send-key --surface surface:<N> Enter` 1~2회로 활성화.
  3. 활성화 후 자식이 spec prompt 받은 상태 (`✳ Forming…` / `Undulating…` 등 thinking) 이면 정상.
- 부모가 회수: `scripts/cmux-pane.sh wait-idle --pane=surface:<N> --idle=15 --timeout=900` → `cmux read-screen --surface surface:<N> --lines 30 | grep -E '^(✅|❌)'`.
- 사용자가 직접 자식 화면 보기: cmux 사이드바의 surface 탭 클릭.

#### Dispatch wrapper 가용성 검증 (회복력 룰)

- (a) wrapper PWD-relative path (`scripts/dispatch-slice-pane.sh`) 가 안 보이면 → **알려진 절대경로** (`~/scripts/dispatch-slice-pane.sh` 글로벌 설치 결과, 또는 SessionStart system-reminder 가 노출한 driver 경로) 로 직접 호출 시도. 검색 결과 부재 ≠ 실행 불가.
- (b) 검색 권한 거부 (find/glob/grep 막힘) ≠ 실행 권한 거부. 검색 막혔다고 실행도 막혔다고 단정 금지 — 절대경로 호출 자체는 별도 권한.
- (c) classifier/sandbox 가 권한 거부 메시지에 "사용자에게 설명/확인" 안내를 포함하면 그대로 따른다. 자동 fallback 금지.
- (d) 사용자가 명시 선택한 mode 의 **핵심 가치** (cmux=시각화, subagent=토큰 추적, pane=tmux 격리) 를 날리는 fallback 결정은 **AskUserQuestion 으로 확인**. 자동 결정 금지.

#### Spec 파일 위치 (컨벤션)

- **위치**: `.claude/specs/<slug>.spec.md` (slug = `--slice=<slug>` 와 동일 kebab-case)
- **명명**: `<slug>.spec.md` 접미사 사용
- **추적**: commit 가능 (`b2ad060` 의 reference spec 들처럼 보존 OK). 일회용도 무방, 사용자가 정리.
- **금지**: `/tmp/<slug>-spec.md` 같은 외부 임시 디렉토리 — classifier 가 같은 turn 의 Write 추적 못 해 dispatch 거부될 수 있음.

호출 예:
```bash
scripts/dispatch-slice-pane.sh \
  --slice=<kebab> \
  --type=<feat|fix|refactor|test|docs|chore> \
  --spec-file=.claude/specs/<kebab>.spec.md \
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

슬라이스 ✅ 확인 후:
```bash
scripts/plan-dev-progress.sh tick --slug=<slice>
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

> 🔬 **통합 테스트 의무** (격리 dispatch 사용 시): rebase 후 verifier 는 **슬라이스별 격리 테스트** (각 worktree 안에서 PASS 확인된 것) + **전체 통합 테스트** (rebase 머지 후 부모 branch 에서 BUILD + TEST 전체 실행) 둘 다 실행. 격리 PASS 인데 통합 FAIL = 슬라이스 간 숨은 의존성 노출 — root cause 분석 후 fix 슬라이스 추가 또는 슬라이스 재분해. 격리만 보고 PASS 처리 금지.

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

**종료 직전** 진행률 최종 확인:
```bash
scripts/plan-dev-progress.sh show
```

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
- ❌ `PROGRESS_DRY_RUN=1` 을 기본값처럼 켜두기 (테스트 전용, 실제 push 억제됨)
- ❌ 두 슬라이스가 같은 파일의 같은 영역 수정 — plan 단계에서 Slice File Map 으로 의존성 분석 후 순차 강등 또는 병합.
- ❌ Phase 1-0 Explore 에서 `page.tsx` / `layout.tsx` 같은 상위 컨테이너 컴포넌트 제외 — 단축키·라우팅·전역 listener 중복 구현 회귀로 비용 폭증.
- ❌ plan 에 cmux dispatch 의도된 슬라이스를 Phase 2 진입 후 "가벼우니 직접 Edit" 로 강등하면서 사용자에게 명시 공지 안 함 — Slice File Map 의 `Mode` 컬럼과 어긋남.
- ❌ dispatch wrapper PWD 검색 실패 시 절대경로 호출 시도 없이 subagent fallback 자동 결정 — 사용자 명시 mode 의 핵심 가치 (시각화 등) 사라짐. AskUserQuestion 으로 확인.
- ❌ 검색 권한 거부를 실행 권한 거부로 단정 — system-reminder / CLAUDE.md / 메모리에 절대경로 노출돼 있으면 그 경로로 직접 호출 시도.
- ❌ classifier/sandbox "사용자에게 설명" 안내 무시하고 자동 fallback — 권한 확장 또는 우회 명시 요청 필요.
- ❌ 작업 중 발견한 별개 버그를 단발 보고만 하고 다음 turn 으로 떠넘기기 — 임시 cleanup 가능하면 즉시 수행 + AskUserQuestion 으로 follow-up plan-dev 진입 여부 확인.
- ❌ dispatch spec-file 을 `/tmp/<slug>-spec.md` 등 repo 밖 임시 디렉토리에 쓰기 — classifier 가 같은 turn 의 Write 추적 못 해 dispatch 거부 위험. `.claude/specs/<slug>.spec.md` 사용.
- ❌ Slice File Map 없이 슬라이스 분해 — rebase fast-forward 시 같은 파일 영역 충돌로 부모 수동 복구 비용 발생.
- ❌ Auto Mode (system prompt) 를 "필수 명확화도 묻지 말고 가정으로 처리" 로 해석 — Auto Mode 는 "재량 명확화" 의 default 만. "정반대 가능" trigger 매치 결정은 Auto Mode 무관 반드시 AskUserQuestion.
- ❌ 사용자가 메시지에 명시한 옵션 (A 또는 B) 을 Assumptions 에서 임의 선택 후 ExitPlanMode — 사용자 의도 있음 신호. 반드시 AskUserQuestion 으로 확인.
- ❌ Slice File Map 의 Mode 컬럼 비워두거나 모호하게 ("적당히") 두기 — plan 단계 dispatch/direct-edit 분기 흐려져 Phase 2 진입 후 디폴트로 direct-edit 흐름. 빈 셀 = ExitPlanMode 차단 신호로 self-check.
- ❌ cmux 환경에서 justification 없이 direct-edit 선택 — 시각화/병렬 가치 날림. dispatch default + direct-edit 사유 명시 룰 따름.
