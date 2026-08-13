---
description: Phase 0~6 워크플로 — Session Start → Plan → TDD Execute → Verify → Review → Commit → Branch & Push → Context 정리
argument-hint: <짧은 요구사항 한 줄>
---

# Plan-Dev Workflow

> **철학**: 계획에 에너지를 쏟아 implementor 가 **1-shot 으로 성공**하게 한다. plan 이 부실하면 implementor 비용이 N 배로 돌아온다.

요청: $ARGUMENTS

## Phase 0 — Session Start (자동)

세션 시작 직후 **즉시** 실행:
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/plan-dev-session.sh start
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
| **재량 명확화** (어느 쪽이든 합리적) | 기본: **배치로 묶어 AskUserQuestion** (질문 1회에 여러 결정 항목). "묻지 말고 진행" 지시 또는 Auto Mode 시 가정 후 Assumptions 기록 |

**판단 기준**: 되돌리기 어렵거나(backward-incompatibility·데이터 손실 위험), 사용자가 메시지에 옵션을 명시적으로 제시했거나, 이전 turn 에서 명시한 선호와 충돌 가능하거나, 모델 스스로 "default 가 불명확한 임의 선택"이라고 인지하면 필수 명확화 → AskUserQuestion. **사용자 선택을 요구하는 option list 는 반드시 AskUserQuestion 으로 전달** (plain text dump 금지) — 단순 정보 enumeration 은 해당 없음.

> 🛑 **EnterPlanMode 진입 전 self-check**: Assumptions 에 들어갈 결정 항목 중 위 "정반대 가능" trigger 매치하는 게 있는가? 있으면 **EnterPlanMode 호출 전** AskUserQuestion 으로 확인. plan 파일 안 Assumptions 에 결정값 dump 금지 — 결정값은 ask 대상.

> 💡 **Phase 1-1 ↔ Phase 1-2 연결**: 1-1 의 Acceptance criteria 가 1-2 의 Goal Statement 의 source. 같은 항목을 측정 가능 form (grep/test/명령) 으로만 transform.

### 1-1.5. 설계 문서 작성 + 승인
조건부 블록(원인분석 / 구조 델타 / 결정 갈림길 / 기준선) 중 **하나라도 필요하면** `docs/design/<slug>.md` 를 먼저 쓰고 AskUserQuestion 으로 승인 → **2게이트**(설계 승인 → plan 승인). 전부 불필요하면 **fast path**(1게이트). commit type 으로 가르지 않는다. `hotfix` 는 착수 전 **골격만**(증상+가설+즉시조치) 승인하고 원인분석·재발방지는 사후. 승인 후 `plan-dev-session.sh set-design <절대경로>` 로 latch (Phase 5 게이트 입력). 판정 기준·절차·하네스 한계는 ➜ [설계 문서 가이드](./plan-dev/design-doc.md).

### 1-2. EnterPlanMode → plan 파일 작성
필수 섹션: **설계 문서 링크**(1-1.5 산출물, fast path 면 Context 한 단락으로 대체) / Explored Files / Assumptions / Vertical Slices / **Slice File Map** / **동작 스펙 (Behavior Spec)** / Verification / **Goal Statement**. plan 의 독자는 implementor/자식 surface — 사람이 판단할 내용은 설계 문서에 두고 plan 엔 링크만.
**Plan 파일 200줄 이하** — 넘으면 슬라이스 추가 분해.

**Slice File Map** — 각 슬라이스의 산출 파일 목록 (Write/Edit 대상). rebase fast-forward 충돌 예방 목적. 형식:
| Slice | Files | Mode | DOC_IMPACT |
|---|---|---|---|
| S1 | scripts/foo.sh, README.md | direct-edit | updated |
| S2 | .claude/agents/bar.md | dispatch (cmux, 사용자 시각화 요청) | none |

- `Mode` — **`Mode 컬럼 필수`**, 빈 셀 금지. 값: `direct-edit` / `dispatch(cmux)` / `dispatch(tmux)` / `workflow`. **기본은 환경 의존** (cmux 환경 = `dispatch(cmux)` 만, escape 포함) — canonical 규칙은 [cmux dispatch 가이드](./plan-dev/cmux-dispatch.md) 참조. `workflow` 는 opt-in (대규모/비시각, ➜ "Workflow 통합" 섹션).
- `DOC_IMPACT` — `none` / `updated` 중 plan 단계에 미리 결정 (commit 시점에 발견하면 hook 차단 후 재시도 비용).

Slice 정의 시 **type 도 같이 결정**: `feat|fix|refactor|test|docs|chore`. (commit type. **branch prefix 는 `feat`→`feature/`, 그 외 type 그대로** — dispatch 가 자동 매핑. commit 메시지엔 scope 안 씀: `feat: …` 형식.)

#### 동작 스펙 (Behavior Spec) — 사람이 승인하는 동작 계약
슬라이스별 **테스트 케이스명 목록** (시나리오 문장 나열, 본문·코드 없음). 이 목록이 implementor spec 의 "작성할 테스트 목록" 으로 그대로 전달된다.

- **역할 구분**: 동작 스펙 = 사람이 승인하는 동작 계약 (ExitPlanMode 리뷰 대상) / Goal Statement = 기계가 판정하는 완료 조건 (Phase 3 Verify 입력).
- **판단 기준** (규칙 아님): 동작 분기·상태 전이·에러 경로가 있는 슬라이스는 필수. 기계적 변경(rename·문서 이동·설정값)은 한 줄 사유로 생략 가능.
- 각 슬라이스의 동작 스펙에 **판정 주체**를 표기한다 — `기계`(테스트/machine-checks 로 판정) 또는 `사람`(육안·실행 검증). 같은 목록 안에서 둘을 구분하지 않으면 사람 검증 항목이 조용히 누락된다.

  예: `**S3** (tests/foo.sh) — 판정 주체: 기계` / `**S4** — 판정 주체: 사람. 문장 품질은 육안 판단`

#### Goal Statement — 측정가능 완료 기준
**목적**: Phase 1-1 의 Acceptance criteria 를 측정 가능 form 으로 transform 한 체크리스트. **Phase 3 Verify 에서 모델이 직접 실행**해 슬라이스 완료를 판정한다 (자동 loop 아님 — 모델이 매 verify 때 스스로 돌려보고 결과를 확인).

**형식** (plan 파일 마지막 섹션):
~~~markdown
## Goal Statement
<!-- machine-checks -->
~~~bash
grep -c "X" file | awk '$1>=3{exit 0}{exit 1}'
test -x scripts/foo.sh
~~~
<!-- /machine-checks -->
**Semantic goal**: 한 문장 자연어 — commit-advisor 메시지 + 사람 가독성.
~~~

**제약**:
- machine-checks 라인 = bash one-liner (exit 0 = PASS)
- **측정 가능** 만 — `grep` / `test` / `jq` / shell command 결과 기반
- 추상 표현 금지 (e.g. "품질 향상" ✗, `grep -c "X" file` ≥ 3 ✓)
- 전체 길이 ≤4000 chars

> 💡 **세션격리 latch**: plan 파일 작성 후 `${CLAUDE_PLUGIN_ROOT}/scripts/plan-dev-session.sh set-plan <plan-mode 가 알려준 plan 파일 절대경로>` 실행 권장 — dispatch gate 가 이 세션의 plan 을 결정적으로 latch 해 다른 repo 의 동시 세션 plan 과 섞이지 않게 한다 (빠뜨려도 최초 dispatch 가 자동으로 latch 하니 필수는 아님).

### 1-3. Plan Review (강력 권장, 단 1회)
`Agent(subagent_type="Plan")` 으로 staff engineer 비평 수령. 5분 이내.
- **opt-in 시 judge panel 격상**: 사용자가 workflow 명시 / 대규모 plan 이면 단일 Plan 대신 `Workflow` 툴로 N개 독립 비평 → 합성 (➜ "Workflow 통합" A).

**충돌 사전 점검**: Slice File Map 의 파일 교집합 존재 시 그 슬라이스들은 의존성 있음으로 분류 — 병렬 X, 순차로 강등하거나 단일 슬라이스로 병합.

> 📎 환경별 Mode 룰 상세: [cmux dispatch 가이드](./plan-dev/cmux-dispatch.md)

### 1-4. ExitPlanMode → 사용자 승인 (MANDATORY)
승인 전 Phase 2 진입 금지.
Assumptions 가 비어있지 않으면 ExitPlanMode 승인 요청 텍스트에 **가정 요약** 을 포함한다 — 사용자가 승인과 함께 가정을 일괄 확인.

슬라이스 수 확정 후 progress 시작:
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/plan-dev-progress.sh start --total=<N>
```

## Phase 2 — TDD Execute (비동기)

> **진단 기록 가이드**: Phase 2 진행 중 발견한 진단·결정·우회는 plan 파일 (200줄 한도면 별도 `<plan>-notes.md`) 에 즉시 기록. 세션이 중간에 끊겨도 다음 세션이 1턴 만에 컨텍스트 복원 가능.

**의존성 없는 슬라이스는 병렬, 의존 있으면 순차** — subagent(`Agent` 호출, `run_in_background=true`, `isolation="worktree"`)든 dispatch(cmux/tmux)든 **감시 루프 시작 전에 전부 dispatch**(launch lock 이 동시 호출 race 방지, dispatch→회수→다음 dispatch 순차 진행은 병렬 이점 소멸). implementor 는 `<type>/<slug>` worktree 에서 Red→Green→Refactor 후 `✅` 리턴.

**implementor 실패 시 (`❌` 리턴):**
1. Rewind → 재시도 (자동, 1회).
2. 재시도도 `❌` → 슬라이스 중단 + 사용자 보고.

> 📎 상세: [Phase 2 모드 선택 · cmux dispatch 가이드](./plan-dev/cmux-dispatch.md)

### 애드혹 편집 (Slice File Map 밖 요청)
plan 승인(1-4 ExitPlanMode) 후, 원래 Slice File Map 에 없던 편집 요청이 사용자로부터 올 수 있다 — 작은 단발 수정이라도:

- **부모 세션에서 direct-edit 하지 말 것.** `dispatch-slice-pane.sh` 로 짧은 인라인 spec 을 만들어 새 슬라이스처럼 dispatch — maintainer(부모) 의 context 를 보존한다.
- gate(`enforce-dispatch-gate.sh`) 는 plan 승인 후의 이런 애드혹 dispatch 를 이미 허용한다 (plan_file latch 로 세션이 격리돼 있으므로 추가 조치 불필요).
- 규모가 작아 보여도 예외 없음 — "한 줄만 고치면 되는데" 라는 판단이 반복적 direct-edit 로 누적되면 부모 context 낭비가 커진다.
- 📎 상세: [cmux dispatch 가이드 — 애드혹 dispatch](./plan-dev/cmux-dispatch.md)

## Phase 3 — Verify (loop)

완료된 slice worktree 를 순서대로 **rebase fast-forward** 후 verifier 호출. (`git merge` 금지 — merge 커밋이 S라벨·잡음 누출. 📎 [cmux dispatch 가이드](./plan-dev/cmux-dispatch.md))

**verifier 루프:**
- rebase 완료 후 `verifier` 에이전트 호출.
- 실패 시 원인 + 수정안 적용 → 재호출. 최대 5회.
- plan 의 **Goal Statement** `<!-- machine-checks -->` 체크리스트를 모델이 직접 실행해 PASS 확인 (fail 항목 있으면 fix 후 재실행).

> 🔬 **통합 테스트 의무** (격리 dispatch 사용 시): rebase 후 verifier 는 **슬라이스별 격리 테스트** (각 worktree 안에서 PASS 확인된 것) + **전체 통합 테스트** (rebase 머지 후 부모 branch 에서 BUILD + TEST 전체 실행) 둘 다 실행. 격리 PASS 인데 통합 FAIL = 슬라이스 간 숨은 의존성 노출 — root cause 분석 후 fix 슬라이스 추가 또는 슬라이스 재분해. 격리만 보고 PASS 처리 금지.

## Phase 3.5 — Review (선택)
verifier PASS 후 commit 전 코드 리뷰를 원하면 `reviewer` 에이전트 호출.

- 치명적 이슈 → Phase 2 회귀.
- 제안(논블로킹)은 사용자 판단.
- **opt-in 시 multi-dimension 적대 verify 격상**: 단일 reviewer 대신 `Workflow` 툴로 dimension 별 finder + finding 별 적대 다수결 (➜ "Workflow 통합" A).

## Phase 4 — Git 추천
### 4-0. 설계 문서 실측 write-back (필수 — 1-1.5 를 거친 세션)
`docs/design/<slug>.md` 의 `## 6. 결과` 에서 `실측` 칸을 채운다. 측정 불가면 `미검증 — 재발 감시 중` 명시 — 빈 칸·`TODO`·괄호 자리표시자는 Phase 5 게이트가 차단. 이게 없으면 문서에 `예상`만 남아 인수인계·이력서 자료로 못 쓴다. 형태 대응은 ➜ [설계 문서 가이드](./plan-dev/design-doc.md).

### 4-1. commit-advisor
`commit-advisor` 에이전트 호출:
- `start_ref..HEAD` 의 커밋 메시지 전체 분석 → 가장 비중 큰 type + 작업 요약 slug → `<type>/<slug>` 브랜치명 추천.
- **한글 Conventional Commit** 메시지 + DOC_IMPACT 추천.
- 세션에 내부 라벨/머지 잡음 커밋이 쌓였으면 commit-advisor 가 squash 추천 → 깨끗한 단일/소수 커밋. **S1/S2 라벨은 최종 히스토리에 남기지 않는다.**
- 사용자 승인 후 `git add` + `git commit`. 커밋 명령은 marker touch 를 번들:
  ```
  DOC_IMPACT=<none|updated> git commit -m "..." && touch "$(git rev-parse --git-common-dir)/plan-dev-commit-advised"
  ```
  `record-commit-advised` hook(PostToolUse Task|Agent) 이 commit-advisor 호출을 감지해 이 marker 를 자동 기록하는 게 primary — 이 번들은 belt(hook 미배선/비-plugin 환경 대비).

## Phase 5 — Branch & Push

1. commit-advisor 추천의 `<type>/<slug>` 브랜치명 적용.
2. `${CLAUDE_PLUGIN_ROOT}/scripts/finish-plan-dev.sh` 실행:
   - marker 읽기 → develop 있음/없음 분기 → `git push -u origin <branch>`.
   - develop 있으면: 현재 `<type>/<slug>` branch 를 remote 에 push.
   - develop 없음(main-only): main 직접 push.
3. 실패 시 사용자에게 명령 출력 후 중단.

우회:
- `SKIP_PLAN_DEV_FINISH=1` — 1회 우회 (exit 0 + "skipped").
- `DISABLE_PLAN_DEV_FINISH=1` — 영구 비활성화.

## Phase 6 — Context 정리

작업 종료 후 **`fork` 스킬을 직접 호출**한다 (텍스트로 추천만 하지 않는다). Skill(fork) 이:
- 세션의 잔여 정리(worktree cleanup 등) + 작업 요약을 수행하고,
- 마지막 줄에 다음 명령(`/clear` 또는 `/compact <남길 핵심>`)을 추천한다.

> ℹ️ 이 단계는 **콘텐츠 전용 강제**다. `/fork` 는 Skill = 모델이 호출하는 것이라 hook 으로 호출을 강제할 수 없다(Stop hook 은 turn 재개만 가능, 액션 지정 불가). 따라서 이 지시를 반드시 따를 것.

> 📎 bash 예시 (progress show · worktree cleanup): [cmux dispatch 가이드](./plan-dev/cmux-dispatch.md)

> 📎 상세: [Workflow 통합 가이드](./plan-dev/workflow-integration.md)

> 📎 설계 문서 템플릿·블록 조건·mermaid 규약: [설계 문서 가이드](./plan-dev/design-doc.md)

## 안전 규칙
- 슬라이스 의존성 분석 결과 의심스러우면 병렬 X, 순차로 강등.
- worktree 격리 — 슬라이스 간 같은 파일 수정 가능성 있을 때 특히 중요.

> 📎 전체 목록: [안티패턴 레퍼런스](./plan-dev/antipatterns.md)
