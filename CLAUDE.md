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

## 릴리즈 & 버저닝 규칙

- **버전 소스**: `.claude-plugin/plugin.json` + `.claude-plugin/marketplace.json` 두 곳 동시. `release.sh` 가 동기화.
- **semver bump 기준**: breaking(하위호환 깨짐)=major / 새 기능(feat)=minor / fix·docs·refactor·chore=patch. plan-dev Phase 4 의 commit-advisor 가 산정한 최대 type 을 참고.
- **태그 컨벤션**: `sshworld--vX.Y.Z` (double-dash prefix 유지).
- **발행 위치**: **GitHub Release native 로만**. CHANGELOG.md 파일은 두지 않는다(중복). 사용자 판단.
- **릴리즈 노트 형식**: 섹션 헤더는 **conventional 영문 라벨**(Feature/Fix/Refactor/Chore/Docs/Breaking), 항목 설명은 **한글**.
```
## v1.3.6 — <한줄 요약>

### ✨ Feature          (feat)
### 🐛 Fix              (fix)
### ♻️ Refactor / Chore (refactor·chore)
### 📝 Docs             (docs)
### ⚠️ Breaking         (있을 때만)

**업데이트**: `/plugin update sshworld`
```
  - 빈 섹션 생략. 항목은 사용자 관점 한 줄. **슬라이스 라벨(S1/S2)·머지 잡음 금지** (commit-advisor 원칙과 동일).
- **릴리즈 흐름 (매 배포마다 Claude 가 수행)**:
  1. `scripts/release.sh draft` 로 skeleton 뽑고 → Claude 가 사용자 관점으로 살 붙임 → notes 파일 저장.
  2. `RELEASE_DRY_RUN=1 scripts/release.sh publish <ver> <notes>` 로 검증.
  3. `scripts/release.sh publish <ver> <notes>` 로 실발행 (bump+commit+tag+push+gh release).
- plan-dev Phase 5(Branch & Push) 와의 관계: feature 머지와 릴리즈(버전 bump)는 별개 행위. 버전 올릴 때만 release.sh.

## 파일별 책임 분리

| 파일 | 책임 |
|---|---|
| `scripts/release.sh` | 릴리즈 자동화 — draft(type별 한글 skeleton)/publish(bump+commit+태그+push+gh release)/backfill(과거 소급 태그+release). 버전 소스 plugin.json+marketplace.json 동기화. `RELEASE_DRY_RUN`/`GH_CMD`/`GIT_PUSH_CMD` mock. 노트 body 는 Claude 가 작성해 --notes-file 로 전달. |
| `commands/plan-dev.md` | 사용자 entry point. 단계별 가이드와 안티패턴. Phase 6 = `/fork` 스킬 직접 호출(세션 클로저). |
| `commands/parallel-consult.md` | 자식 Claude pane 띄워 1회 질의응답. |
| `agents/implementor.md` | TDD Red→Green→Refactor. subagent / tmux pane 모드 양쪽 지원. |
| `agents/verifier.md` | Read-only 빌드/테스트. 코드 수정 안 함. |
| `agents/reviewer.md` | 치명적 vs 제안 분류. 직접 수정 안 함. |
| `agents/commit-advisor.md` | 한글 Conventional Commit + DOC 영향 평가 + 히스토리 위생/squash 추천. 실제 commit 안 함. |
| `.claude/workflows/*.mjs` | dynamic **Workflow** 툴용 reference 스크립트 (plan-review-panel / slice-pipeline / codebase-audit / `vuln-scan-pipeline`(defending-code-reference-harness find→grade→judge→report 정적분석 재현, 코드 실행 X)). plan-dev 의 A(Plan/Review judge·적대 panel) / B(opt-in workflow 실행모드) / C(대규모 audit) 통합 템플릿. `Workflow({scriptPath})` 또는 inline `script:` paste. `export const meta` + top-level await/return → 런타임이 async fn wrap (raw `node --check` 불가, `tests/workflow_integration_lint.sh` 가 export-strip+wrap 후 syntax 검증). cmux surface 아님 — `/workflows` 트리 표현, cmux 시각화와 상호배타. **이동 안 함 — Workflow 툴 reference 로 .claude/ 유지.** |
| `skills/fork/SKILL.md` | 자식 컨텍스트로 작업 위임, 요약만 반환. 이중 용도(격리 실행 / Phase 6 클로저). |
| `skills/tmux-orchestrate/SKILL.md` | 부모-자식 Claude tmux pane 협업 패턴 가이드. |
| `hooks/*.sh` | 런타임 강제. stderr 메시지에 우회 방법 항상 명시. |
| `hooks/hooks.json` | 플러그인 hooks 정의 파일. `${CLAUDE_PLUGIN_ROOT}` 기반 경로. permissions 는 미포함(플러그인 비지원 — README 권장 permissions 참조). |
| `hooks/limit-child-panes.sh` | 자식 tmux pane + cmux child **합산** 상한 강제 (`CLAUDE_MAX_CHILD_PANES`, 디폴트 **99** = 사실상 무제한). tmux 가용 시 `tmux-pane-mgr` 세션 pane 수, cmux 가용(ping 성공) 시 state file 라인 수 (폴백: `cbp-` workspace 수) 합산. 에러 메시지에 `tmux pane: X, cmux child: Y, total: Z` 표시. |
| `hooks/enforce-cmux-context.sh` | cmux 안(`CMUX_WORKSPACE_ID` set)에서 부모가 tmux 계열 명령 시도 시 advisory warning (exit 0). 디폴트 advisory — `hooks.json`/`settings.json` 모두 strict inline 강제 없음. `CMUX_CONTEXT_HOOK_STRICT=1` 사용자 opt-in 시만 차단(exit 2). `SKIP_CMUX_CONTEXT_HOOK=1` / `DISABLE_CMUX_CONTEXT_HOOK=1` 우회. |
| `hooks/enforce-test-first.sh` | PreToolUse Write\|Edit. production 파일(`src/main/`,`lib/`,`app/`,`internal/`,`pkg/`) Write/Edit 전 대응 테스트 파일 존재 검사. 디폴트 경고만, `CLAUDE_TDD_STRICT=1` 시 차단(exit 2). |
| `hooks/statusline-tokens.sh` | (opt-in 대안) statusLine 으로 토큰 사용량 상시 표시. 기본은 `token-stats.sh` 의 inline 메시지. |
| `.claude/settings.json` | permissions(allow/deny) + hooks. 광역 `Bash(tmux*)` 금지 — 좁힌 패턴만. project-scope dogfooding 보존. |
| `install.sh` | **deprecated** — `/plugin install sshworld` 로 교체. 실행 시 안내 출력 후 exit 0. |
| `scripts/merge-settings.sh` | settings.json 병합 헬퍼 (`<cur.json> <new.json>` → stdout). allow/deny union, `hooks.<event>` 는 matcher order-preserving unique + command 키(`hooks/<name>.(sh\|js)` 또는 full cmd) dedup — **cur 내부 + cur-vs-new 모두** dedup → install 재실행해도 hook 누적·복제 없음(idempotent). 과거 inline jq 의 matcher 미-unique 로 SessionStart 1024× 더블링 버그를 추출+수정. `tests/unit/merge-settings.test.sh` 회귀 가드. |
| `scripts/trust-dir.sh` | 자식 worktree 경로를 `~/.claude.json` (`hasTrustDialogAccepted`) 에 자동 시딩. cross-machine bypass 자동화 — fresh 머신 trust 다이얼로그 회피. `dispatch-slice-pane.sh` 가 worktree launch 직전 호출. `CBP_CLAUDE_CONFIG` mock, `_TRUST_DIR_NO_JQ=1` jq 부재 흉내. 우회: `SKIP_DISPATCH_TRUST=1` (dispatch 쪽). jq 부재 시 conservative exit 0. |
| `scripts/tmux-pane.sh` | tmux wrapper — launch/send/capture/wait-idle/kill/list/status. 외부 `tmux-cli` 와 명령 표면 정렬. launch 시 pane 에 `@cbp_child=1` 태깅 — cleanup 이 이 태그 붙은 pane 만(현재 window 스코프) 정리, self pane 은 `$TMUX_PANE` 으로 보호. |
| `scripts/cmux-pane.sh` | cmux wrapper — launch/send/capture/wait-idle/kill/**reap**/**reap-orphans**/list/cleanup/status/**notify/set-status**. `CMUX_BIN` env 로 mock 가능. `CBP_LIST_LINES` / `CLAUDE_FAKE_SELF_CMUX_WS` 로 테스트 mock 지원. **state file 헬퍼 (sanitize + mkdir-mutex + ts, pid 기반 stale reap)**. **`_do_launch_grid` 의 count-read→cmux생성→state기록 을 단일 mkdir-mutex critical section 으로 묶어 병렬 dispatch race-safe** (launch 직렬화, warmup/rename 은 lock 밖 → 자식 작업 병렬성 보존. 우회 토글 `CBP_DISABLE_LAUNCH_LOCK=1` 은 테스트 red baseline 전용). **launch 후 `_cbp_surface_is_terminal` 로 PTY 검증 재시도(`CBP_LAUNCH_VERIFY_TRIES`, 기본 5), 끝내 미기동 시 die(exit 3)**. `CBP_DISABLE_WARMUP=1` 시 검증 루프 스킵(기존 동작). **좀비 surface 방지: `_do_launch_grid` 가 surface 생성 성공 직후부터 launch 정상 완료까지 `trap ... EXIT` 로 best-effort close-surface + state 제거를 걸어둠 — verify-fail die(exit 3) 및 이후 send die 로 인한 실패 종료 시에도 발동, 정상 완료 시 `trap - EXIT` 로 해제 (exit code 는 trap 안에서 즉시 캡처 후 재-exit 로 보존).** **`CBP_LAUNCH_DEBUG=1`: verify 각 시도의 read-screen 출력 + 생성 경로(new-pane/new-split raw_out) + prev_surface 를 stderr 로 dump (off 시 동작·출력 완전 불변, 추가 read-screen 호출 없음).** send/capture/wait-idle/kill 의 surface 판정은 `_cbp_pane_flag` 헬퍼로 중앙화 — `surface:N` 뿐 아니라 cmux 실측 UUID ref(`$CMUX_SURFACE_ID` 값, dispatch `CBP_SELF_PANE` 미주입 시 belt) 도 `--surface` 로, 그 외(`workspace:N` 포함)는 `--workspace` 로 자동 dispatch. **do_reap(`--pane=<ref>`): wait-idle → capture → ✅/❌ 감지 (⏺ prefix/들여쓰기 허용) → 완료 자식 자동 close-surface (do_kill 재사용, self-surface 거부 상속).** **완료 마커가 떴어도 자식 input box 에 미제출 사용자 텍스트(`❯ text`)가 남아있으면 `input-pending — kept` 로 회수 보류** (`_send_is_submitted` 판정 재사용 — send-confirm 과 공유). 강제 회수: `CBP_REAP_IGNORE_PENDING=1`. `CBP_REAP_DRY_RUN=1` dry-run(pending 시 "would keep (input-pending)"). **done-marker 가 own-workspace 로 확인되면(`CBP_REAP_MARKER_TRUMPS_PENDING`, 디폴트 1) input-pending 가드보다 marker 를 우선시켜 pending 이어도 회수 진행** — cmux workspace 잔존 composer draft/오버레이가 모든 자식 화면에 찍혀 pending 을 상시 오탐하던 문제 대응, 출력에 `reaped ... (pending-input 무시: <텍스트>)` 부기. `0` 이면 구 동작(marker 있어도 pending 이면 kept) 복원. **`reap` `--pane` 생략(argless) 또는 `--all`: `_do_reap_one` 을 state 의 모든 자식에 subshell 로 반복 실행(개별 실패가 루프를 안 죽임) — fast-probe 기본 `--idle=2 --timeout=10`(옵션 명시 시 override), ts 기준 age < `CBP_REAP_ORPHANS_GRACE_SEC`(기본 30) 인 신생 자식은 probe 없이 "grace — kept", 마지막 줄 `reaped N / kept M / pending P` 요약(pending 은 kept 로 흡수되지 않음). 부모 감시 루프의 `--pane` 없는 반복 호출이 더 이상 exit 2 로 헛돌지 않음.** send confirm rc2 분기: PTY detached 의심 시 Enter 재전송으로 attach 강제 (bounded: `CBP_SEND_CONFIRM_DETACHED_TRIES` 회). 완료 detection 은 `reap` 단일 경로 — hand-rolled `grep -E '^(✅|❌)'`(strict column-0) 금지, `⏺`/들여쓰기 prefix 못 잡음. dead surface(read-screen 실패=not a terminal) → `died`+exit 5 로 구분(헛대기 방지), 호출자는 subagent 폴백; **reap died 시 state 에서 제거(좀비 차단), `_do_launch_grid` 는 live prev_surface 만 기준 split(죽은 prev cascade 차단, 없으면 new-pane 폴백).** **do_reap_orphans (2-phase lock): `CBP_STATE_DIR`(디폴트 `~/.cache/cbp`) 의 `children-*.json` 전체 스캔 → self surface 제외 + alive(read-screen rc0) 보존 + 신생 surface grace(`CBP_REAP_ORPHANS_GRACE_SEC`, 디폴트 30초 — ts 가 now 기준 이 이내면 liveness 검사 자체 skip, launch 직후 race 로 오살 방지) + dead surface best-effort close-surface + state 줄 제거 + 빈 state file rm. `CBP_REAP_ORPHANS_DRY_RUN=1` dry-run. `plan-dev-session.sh start` 및 `finish-plan-dev.sh` 가 best-effort 호출 (`SKIP_CMUX_REAP=1` 우회).** do_list: state file 우선 (lazy reconcile, mock 환경 자동 감지), 폴백 cbp- workspace. do_cleanup: state file surface 일괄 close-surface + state 제거 후 cbp- workspace cleanup 도 실행 (호환). **reap fast-path**: `_cbp_find_done_marker` 가 `hooks/notify-slice-done.sh` 가 남긴 done-marker(`cbp-slice-done-*`) 를 찾아 line1(surface ref) 매치 + line2(workspace id, 있으면 자기 `$CMUX_WORKSPACE_ID` 와 다를 때 skip) 검사 통과 시 `CBP_REAP_FAST_CHECK`(디폴트 1) 하에 `do_wait_idle` 스킵하고 바로 capture 로 직행 — marker 는 reaped/died 시 rm(dry-run/kept 시 보존). `hooks/reap-on-stop.sh` 도 동일 계약으로 marker 를 직접 소비한다. |
| `scripts/detect-pane-env.sh` | 터미널 멀티플렉서 환경 감지. stdout: `tmux` \| `cmux` \| `default`. sourcing guard 포함. |
| `scripts/cmux-title-chpwd.sh` | zsh `chpwd` hook — cd 마다 (1) cmux tab/surface title 을 `basename $PWD` 로 rename (`rename-tab --surface`), (2) **single-surface workspace** 면 추가로 왼쪽 사이드바 **workspace** 이름도 `workspace-action --action rename --title` 로 갱신. cmux 환경(`CMUX_SURFACE_ID` set) 시만, 비-cmux no-op. multi-surface workspace(dispatch grid 등)는 `list-pane-surfaces` count≠1 → workspace rename skip (자식 cd clobber 방지, tab 만 갱신). cmux 호출 실패/판정 실패 시 conservative skip — cd 흐름 안 깨짐. `~/.zshrc` 에서 source (사용자가 수동 추가 — `install.sh` 는 deprecated 라 zshrc 를 건드리지 않음). `CMUX_BIN` env 로 mock. |
| `scripts/dispatch-slice-pane.sh` | implementor 슬라이스를 worktree + tmux/cmux pane 으로 spawn. 멀티-driver: `--mode=tmux\|cmux\|pane\|auto\|subagent`. `plan-dev --mode=pane` 진입점. `--model=<alias>` 로 자식 model 선택 (디폴트 sonnet). `--type=<feat|fix|refactor|test|docs|chore>` 로 브랜치 prefix 결정(`feat`→`feature/`, 나머지는 동일). `build_child_cmd` 순수 함수로 분리되어 단위 테스트 가능. `DISPATCH_DRY_RUN=1` 로 launch 없이 분기 검증. 시작 시 기존 자식 pane 자동 정리 (`DISPATCH_SKIP_CLEANUP=1` 우회) — plan-dev 세션당 1회로 원자화(stamp 파일 `<git-common-dir>/plan-dev-dispatch-cleaned` 에 marker start_ts 기록, 병렬 dispatch 가 방금 뜬 자식 재살처분 방지). **cmux 경로: 자식 claude TUI 기동 검증(`DISPATCH_VERIFY`/`DISPATCH_VERIFY_TRIES`) + 실패 시 exit 비0 + subagent 폴백 안내**. **자식 셸에 정확한 `surface:N` ref 를 `CBP_SELF_PANE` env 로 주입**(cd 이후, 자식 명령 전송 이전, best-effort) — 자식 claude(및 Stop hook) 가 상속해 `notify-slice-done.sh` done-marker line1 을 UUID 대신 `surface:N` namespace 로 기록, reap fast-path/wrapper 라우팅과 정합. |
| `scripts/plan-dev-session.sh` | plan-dev 세션 marker 관리 (start/query/clear). start 시 start_ref, base_branch, work_branch, start_ts, start_pid, auto_branch 기록. detached HEAD 차단. 기존 살아있는 세션 재진입 안전 처리. 재진입(dead pid + within_24h) 시 start_ts/start_ref 보존 — progress start 재호출 clobber 방지(enforce-plan-mode false-positive 제거). **marker 기록 직후 cmux 환경에서 `reap-orphans` best-effort 호출** (CMUX_WORKSPACE_ID set 시, `SKIP_CMUX_REAP=1` 우회). start 시 stale done-marker(`cbp-slice-done-*`) backstop rm (reap fast-path 의 rm 누락/실패 대비, best-effort). |
| `scripts/plan-dev-progress.sh` | plan-dev 진행률 cmux push 헬퍼 (start/tick/show). `PLAN_DEV_SESSION_BIN` / `CMUX_PANE_BIN` env 로 mock 가능. `PROGRESS_DRY_RUN=1` 로 notify/set-status dry-run. cmux 환경 외에서는 tick stdout 만 출력. |
| `scripts/finish-plan-dev.sh` | develop/main 분기 push 자동화 + marker clear. `origin/develop` 있으면 feature branch push, 없으면 main 직접 push. branch 이름 충돌 시 suffix -2~-5 자동 부여. **push 직전 commit-advised marker 게이트(commit-advisor 미실행 차단)** — `.git/plan-dev-commit-advised` 부재 시 exit 2. **push 성공 직후 cmux 자식 surface 자동 cleanup** (`do_cmux_cleanup` — CMUX_WORKSPACE_ID set 시만) + **reap-orphans backstop** (cleanup 후 dead surface 회수, `SKIP_CMUX_REAP=1` 우회). cleanup 직후 stale done-marker(`cbp-slice-done-*`) backstop rm (reap fast-path 의 rm 누락/실패 대비, best-effort). `SKIP_PLAN_DEV_FINISH` / `DISABLE_PLAN_DEV_FINISH` / `SKIP_COMMIT_ADVISOR_GATE` / `DISABLE_COMMIT_ADVISOR_GATE` / `SKIP_PLAN_DEV_CMUX_CLEANUP` / `DISABLE_PLAN_DEV_CMUX_CLEANUP` / `SKIP_CMUX_REAP` 우회 지원. |
| `hooks/track-cmux-edit-burst.sh` | PreToolUse Write\|Edit. cmux env Edit/Write 누적 N회 advisory (디폴트 임계치 **50**). 디폴트 **advisory only** — settings.json 의 inline `CMUX_EDIT_BURST_STRICT=1` 제거됨. `CMUX_EDIT_BURST_STRICT=1` env 명시 시만 차단(exit 2, 회귀 가드). count file 은 cmux workspace 별 독립 — 다른 workspace 끼리 누적 공유 안 됨. mtime idle 기반 자동 리셋. dispatch-slice-pane.sh launch 시 명시 리셋. **자식 worktree 감지 (git-dir != git-common-dir) 시 자동 skip** — dispatch 자식 환경 false-positive 회피. |
| `hooks/enforce-cmux-dispatch.sh` | PreToolUse ExitPlanMode. cmux env(`CMUX_WORKSPACE_ID` set)에서 plan Slice File Map 의 `direct-edit` 표셀 탐지 시 **exit 2 차단**. `CMUX_DIRECT_EDIT_OK=1` 의식적 escape (1회 통과). `SKIP_CMUX_DISPATCH_GATE=1` / `DISABLE_CMUX_DISPATCH_GATE_HOOK=1` 우회. 비-cmux 환경 no-op. |
| `hooks/cmux-dispatch-hint.sh` | SessionStart. cmux env(`CMUX_WORKSPACE_ID` set) 시 **dispatch-first advisory** 를 stdout(additionalContext)으로 inject — "cmux 환경에선 plan-dev Slice 가 dispatch(cmux) 기본, direct-edit 는 `CMUX_DIRECT_EDIT_OK=1` escape". 비-cmux 환경은 무출력(exit 0). advisory nudge + ExitPlanMode 게이트 reminder. |
| `hooks/enforce-plan-mode.sh` | PreToolUse Write\|Edit. **/plan-dev plan mode 진입 강제** — plan-dev-session marker 활성 + plan mode 미진입 상태에서 Write/Edit 시도 시 exit 2 차단. 판정: **marker 의 `start_ts` 이후 작성된 plan 파일(`~/.claude/plans/*.md`)이 존재하면 allow** (plan mode 진입 = plan 파일 작성). `permission_mode==plan`(plan mode 중) / `==bypassPermissions`(dispatch 자식·명시 우회) → allow. 자식 worktree(git-dir≠git-common-dir) → skip. **마커 없음(비-plan-dev 세션) → no-op**. start_ts 파싱 불가 → conservative allow. marker 가 **24시간 넘게 stale**(dead pid 등) 이면 이전 세션 잔재로 판단해 allow. skip-once marker 파일 `<git-common-dir>/cbp-skip-once-plan-mode` 존재 시 rm 하며 1회 통과. ⚠️ marker **파일 mtime** 이 아니라 **start_ts JSON** 사용 — `plan-dev-progress.sh` 가 marker 를 재기록해 mtime 을 bump 하므로(mtime 기준이면 progress 후 false-positive). override: `PLAN_MODE_SESSION_FILE` / `PLAN_MODE_PLANS_DIR`. 우회: `SKIP_PLAN_MODE_ENFORCE` / `DISABLE_PLAN_MODE_ENFORCE_HOOK`. 한계: plan reject 후에도 plan 파일 존재 시 통과 — 목적은 "plan mode 아예 미진입" catch. (구 flag 방식은 plan 파일 write 가 PreToolUse Write 를 안 타 flag 미기록 → 승인 후 전부 차단하는 false-positive 였음, start_ts 신호로 교체 수정.) |
| `hooks/enforce-dispatch-gate.sh` | PreToolUse Bash. `dispatch-slice-pane.sh --slice` 명령(둘 다 포함 시만) 감지 → plan-dev 세션 활성 + plan mode 거침(marker `start_ts` 이후 plan 파일 존재) 확인 — 미진입이면 exit 2 차단. 자식 worktree / bypassPermissions / plan mode 중 → skip. marker 가 **24시간 넘게 stale** 이면 이전 세션 잔재로 판단해 allow. skip-once marker 파일 `<git-common-dir>/cbp-skip-once-dispatch-gate` 존재 시 rm 하며 1회 통과. 파싱 실패 → conservative exit 0. `SKIP_DISPATCH_GATE=1` (1회) / `DISABLE_DISPATCH_GATE_HOOK=1` (영구) 우회. `DISPATCH_GATE_SESSION_FILE` / `PLAN_MODE_PLANS_DIR` env 로 mock. |
| `hooks/record-commit-advised.sh` | PostToolUse Task\|Agent. `tool_input.subagent_type` 에 `commit-advisor` substring(플러그인 네임스페이스 `sshworld:commit-advisor` 포함) 감지 시 `plan-dev-commit-advised` marker 자동 touch — `finish-plan-dev.sh` push 게이트가 advisor agent 본인의 touch 이행(LLM 준수)에 의존하던 구조적 취약점 보강. jq/python3 없이 grep/sed 파싱. 비-git cwd / 빈·깨진 stdin 전부 조용히 exit 0 (세션 절대 안 막음). |
| `hooks/notify-slice-done.sh` | Stop hook (cmux 자식 worktree 전용). 자식 turn 종료 시 마지막 assistant 텍스트에서 ✅/❌ 판정 → (a) `cmux notify` 로 부모 사이드바 알림 push, (b) `<git-common-dir>/cbp-slice-done-<branch sanitized: / → _>` done-marker 파일에 **2줄** 기록 — line1 surface ref(dispatch 가 주입한 `$CBP_SELF_PANE` 우선, 없으면 `$CMUX_SURFACE_ID` 폴백), line2 `$CMUX_WORKSPACE_ID`(타 workspace 오사용 차단, 소비측 `_cbp_find_done_marker`/`reap-on-stop.sh` 가 검사) — `cmux-pane.sh reap` fast-path(`CBP_REAP_FAST_CHECK`) 및 `hooks/reap-on-stop.sh` 의 공유 소비 계약. 가드: `CMUX_WORKSPACE_ID` unset / 비-자식-worktree(git-dir==git-common-dir) / 비-`.worktrees/*` 인 경우 `CBP_NOTIFY_ANY_WORKTREE=1` 없으면 skip. jq 부재 시 판정 불가 `🔔 turn 종료` 로 강등. 모든 경로 exit 0(세션 안 막음). 우회: `SKIP_SLICE_DONE_NOTIFY=1`(1회) / `DISABLE_SLICE_DONE_NOTIFY=1`(영구). |
| `hooks/reap-on-stop.sh` | Stop hook (부모 세션 전용, 자식 worktree skip). turn 경계마다 `<git-common-dir>/cbp-slice-done-*` marker 를 glob 으로 소비 — 상한 5개까지 `CBP_REAP_FAST_CHECK=1` 강제한 `cmux-pane.sh reap --pane=<ref>` 로 targeted reap. line2 workspace 불일치·자기 surface(`$CMUX_SURFACE_ID`)는 skip. **분류는 `^reaped ` 매치를 최우선(reaped-first)** — marker 가 pending 을 trump 해 회수된 경우("reaped ... (pending-input 무시: ...)") 가 아래 `input-pending` 문자열 검사에 보류로 오분류되는 것을 방지, annotation(무시된 입력 텍스트) 은 추출해 그대로 병기. 결과(reaped(+annotation)/⏸ input-pending kept)를 systemMessage 1줄로 통지(jq 필요, 부재 시 무출력). 감시 루프 없이도 자식 완료 → 다음 부모 turn 경계에 자동 회수되는 belt. 우회: `SKIP_REAP_ON_STOP=1`(1회) / `DISABLE_REAP_ON_STOP=1`(영구). wrapper 경로 override: `CBP_PANE_BIN`. 모든 경로 exit 0(세션 안 막음). |

## 추가 / 수정 체크리스트

새 command/agent/skill 추가 시:
- [ ] frontmatter `name` 값이 파일명과 일치하는가?
- [ ] description 한 줄로 호출 시점이 명확한가?
- [ ] 다른 agent/command 와 책임이 겹치지 않는가?
- [ ] 관련 하네스(hook) 가 필요한가? 있다면 같이 추가.
- [ ] README.md 의 "구성" / "사용" 섹션 업데이트.

새 hook 추가 시:
- [ ] **`hooks/hooks.json` 에 새 hook 명시** — 플러그인 설치 시 훅이 등록되도록. (`install.sh` 는 deprecated.)
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

버전 bump / 배포 시:
- [ ] `release.sh` 로 발행 (직접 tag/gh 명령 금지 — drift 원인).
- [ ] 릴리즈 노트 한글 형식 준수 ("## 릴리즈 & 버저닝 규칙" 참조).

## 안티패턴

- ✅ 예외: **스킬 호출(예: Phase 6 의 `/fork`)은 hook 으로 강제 불가** — Stop hook 은 turn 재개만 가능하고 특정 액션 지정을 못 한다. 이 경우 "콘텐츠만/하네스 없음" 이 안티패턴이 아니라 **정당한 콘텐츠-전용**이다(구조적 한계). 순진한 하네스 누락과 구분할 것.
- ❌→ℹ️ 플러그인 버전 bump(예 1.3.4→1.3.5)+reload 후에도 **실행 중이던 세션**은 stale `CLAUDE_PLUGIN_ROOT`(옛 versioned 경로 GC됨) → `Hook script appears to be missing` 노이즈. 코드 결함 아님 — `/clear` 로 세션 재시작해야 새 plugin root 반영.
- ❌ 콘텐츠만 추가 / 하네스 없음 (모델이 빼먹으면 무력)
- ❌ 하네스만 추가 / 콘텐츠 가이드 없음 (사용자가 차단 이유 모름)
- ❌ hook 에서 stderr 메시지에 우회 방법 안 적기
- ❌ 일률 차단으로 SKIP 환경변수가 기본값처럼 되는 설계
- ❌ plan 파일 200줄 초과 (슬라이스 더 쪼개라)
- ❌ Horizontal phase slicing
- ❌ README/CLAUDE.md 동기화 없이 동작 변경
- ❌ 광역 `Bash(tmux*)` 허용 — 좁힌 패턴 (`tmux new-window*`, `tmux send-keys*`, `tmux capture-pane*`, `tmux display-message*`, `tmux list-panes*`, `tmux kill-pane*`) 만. `kill-server` 는 deny.
- ❌ tmux pane 모드에서 자식 결과(`✅` / `❌`) 회수 전 머지 시도
- ❌ `slice/<kebab>` branch 명 — 반드시 `<type>/<slug>` 사용 (`feature/...`(type=feat 는 브랜치 prefix 가 `feature/` 로 매핑됨), `fix/...`, etc.)
- ❌ `git merge --no-ff slice/...` — rebase fast-forward + `git branch -D` + `git worktree remove`
- ❌ Phase 5 (Branch & Push) 를 `SKIP_PLAN_DEV_FINISH=1` 로 기본값처럼 우회 — 예외적 사용만
- ❌ `PROGRESS_DRY_RUN=1` 을 환경변수로 항상 켜두기 — 진행률이 push 되지 않아 cmux 좌측에 표시가 멈춤. 테스트 시 일회성으로만.
- ❌ `dispatch-slice-pane.sh` 의 spec 본문을 `wrapper send` 로 inline 전송 — cmux send 에서 timeout 위험. 항상 spec-file 경로만 전달 + 자식에게 Read 지시.
- ❌ Slice File Map 없이 슬라이스 분해 — rebase fast-forward 시 같은 파일 영역 충돌로 부모 수동 복구 비용 발생.
- ❌ Dead code 판정 시 사용처 grep + 테스트 prop 직접 주입 확인 누락 — 부모가 prop 으로 set 하는 분기를 "도달 불가" 로 오판해 삭제하면 기존 테스트가 회귀로 catch.
- ❌ 검증용 단순 curl / sleep 단독 호출 — Bash 자동 background 진입으로 동기 결과 못 받음. `timeout 5 curl ...` 또는 cmux browser eval 사용.
- ❌ cmux 환경 plan Mode 컬럼에 `direct-edit` — **`enforce-cmux-dispatch`** hook 이 ExitPlanMode 차단. cmux 기본은 dispatch(cmux). 예외는 plan 콘텐츠가 아니라 out-of-band env: `CMUX_DIRECT_EDIT_OK=1` escape. 비-cmux 환경은 그 반대(direct-edit 기본). `track-cmux-edit-burst` 는 advisory only(50, 차단 없음).
- ❌ dispatch spec-file 을 `/tmp/<slug>-spec.md` 등 repo 밖에 두기 — classifier transcript-blind 시 dispatch 거부 위험. `.claude/specs/<slug>.spec.md` 컨벤션 사용.
- ❌ Goal Statement 에 `<!-- machine-checks -->` bash block 누락 — Phase 3 Verify 때 모델이 실행할 입력 없음. 형식 박스 그대로 따를 것.
- ❌ Goal Statement 에 측정 불가 추상 표현 ("품질 향상", "안정성 강화") 만 박기 — 모델이 PASS/FAIL 판정 못 함. `grep` / `test` / `jq` / shell command 결과 기반 bash one-liner 만.
- ❌ 옵션 list (A/B/C) 를 plain text 로 응답 끝에 dump 하고 turn 종료 — selection chip UI 가 안 떠 사용자 입력 비용 증가, plan-dev 흐름 끊김. AskUserQuestion 의무 (Phase 1-1 `정반대 가능` trigger 매치 시).
- ❌ opt-in 없이 `Workflow` 툴 호출 — 수십 agent 비용. 사용자가 "workflow"/"multi-agent" 명시 또는 명시 지시(예: "모든 수로 검증")/ultracode on 일 때만. 그 외엔 단일 `Agent`.
- ❌ cmux 시각화 의도 슬라이스를 `Workflow` 로 돌려 사이드바에서 안 보이게 — Workflow agent 는 cmux surface 아님(상호배타 런타임). 시각 실행은 `--mode=cmux`, 비시각·대규모만 workflow.
- ❌ B(workflow 실행모드)를 비-cmux **기본값**으로 격상 — opt-in 유지. 환경별 기본(cmux=dispatch, 비-cmux=direct-edit)은 안 뒤집음.
- ❌ `.claude/workflows/*.mjs` 를 `node --check` 로 직접 검증 — top-level return/await 로 SyntaxError. export-strip + async fn wrap 후 검사 (`tests/workflow_integration_lint.sh` 참조).
- ❌ `S1`/`S2` 등 슬라이스 라벨 또는 `merge:` 를 최종 커밋 메시지·브랜치명에 노출 — 협업자는 슬라이스 번호를 모름. commit-advisor 가 squash·위생 추천, rebase-ff 로 merge 커밋 자체 제거.
- ❌ cmux 환경에서 "정책/하네스/문서 파일이니 direct-edit 가 맞다"며 반사적 direct-edit — 자기수정도 dispatch(cmux) 기본. `CMUX_DIRECT_EDIT_OK=1` 는 dispatch 자체가 불가한 환경 등 진짜 예외 한정.
- ❌ 테스트에 now 와의 관계를 가정한 절대 날짜 리터럴(2026-01-01 식 start_ts 등) — 시점 지나면 rot. now-offset(relative)으로.
- ❌ 병렬 슬라이스 통합 시 worktree 점유 브랜치를 rebase 시도 / rebase+cleanup 을 한 `&&` 체인에 — 중간 실패가 미머지 브랜치 삭제. worktree remove 먼저, cleanup 은 머지 후. disjoint 슬라이스(파일 비충돌)는 rebase 말고 `cherry-pick` 권장 — worktree/main-HEAD footgun 자체 회피.

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
| `DISPATCH_VERIFY` | 1 (on) | `dispatch-slice-pane.sh` cmux 자식 claude TUI 기동 검증. `0` 이면 스킵 (기존 동작 보존). |
| `DISPATCH_VERIFY_TRIES` | 3 | `dispatch-slice-pane.sh` TUI 기동 검증 최대 재시도 횟수. |
| `SKIP_DISPATCH_TRUST` | unset | `dispatch-slice-pane.sh` worktree trust 시딩 1회 우회 (`trust-dir.sh` 호출 skip) |
| `CBP_CLAUDE_CONFIG` | `~/.claude.json` | `trust-dir.sh` 가 읽고 쓸 Claude config 경로 override. 테스트 mock 에 사용. |
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
| `CBP_LAUNCH_VERIFY_TRIES` | 5 | `cmux-pane.sh launch` 후 PTY terminal 검증 루프 최대 시도 횟수. 각 회: send-key Enter → sleep `CBP_WARMUP_SLEEP` → `_cbp_surface_is_terminal` 확인. 끝내 실패 시 die(exit 3). `CBP_DISABLE_WARMUP=1` 시 루프 자체 스킵. |
| `CBP_SEND_CONFIRM` | unset (ON) | `cmux-pane.sh send` 의 제출 확인 재시도 ON/OFF. `0` 이면 OFF (기존 동작). unset = ON (기본). |
| `CBP_SEND_CONFIRM_TRIES` | 3 | `cmux-pane.sh send` confirm 루프 최대 재시도 횟수. |
| `CBP_SEND_CONFIRM_SLEEP` | 0.6 | `cmux-pane.sh send` confirm 루프 각 슬립 초. |
| `CBP_SEND_CONFIRM_DETACHED_TRIES` | `CBP_SEND_CONFIRM_TRIES` 값 | `cmux-pane.sh send` confirm 루프에서 rc2(PTY detached 의심) 시 Enter 재전송 최대 횟수. 기본은 `CBP_SEND_CONFIRM_TRIES` 재사용. bounded — 초과 시 포기. |
| `CBP_REAP_DRY_RUN` | unset | `cmux-pane.sh reap` dry-run 모드. `1` 이면 close 없이 "would reap" 출력 후 exit 0. |
| `CBP_REAP_IGNORE_PENDING` | unset | `cmux-pane.sh reap`(`_do_reap_one`) 이 완료 마커(✅/❌)는 떴지만 자식 input box 에 미제출 사용자 텍스트가 남아있는 pane 을 `input-pending — kept` 로 보존하는 기본 동작을 우회 — `1` 이면 pending 무시하고 강제 회수(reaped). |
| `CBP_REAP_MARKER_TRUMPS_PENDING` | 1 (on) | `cmux-pane.sh reap`(`_do_reap_one`) 이 done-marker 를 own-workspace 로 확인하면 input-pending 가드보다 우선시켜 pending 이어도 회수(`reaped ... (pending-input 무시: <텍스트>)`). `0` 이면 marker 있어도 pending 이면 kept 되는 구 동작 복원. `CBP_REAP_IGNORE_PENDING=1` 이 이보다 상위(pending 자체를 전면 무시, marker 유무 무관). |
| `CBP_REAP_ORPHANS_DRY_RUN` | unset | `cmux-pane.sh reap-orphans` dry-run 모드. `1` 이면 close 없이 "would reap <ref>" 출력 후 exit 0 (state file 변경 없음). |
| `CBP_STATE_DIR` | `~/.cache/cbp` | `cmux-pane.sh reap-orphans` 가 스캔하는 state file 디렉토리. 테스트 override 에 사용. |
| `CMUX_EDIT_BURST_THRESHOLD` | 50 | `track-cmux-edit-burst` hook 의 advisory 임계치. 디폴트 50 — 부모 50 Edit 까지 silently pass, 51번째부터 stderr advisory (차단 X, strict env 미지정 시). count file 은 **cmux workspace 별 독립** (`~/.cache/cbp/edit-burst-<workspace_id>.count`) — 다른 workspace 끼리 count 공유 안 됨. |
| `CMUX_EDIT_BURST_IDLE_SEC` | 300 | `track-cmux-edit-burst` hook 의 자동 리셋 idle 초 |
| `CMUX_EDIT_BURST_STRICT` | unset | `track-cmux-edit-burst` hook strict 모드 (exit 2 차단). settings.json 의 inline 설정은 제거됨 — 디폴트 advisory only. 명시 set 시만 차단 (회귀 가드 보존). |
| `SKIP_CMUX_EDIT_BURST` | unset | `track-cmux-edit-burst` hook 1회 우회 |
| `DISABLE_CMUX_EDIT_BURST_HOOK` | unset | `track-cmux-edit-burst` hook 영구 비활성화 |
| `CBP_BURST_FILE` | unset | `track-cmux-edit-burst` hook 카운터 파일 경로 override (테스트 mock) |
| `SKIP_CMUX_REAP` | unset | `plan-dev-session.sh start` 및 `finish-plan-dev.sh` 의 reap-orphans best-effort 호출 skip |
| `SKIP_PLAN_DEV_CMUX_CLEANUP` | unset | `finish-plan-dev.sh` push 후 cmux 자식 surface cleanup 1회 우회 |
| `DISABLE_PLAN_DEV_CMUX_CLEANUP` | unset | `finish-plan-dev.sh` push 후 cmux cleanup 영구 비활성 |
| `SKIP_COMMIT_ADVISOR_GATE` | unset | `finish-plan-dev.sh` push 직전 commit-advisor 게이트 1회 우회 (`.git/plan-dev-commit-advised` 부재 허용) |
| `DISABLE_COMMIT_ADVISOR_GATE` | unset | `finish-plan-dev.sh` commit-advisor 게이트 영구 비활성화 |
| `SKIP_PLAN_MODE_ENFORCE` | unset | `enforce-plan-mode.sh` PreToolUse hook 1회 우회 (plan mode 미진입 차단 bypass) |
| `DISABLE_PLAN_MODE_ENFORCE_HOOK` | unset | `enforce-plan-mode.sh` 영구 비활성화 |
| `PLAN_MODE_SESSION_FILE` | auto | `enforce-plan-mode.sh` 마커 경로 override (디폴트 `$CLAUDE_PROJECT_DIR/.git/plan-dev-session.json`, 테스트 mock) |
| `PLAN_MODE_PLANS_DIR` | `$HOME/.claude/plans` | `enforce-plan-mode.sh` / `enforce-dispatch-gate.sh` 가 plan 파일을 찾는 디렉토리 override (테스트 mock) |
| `CMUX_DIRECT_EDIT_OK` | unset | `enforce-cmux-dispatch.sh` 의식적 escape — cmux 환경 plan direct-edit ExitPlanMode 게이트 1회 통과 |
| `SKIP_CMUX_DISPATCH_GATE` | unset | `enforce-cmux-dispatch.sh` 1회 우회 |
| `DISABLE_CMUX_DISPATCH_GATE_HOOK` | unset | `enforce-cmux-dispatch.sh` 영구 비활성화 |
| `SKIP_DISPATCH_GATE` | unset | `enforce-dispatch-gate.sh` 1회 우회 — dispatch plan mode 게이트 bypass |
| `DISABLE_DISPATCH_GATE_HOOK` | unset | `enforce-dispatch-gate.sh` 영구 비활성화 |
| `DISPATCH_GATE_SESSION_FILE` | auto (`<git-common-dir>/plan-dev-session.json`) | `enforce-dispatch-gate.sh` 의 세션 marker 경로 override (테스트 mock) |
| `RELEASE_DRY_RUN` | unset | `release.sh` 의 git commit/tag/push + gh release 를 실행 없이 echo (버전 파일 쓰기도 skip) |
| `GH_CMD` | `gh` | `release.sh` 의 gh 바이너리 override (테스트 mock) |
| `GIT_PUSH_CMD` | `git push` | `release.sh` push 명령 override (테스트 mock). finish-plan-dev.sh 와 공유 이름. |
| `RELEASE_PLUGIN_JSON` | `.claude-plugin/plugin.json` | `release.sh` 버전 소스 경로 override (테스트 mock) |
| `RELEASE_MARKETPLACE_JSON` | `.claude-plugin/marketplace.json` | `release.sh` marketplace 버전 소스 경로 override (테스트 mock) |
| `CBP_REAP_ORPHANS_GRACE_SEC` | 30 | `cmux-pane.sh reap-orphans` 의 신생 surface grace 초 — state ts 가 now 기준 이 이내인 surface 는 dead 판정에서 제외 (launch 직후 race 방지) |
| `CBP_DISABLE_LAUNCH_LOCK` | unset | `cmux-pane.sh` `_do_launch_grid` 의 count-read→생성→state기록 mkdir-mutex critical section 비활성화. 테스트 red baseline 전용 — 운영 사용 금지(병렬 dispatch race 재발) |
| `CBP_LAUNCH_DEBUG` | unset | `cmux-pane.sh launch` 진단 로깅 — `1` 이면 `_do_launch_grid` 의 생성 경로(new-pane/new-split raw_out), prev_surface, verify 루프 각 시도의 read-screen 출력을 stderr 로 dump. unset(off) 시 동작·출력 완전 불변(추가 read-screen 호출 없음). |
| `CLAUDE_TDD_STRICT` | unset | `enforce-test-first.sh` strict 모드 — production 파일에 대응 테스트 없이 Write/Edit 시 차단(exit 2). unset 시 경고만 |
| `CBP_REAP_FAST_CHECK` | 1 (on) | `cmux-pane.sh reap` 의 done-marker fast-path 스위치. 자식 Stop hook(`notify-slice-done.sh`) 이 남긴 `cbp-slice-done-<sanitized branch>` 첫 줄이 대상 surface ref 와 일치하면 `do_wait_idle` 스킵 후 바로 capture. `0` 이면 기존 wait-idle 경로 그대로. |
| `SKIP_SLICE_DONE_NOTIFY` | unset | `notify-slice-done.sh` Stop hook 1회 우회 (notify + marker 생성 모두 skip) |
| `DISABLE_SLICE_DONE_NOTIFY` | unset | `notify-slice-done.sh` Stop hook 영구 비활성화 |
| `CBP_NOTIFY_ANY_WORKTREE` | unset | `notify-slice-done.sh` 가 `.worktrees/*` 밖의 worktree 에서도 notify+marker 생성하도록 하는 escape (기본은 `.worktrees/*` 자식만 대상) |
| `SKIP_REAP_ON_STOP` | unset | `hooks/reap-on-stop.sh` 1회 우회 |
| `DISABLE_REAP_ON_STOP` | unset | `hooks/reap-on-stop.sh` 영구 비활성화 |
| `CBP_PANE_BIN` | `scripts/cmux-pane.sh` | `hooks/reap-on-stop.sh` 가 reap 호출에 사용할 wrapper 경로 override (테스트 mock) |
| `CBP_SELF_PANE` | unset | `dispatch-slice-pane.sh` 가 자식 셸에 주입하는 env(사용자가 직접 설정하는 값 아님) — 자식의 정확한 `surface:N` ref. `notify-slice-done.sh` done-marker line1 이 이 값을 우선 사용(폴백 `$CMUX_SURFACE_ID`) |
| skip-once marker 채널 3종 | (파일 부재) | `enforce-plan-mode.sh`/`enforce-cmux-dispatch.sh`/`enforce-dispatch-gate.sh` 공통 1회 escape. 경로: `<git-common-dir>/cbp-skip-once-{plan-mode,cmux-dispatch,dispatch-gate}` (존재 시 hook 이 rm 하며 통과, 자동 1회 소모). `enforce-cmux-dispatch.sh` 만 비-git 폴백 `$HOME/.cache/cbp/cbp-skip-once-cmux-dispatch-<sanitized CMUX_WORKSPACE_ID>` 지원 |

## 향후 작업 (플러그인화)

본 repo 는 최종적으로 Claude Code 플러그인 형태로 패키징될 예정. 그 시점에:
- `install.sh` 는 플러그인 manifest 로 대체.
- `.claude/` 디렉토리 구조는 유지하되 plugin 메타데이터 추가.
- 글로벌 / 프로젝트 scope 는 플러그인 enable 방식으로.

지금은 sh 기반 설치로 충분 — 플러그인화는 안정화된 후.
