# CLAUDE.md — claude-best-practice repo 가이드

이 repo 자체를 작업할 때 Claude 가 따라야 할 규칙. (이 repo 가 제공하는 워크플로의 사용법은 [README.md](./README.md) 참조)

## 정체성

- 본 repo 는 **개인용 Claude Code 워크플로 모음**. 사용자(@shsong) 가 다양한 프로젝트에 글로벌/로컬로 깔아 쓰는 공통 자산.
- 핵심 가치: **"콘텐츠(commands/agents/skills) + 하네스(settings/hooks)" 이중 방어**. 모델 가이드와 런타임 강제를 같이 둔다.
- 베이스: [shanraisshan/claude-code-best-practice](https://github.com/shanraisshan/claude-code-best-practice).

## 변경 시 원칙

1. **콘텐츠와 하네스 짝 맞추기**
   - 새 룰을 도입할 때 콘텐츠(에이전트 프롬프트)만 두지 말고, 가능하면 하네스(hook/permission)로 강제력을 같이 부여한다.
   - 반대로 하네스만 있고 콘텐츠 가이드가 없으면 사용자가 차단 이유를 모름 → 양쪽 다 명시.

2. **강제는 "판단 강제"로 설계**
   - 일률 차단/통과보다, 사용자에게 매번 한 번의 의식적 결정을 시키는 방향이 낫다.
   - 예: `enforce-doc-sync.sh` 는 `DOC_IMPACT=none|updated` 환경변수로 결정을 명시하게 함.

3. **plan 파일은 200줄 이하**
   - implementor 가 자식 컨텍스트에서 통째로 읽기 좋게.
   - 길어지면 슬라이스를 더 쪼개는 신호.

4. **Vertical slice — Horizontal phases 금지**
   - 슬라이스는 cross-layer feature 단위 (DB+service+UI 같이).
   - "1단계: 모든 entity, 2단계: 모든 service" 식 분해 금지.
   - 슬라이스별 산출 파일 목록(`Slice File Map`) 을 plan 에 명시. 다른 슬라이스와 같은 파일·같은 영역 수정 시 단일 슬라이스로 병합 또는 순차 강등.

5. **README/CLAUDE.md 동기화**
   - 본 repo 안에서 `.claude/` 또는 `install.sh` 의 동작이 바뀌면 README.md 의 해당 섹션을 같이 업데이트.
   - DOC 영향 평가는 본 repo 의 commit 에도 동일하게 적용 — `DOC_IMPACT` prefix 사용.

## 파일별 책임 분리

| 파일 | 책임 |
|---|---|
| `.claude/commands/plan-dev.md` | 사용자 entry point. 단계별 가이드와 안티패턴. |
| `.claude/commands/parallel-consult.md` | 자식 Claude pane 띄워 1회 질의응답. |
| `.claude/agents/implementor.md` | TDD Red→Green→Refactor. subagent / tmux pane 모드 양쪽 지원. |
| `.claude/agents/verifier.md` | Read-only 빌드/테스트. 코드 수정 안 함. |
| `.claude/agents/reviewer.md` | 치명적 vs 제안 분류. 직접 수정 안 함. |
| `.claude/agents/commit-advisor.md` | 한글 Conventional Commit + DOC 영향 평가. 실제 commit 안 함. |
| `.claude/agents/goal-checker.md` | plan-dev Stop hook 의 agent layer (Haiku). plan Semantic goal + start_ref..HEAD diff 보고 JSON `{pass, missing}` 응답. enforce-plan-dev-goal.sh 가 `claude -p` 로 호출. |
| `.claude/workflows/*.mjs` | dynamic **Workflow** 툴용 reference 스크립트 (plan-review-panel / slice-pipeline / codebase-audit). plan-dev 의 A(Plan/Review judge·적대 panel) / B(opt-in workflow 실행모드) / C(대규모 audit) 통합 템플릿. `Workflow({scriptPath})` 또는 inline `script:` paste. `export const meta` + top-level await/return → 런타임이 async fn wrap (raw `node --check` 불가, `tests/workflow_integration_lint.sh` 가 export-strip+wrap 후 syntax 검증). cmux surface 아님 — `/workflows` 트리 표현, cmux 시각화와 상호배타. |
| `.claude/skills/fork/SKILL.md` | 자식 컨텍스트로 작업 위임, 요약만 반환. |
| `.claude/skills/tmux-orchestrate/SKILL.md` | 부모-자식 Claude tmux pane 협업 패턴 가이드. |
| `.claude/hooks/*.sh` | 런타임 강제. stderr 메시지에 우회 방법 항상 명시. |
| `.claude/hooks/limit-child-panes.sh` | 자식 tmux pane + cmux child **합산** 상한 강제 (`CLAUDE_MAX_CHILD_PANES`, 디폴트 **99** = 사실상 무제한). tmux 가용 시 `tmux-pane-mgr` 세션 pane 수, cmux 가용(ping 성공) 시 state file 라인 수 (폴백: `cbp-` workspace 수) 합산. 에러 메시지에 `tmux pane: X, cmux child: Y, total: Z` 표시. |
| `.claude/hooks/enforce-cmux-context.sh` | cmux 안(`CMUX_WORKSPACE_ID` set)에서 부모가 tmux 계열 명령 시도 시 advisory warning (exit 0). `CMUX_CONTEXT_HOOK_STRICT=1` 시만 차단(exit 2). `SKIP_CMUX_CONTEXT_HOOK=1` / `DISABLE_CMUX_CONTEXT_HOOK=1` 우회. |
| `.claude/hooks/statusline-tokens.sh` | (opt-in 대안) statusLine 으로 토큰 사용량 상시 표시. 기본은 `token-stats.sh` 의 inline 메시지. |
| `.claude/settings.json` | permissions(allow/deny) + hooks. 광역 `Bash(tmux*)` 금지 — 좁힌 패턴만. |
| `scripts/merge-settings.sh` | `install.sh` 가 호출하는 settings.json 병합 헬퍼 (`<cur.json> <new.json>` → stdout). allow/deny union, `hooks.<event>` 는 matcher order-preserving unique + command 키(`hooks/<name>.(sh\|js)` 또는 full cmd) dedup — **cur 내부 + cur-vs-new 모두** dedup → install 재실행해도 hook 누적·복제 없음(idempotent). 과거 inline jq 의 matcher 미-unique 로 SessionStart 1024× 더블링 버그를 추출+수정. `tests/unit/merge-settings.test.sh` 회귀 가드. |
| `scripts/tmux-pane.sh` | tmux wrapper — launch/send/capture/wait-idle/kill/list/status. 외부 `tmux-cli` 와 명령 표면 정렬. |
| `scripts/cmux-pane.sh` | cmux wrapper — launch/send/capture/wait-idle/kill/list/cleanup/status/**notify/set-status**. `CMUX_BIN` env 로 mock 가능. `CBP_LIST_LINES` / `CLAUDE_FAKE_SELF_CMUX_WS` 로 테스트 mock 지원. **state file 헬퍼 (sanitize + mkdir-mutex + ts, pid 기반 stale reap)**. **`_do_launch_grid` 의 count-read→cmux생성→state기록 을 단일 mkdir-mutex critical section 으로 묶어 병렬 dispatch race-safe** (launch 직렬화, warmup/rename 은 lock 밖 → 자식 작업 병렬성 보존. 우회 토글 `CBP_DISABLE_LAUNCH_LOCK=1` 은 테스트 red baseline 전용). send/capture/wait-idle 이 `surface:N` ref 를 `--surface` flag 로, `workspace:N` 을 `--workspace` 로 자동 dispatch. do_list: state file 우선 (lazy reconcile, mock 환경 자동 감지), 폴백 cbp- workspace. do_cleanup: state file surface 일괄 close-surface + state 제거 후 cbp- workspace cleanup 도 실행 (호환). |
| `scripts/detect-pane-env.sh` | 터미널 멀티플렉서 환경 감지. stdout: `tmux` \| `cmux` \| `default`. sourcing guard 포함. |
| `scripts/cmux-title-chpwd.sh` | zsh `chpwd` hook — cd 마다 (1) cmux tab/surface title 을 `basename $PWD` 로 rename (`rename-tab --surface`), (2) **single-surface workspace** 면 추가로 왼쪽 사이드바 **workspace** 이름도 `workspace-action --action rename --title` 로 갱신. cmux 환경(`CMUX_SURFACE_ID` set) 시만, 비-cmux no-op. multi-surface workspace(dispatch grid 등)는 `list-pane-surfaces` count≠1 → workspace rename skip (자식 cd clobber 방지, tab 만 갱신). cmux 호출 실패/판정 실패 시 conservative skip — cd 흐름 안 깨짐. `~/.zshrc` 에서 source. install.sh user scope 가 `~/.zshrc` 에 idempotent source block 추가 (marker `# >>> cmux-title-chpwd >>>`). `CMUX_BIN` env 로 mock. |
| `scripts/dispatch-slice-pane.sh` | implementor 슬라이스를 worktree + tmux/cmux pane 으로 spawn. 멀티-driver: `--mode=tmux\|cmux\|pane\|auto\|subagent`. `plan-dev --mode=pane` 진입점. `--model=<alias>` 로 자식 model 선택 (디폴트 sonnet). `--type=<feat|fix|refactor|test|docs|chore>` 로 브랜치 prefix 결정. `build_child_cmd` 순수 함수로 분리되어 단위 테스트 가능. `DISPATCH_DRY_RUN=1` 로 launch 없이 분기 검증. 시작 시 기존 자식 pane 자동 정리 (`DISPATCH_SKIP_CLEANUP=1` 우회). |
| `scripts/plan-dev-session.sh` | plan-dev 세션 marker 관리 (start/query/clear). start 시 start_ref, base_branch, work_branch, start_ts, start_pid, auto_branch 기록. detached HEAD 차단. 기존 살아있는 세션 재진입 안전 처리. |
| `scripts/plan-dev-progress.sh` | plan-dev 진행률 cmux push 헬퍼 (start/tick/show). `PLAN_DEV_SESSION_BIN` / `CMUX_PANE_BIN` env 로 mock 가능. `PROGRESS_DRY_RUN=1` 로 notify/set-status dry-run. cmux 환경 외에서는 tick stdout 만 출력. |
| `scripts/finish-plan-dev.sh` | develop/main 분기 push 자동화 + marker clear. `origin/develop` 있으면 feature branch push, 없으면 main 직접 push. branch 이름 충돌 시 suffix -2~-5 자동 부여. **push 성공 직후 cmux 자식 surface 자동 cleanup** (`do_cmux_cleanup` — CMUX_WORKSPACE_ID set 시만). `SKIP_PLAN_DEV_FINISH` / `DISABLE_PLAN_DEV_FINISH` / `SKIP_PLAN_DEV_CMUX_CLEANUP` / `DISABLE_PLAN_DEV_CMUX_CLEANUP` 우회 지원. |
| `.claude/hooks/track-cmux-edit-burst.sh` | PreToolUse Write\|Edit. cmux env Edit/Write 누적 N회 advisory (디폴트 임계치 **50**). 디폴트 **advisory only** — settings.json 의 inline `CMUX_EDIT_BURST_STRICT=1` 제거됨. `CMUX_EDIT_BURST_STRICT=1` env 명시 시만 차단(exit 2, 회귀 가드). count file 은 cmux workspace 별 독립 — 다른 workspace 끼리 누적 공유 안 됨. mtime idle 기반 자동 리셋. dispatch-slice-pane.sh launch 시 명시 리셋. **자식 worktree 감지 (git-dir != git-common-dir) 시 자동 skip** — dispatch 자식 환경 false-positive 회피. |
| `.claude/hooks/enforce-plan-dev-goal.sh` | Stop hook. plan-dev-session marker 활성 + plan 파일 Goal Statement 의 `<!-- machine-checks -->` bash block 매 turn 종료 시 실행 = **bash layer**. 전부 PASS 후 `claude -p` headless 로 `goal-checker` agent 호출 = **agent layer** (semantic 판단). 두 layer PASS → exit 0 / 하나라도 fail → exit 2 + stderr reason → 모델 자동 다음 turn. native /goal 의 self-built 대체. **Active dispatch worktree (`.worktrees/<slug>`) 진행 중 자동 skip** — 자식 wait 단계 false-positive 회피. agent layer 우회: `SKIP_GOAL_AGENT` / `DISABLE_GOAL_AGENT`. **Semantic goal 추출은 템플릿의 인라인 `**Semantic goal**: <텍스트>` 형식을 캡처 (awk `next` 없이 매치 줄 포함 + prefix strip); 추출 빈값이면 agent layer 자동 skip (빈 goal false-negative 무한 block 방지).** |
| `.claude/hooks/cmux-dispatch-hint.sh` | SessionStart. cmux env(`CMUX_WORKSPACE_ID` set) 시 **dispatch-first advisory** 를 stdout(additionalContext)으로 inject — "cmux 환경에선 plan-dev Slice 가 dispatch(cmux) 기본, direct-edit 는 justification 동반 opt-in 예외". 비-cmux 환경은 무출력(exit 0). 하드 차단 아님(advisory nudge). cmux 환경 dispatch-기본 정책의 런타임 reminder. |
| `.claude/hooks/enforce-plan-mode.sh` | PreToolUse Write\|Edit. **/plan-dev plan mode 진입 강제** — plan-dev-session marker 활성 + plan mode 미진입 상태에서 Write/Edit 시도 시 exit 2 차단. 판정: **marker 의 `start_ts` 이후 작성된 plan 파일(`~/.claude/plans/*.md`)이 존재하면 allow** (plan mode 진입 = plan 파일 작성). `permission_mode==plan`(plan mode 중) / `==bypassPermissions`(dispatch 자식·명시 우회) → allow. 자식 worktree(git-dir≠git-common-dir) → skip. **마커 없음(비-plan-dev 세션) → no-op**. start_ts 파싱 불가 → conservative allow. ⚠️ marker **파일 mtime** 이 아니라 **start_ts JSON** 사용 — `plan-dev-progress.sh` 가 marker 를 재기록해 mtime 을 bump 하므로(mtime 기준이면 progress 후 false-positive). override: `PLAN_MODE_SESSION_FILE` / `PLAN_MODE_PLANS_DIR`. 우회: `SKIP_PLAN_MODE_ENFORCE` / `DISABLE_PLAN_MODE_ENFORCE_HOOK`. 한계: plan reject 후에도 plan 파일 존재 시 통과 — 목적은 "plan mode 아예 미진입" catch. (구 flag 방식은 plan 파일 write 가 PreToolUse Write 를 안 타 flag 미기록 → 승인 후 전부 차단하는 false-positive 였음, start_ts 신호로 교체 수정.) |

## 추가 / 수정 체크리스트

새 command/agent/skill 추가 시:
- [ ] frontmatter `name` 값이 파일명과 일치하는가?
- [ ] description 한 줄로 호출 시점이 명확한가?
- [ ] 다른 agent/command 와 책임이 겹치지 않는가?
- [ ] 관련 하네스(hook) 가 필요한가? 있다면 같이 추가.
- [ ] README.md 의 "구성" / "사용" 섹션 업데이트.

새 hook 추가 시:
- [ ] **install.sh 의 hooks list (line 40~ array) 에 새 hook 파일명 추가** — 글로벌 `~/.claude/hooks/` propagate 보장. 누락 시 다른 프로젝트에서 hook 부재 → 동일 워크플로 깨짐.
- [ ] stderr 메시지에 **우회 방법** 명시 (`SKIP_*`, `DISABLE_*_HOOK` 등).
- [ ] 차단(exit 2) vs 경고(exit 0) 결정 기준 명확.
- [ ] settings.json 의 `hooks` 섹션에 등록.
- [ ] `chmod +x` 적용.
- [ ] README.md "하네스 가드" 섹션 업데이트.
- [ ] CLAUDE.md "환경변수" 표 갱신.

새 permission 추가 시:
- [ ] allow 인가 deny 인가 명확.
- [ ] glob 패턴이 너무 좁거나 넓지 않은가.
- [ ] README.md "Permissions" 섹션 업데이트.

## 안티패턴

- ❌ 콘텐츠만 추가 / 하네스 없음 (모델이 빼먹으면 무력)
- ❌ 하네스만 추가 / 콘텐츠 가이드 없음 (사용자가 차단 이유 모름)
- ❌ hook 에서 stderr 메시지에 우회 방법 안 적기
- ❌ 일률 차단으로 SKIP 환경변수가 기본값처럼 되는 설계
- ❌ plan 파일 200줄 초과 (슬라이스 더 쪼개라)
- ❌ Horizontal phase slicing
- ❌ README/CLAUDE.md 동기화 없이 동작 변경
- ❌ 광역 `Bash(tmux*)` 허용 — 좁힌 패턴 (`tmux new-window*`, `tmux send-keys*`, `tmux capture-pane*`, `tmux display-message*`, `tmux list-panes*`, `tmux kill-pane*`) 만. `kill-server` 는 deny.
- ❌ tmux pane 모드에서 자식 결과(`✅` / `❌`) 회수 전 머지 시도
- ❌ `slice/<kebab>` branch 명 — 반드시 `<type>/<slug>` 사용 (`feat/...`, `fix/...`, etc.)
- ❌ `git merge --no-ff slice/...` — rebase fast-forward + `git branch -D` + `git worktree remove`
- ❌ Phase 5 (Branch & Push) 를 `SKIP_PLAN_DEV_FINISH=1` 로 기본값처럼 우회 — 예외적 사용만
- ❌ `PROGRESS_DRY_RUN=1` 을 환경변수로 항상 켜두기 — 진행률이 push 되지 않아 cmux 좌측에 표시가 멈춤. 테스트 시 일회성으로만.
- ❌ `dispatch-slice-pane.sh` 의 spec 본문을 `wrapper send` 로 inline 전송 — cmux send 에서 timeout 위험. 항상 spec-file 경로만 전달 + 자식에게 Read 지시.
- ❌ Slice File Map 없이 슬라이스 분해 — rebase fast-forward 시 같은 파일 영역 충돌로 부모 수동 복구 비용 발생.
- ❌ Dead code 판정 시 사용처 grep + 테스트 prop 직접 주입 확인 누락 — 부모가 prop 으로 set 하는 분기를 "도달 불가" 로 오판해 삭제하면 기존 테스트가 회귀로 catch.
- ❌ 검증용 단순 curl / sleep 단독 호출 — Bash 자동 background 진입으로 동기 결과 못 받음. `timeout 5 curl ...` 또는 cmux browser eval 사용.
- ❌ cmux 환경인데 반사적으로 direct-edit — **cmux 환경 기본은 dispatch(cmux)**. cmux 에서 direct-edit 는 Mode 컬럼 1줄 justification 동반 opt-in 예외(정책/문서 편집·trivial 수정·사용자 명시 등). 비-cmux 환경은 그 반대(direct-edit 기본). `cmux-dispatch-hint` SessionStart advisory 가 cmux 세션마다 상기. `track-cmux-edit-burst` 는 advisory only(50, 차단 없음). 하드 차단은 없음.
- ❌ enforce-plan-dev-goal hook 의 active dispatch worktree skip 룰을 잊고 자식 wait 단계에서 SKIP env 우회 시도 — `git worktree list --porcelain` 결과 안 `.worktrees/<slug>` 존재 시 hook 가 이미 자동 skip. SKIP env 불필요.
- ❌ dispatch spec-file 을 `/tmp/<slug>-spec.md` 등 repo 밖에 두기 — classifier transcript-blind 시 dispatch 거부 위험. `.claude/specs/<slug>.spec.md` 컨벤션 사용.
- ❌ Goal Statement 에 `<!-- machine-checks -->` bash block 누락 — Stop hook 가 평가할 입력 없음 → exit 0 으로 통과해 loop 의미 상실. 형식 박스 그대로 따를 것.
- ❌ Goal Statement 에 측정 불가 추상 표현 ("품질 향상", "안정성 강화") 만 박기 — Stop hook 가 평가 못 함 / false-positive. `grep` / `test` / `jq` / shell command 결과 기반 bash one-liner 만.
- ❌ 옵션 list (A/B/C) 를 plain text 로 응답 끝에 dump 하고 turn 종료 — selection chip UI 가 안 떠 사용자 입력 비용 증가, plan-dev 흐름 끊김. AskUserQuestion 의무 (Phase 1-1 `정반대 가능` trigger 매치 시).
- ❌ opt-in 없이 `Workflow` 툴 호출 — 수십 agent 비용. 사용자가 "workflow"/"multi-agent" 명시 또는 명시 지시(예: "모든 수로 검증")/ultracode on 일 때만. 그 외엔 단일 `Agent`.
- ❌ cmux 시각화 의도 슬라이스를 `Workflow` 로 돌려 사이드바에서 안 보이게 — Workflow agent 는 cmux surface 아님(상호배타 런타임). 시각 실행은 `--mode=cmux`, 비시각·대규모만 workflow.
- ❌ B(workflow 실행모드)를 비-cmux **기본값**으로 격상 — opt-in 유지. 환경별 기본(cmux=dispatch, 비-cmux=direct-edit)은 안 뒤집음.
- ❌ `.claude/workflows/*.mjs` 를 `node --check` 로 직접 검증 — top-level return/await 로 SyntaxError. export-strip + async fn wrap 후 검사 (`tests/workflow_integration_lint.sh` 참조).

## 환경변수 (tmux / cmux 통합)

| 변수 | 기본 | 효과 |
|---|---|---|
| `CLAUDE_MAX_CHILD_PANES` | 99 | 자식 tmux+cmux pane 합산 상한 — `limit-child-panes` hook 이 강제. 사실상 무제한 (병렬 dispatch 자유). 작은 값으로 제한하려면 명시적 set. |
| `DISABLE_PANE_LIMIT_HOOK` | unset | `limit-child-panes` hook 영구 비활성화 |
| `FORCE_SELF_KILL` | unset | `tmux-pane.sh kill` / `cmux-pane.sh kill` **workspace** ref 의 자기 거부 우회. surface ref 는 self-surface(`CMUX_SURFACE_ID` 일치) 만 거부, 그 외 surface 는 모두 허용 (영향 없음). |
| `TMUX_PANE_NO_LAYOUT` | unset | `tmux-pane.sh launch` 의 main-vertical layout 자동 적용 끄기 |
| `DISPATCH_CHILD_CMD` | unset | `dispatch-slice-pane.sh` 가 자식 명령으로 사용할 cmd 강제 (테스트용 substitute) |
| `DISPATCH_DEFAULT_MODEL` | sonnet | `dispatch-slice-pane.sh` 의 자식 model 디폴트 (--model arg 가 우선) |
| `DISPATCH_DEFAULT_TYPE` | feat | `dispatch-slice-pane.sh` 의 --type 미지정 시 기본 type (기본: feat) |
| `DISPATCH_DEFAULT_MODE` | auto | `dispatch-slice-pane.sh` 의 --mode 미지정 시 기본 driver (auto/tmux/cmux/pane/subagent). auto = `detect-pane-env.sh` 결과 분기. 기존 동작 복원: `pane` |
| `DISPATCH_SKIP_CLEANUP` | unset | `dispatch-slice-pane.sh` 의 시작 시 자식 pane 자동 정리 끄기 |
| `DISPATCH_DRY_RUN` | unset | `dispatch-slice-pane.sh` 가 launch 직전 driver/wrapper/worktree JSON 출력 후 exit 0 (테스트용) |
| `DISPATCH_PERMISSION_MODE` | `bypassPermissions` | `dispatch-slice-pane.sh` 가 자식 `claude` 명령에 `--permission-mode <mode>` flag 로 전달. `default` 시 flag 생략. `DISPATCH_CHILD_CMD` 가 set 되면 무시. |
| `SKIP_PLAN_DEV_FINISH` | unset | `finish-plan-dev.sh` Phase 5 1회 우회 (exit 0 + "skipped") |
| `DISABLE_PLAN_DEV_FINISH` | unset | `finish-plan-dev.sh` 영구 비활성화 (exit 0 + "disabled") |
| `FINISH_AUTO_PUSH_WITHOUT_MARKER` | unset | `finish-plan-dev.sh` 가 marker 없을 때 silent skip 대신 현재 HEAD branch 의 upstream 으로 `git push -u` 자동 시도. 부모가 후속 fix commit 후 marker 가 stale 일 때 유용. |
| `GIT_PUSH_CMD` | `git push` | `finish-plan-dev.sh` 의 push 명령 override (테스트용) |
| `PLAN_DEV_SESSION_BIN` | `scripts/plan-dev-session.sh` | `finish-plan-dev.sh` / `plan-dev-progress.sh` 가 marker 조작에 사용할 헬퍼 경로 override (테스트용) |
| `CMUX_PANE_BIN` | `scripts/cmux-pane.sh` | `plan-dev-progress.sh` 가 cmux push 에 사용할 wrapper 경로 override (테스트용) |
| `PROGRESS_DRY_RUN` | unset | `plan-dev-progress.sh` 의 notify/set-status 단계 dry-run (`cmux-pane.sh` 가 처리). unset 시 실제 push |
| `CMUX_BIN` | `cmux` | `cmux-pane.sh` / `detect-pane-env.sh` 가 사용할 cmux 바이너리 경로. 테스트 mock 에 사용. |
| `CBP_WORKSPACE_PREFIX` | `cbp-` | `cmux-pane.sh launch` 의 workspace 이름 prefix |
| `CBP_STATE_FILE` | `~/.cache/cbp/children-<ws>.json` | `cmux-pane.sh` state file 경로 override. sanitize 규칙: `${CMUX_WORKSPACE_ID//[:\/]/_}` (콜론/슬래시 → 언더스코어) |
| `CBP_LIST_LINES` | unset | `cmux-pane.sh list/cleanup/status` 의 list-workspaces 입력 mock (테스트용). set 시 실제 cmux 호출 생략. |
| `CLAUDE_FAKE_SELF_CMUX_WS` | unset | `cmux-pane.sh kill/cleanup` 의 자기 workspace ref mock (테스트용). `cmux identify` 대신 이 값 사용. |
| `CMUX_CONTEXT_HOOK_STRICT` | unset | `enforce-cmux-context.sh` strict 모드 — cmux 안 tmux 계열 명령 차단(exit 2). unset 이면 advisory only. |
| `SKIP_CMUX_CONTEXT_HOOK` | unset | `enforce-cmux-context.sh` 1회 우회 (advisory 억제, exit 0 통과) |
| `DISABLE_CMUX_CONTEXT_HOOK` | unset | `enforce-cmux-context.sh` 영구 비활성화 |
| `CBP_SPLIT_POLICY` | unset (라운드로빈) | `cmux-pane.sh` grid split 방향 고정 (`down` 또는 `right`). unset 시 라운드로빈 (count 홀수→down, 짝수→right). Slice A3 에서 확장 예정. |
| `CBP_DISABLE_WARMUP` | unset | `cmux-pane.sh launch` 의 PTY warmup (surface 생성 후 send-key Enter + sleep) 끄기. 신규 surface 가 PTY detached 상태로 첫 send 를 swallow 하는 케이스 우회용 (디폴트 on). |
| `CBP_WARMUP_SLEEP` | 0.5 | `cmux-pane.sh launch` PTY warmup 의 sleep 초. |
| `CMUX_EDIT_BURST_THRESHOLD` | 50 | `track-cmux-edit-burst` hook 의 advisory 임계치. 디폴트 50 — 부모 50 Edit 까지 silently pass, 51번째부터 stderr advisory (차단 X, strict env 미지정 시). count file 은 **cmux workspace 별 독립** (`~/.cache/cbp/edit-burst-<workspace_id>.count`) — 다른 workspace 끼리 count 공유 안 됨. |
| `CMUX_EDIT_BURST_IDLE_SEC` | 300 | `track-cmux-edit-burst` hook 의 자동 리셋 idle 초 |
| `CMUX_EDIT_BURST_STRICT` | unset | `track-cmux-edit-burst` hook strict 모드 (exit 2 차단). settings.json 의 inline 설정은 제거됨 — 디폴트 advisory only. 명시 set 시만 차단 (회귀 가드 보존). |
| `SKIP_CMUX_EDIT_BURST` | unset | `track-cmux-edit-burst` hook 1회 우회 |
| `DISABLE_CMUX_EDIT_BURST_HOOK` | unset | `track-cmux-edit-burst` hook 영구 비활성화 |
| `CBP_BURST_FILE` | unset | `track-cmux-edit-burst` hook 카운터 파일 경로 override (테스트 mock) |
| `SKIP_PLAN_DEV_GOAL` | unset | `enforce-plan-dev-goal.sh` Stop hook 1회 우회 — Goal Statement loop bypass |
| `DISABLE_PLAN_DEV_GOAL_HOOK` | unset | `enforce-plan-dev-goal.sh` Stop hook 영구 비활성화 |
| `PLAN_DEV_GOAL_PLAN_PATH` | auto | hook 가 평가할 plan 파일 경로 override (테스트 mock). 미지정 시 marker 의 plan_path 필드 또는 `~/.claude/plans/` 최신 mtime fallback |
| `PLAN_DEV_GOAL_SESSION_FILE` | `.git/plan-dev-session.json` | marker 파일 경로 override (테스트 mock) |
| `PLAN_DEV_GOAL_VERBOSE` | unset | PASS 도 stderr 에 요약 출력 |
| `SKIP_GOAL_AGENT` | unset | `enforce-plan-dev-goal.sh` agent layer 1회 우회 (bash 만 평가) |
| `DISABLE_GOAL_AGENT` | unset | `enforce-plan-dev-goal.sh` agent layer 영구 비활성 (bash 만 평가) |
| `SKIP_PLAN_DEV_CMUX_CLEANUP` | unset | `finish-plan-dev.sh` push 후 cmux 자식 surface cleanup 1회 우회 |
| `DISABLE_PLAN_DEV_CMUX_CLEANUP` | unset | `finish-plan-dev.sh` push 후 cmux cleanup 영구 비활성 |
| `SKIP_PLAN_MODE_ENFORCE` | unset | `enforce-plan-mode.sh` PreToolUse hook 1회 우회 (plan mode 미진입 차단 bypass) |
| `DISABLE_PLAN_MODE_ENFORCE_HOOK` | unset | `enforce-plan-mode.sh` 영구 비활성화 |
| `PLAN_MODE_SESSION_FILE` | auto | `enforce-plan-mode.sh` 마커 경로 override (디폴트 `$CLAUDE_PROJECT_DIR/.git/plan-dev-session.json`, 테스트 mock) |
| `PLAN_MODE_PLANS_DIR` | `$HOME/.claude/plans` | `enforce-plan-mode.sh` 가 plan 파일을 찾는 디렉토리 override (테스트 mock) |

## 향후 작업 (플러그인화)

본 repo 는 최종적으로 Claude Code 플러그인 형태로 패키징될 예정. 그 시점에:
- `install.sh` 는 플러그인 manifest 로 대체.
- `.claude/` 디렉토리 구조는 유지하되 plugin 메타데이터 추가.
- 글로벌 / 프로젝트 scope 는 플러그인 enable 방식으로.

지금은 sh 기반 설치로 충분 — 플러그인화는 안정화된 후.
