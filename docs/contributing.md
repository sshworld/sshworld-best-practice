# 추가 / 수정 체크리스트 & 파일별 책임

> 상위 문서: [CLAUDE.md](../CLAUDE.md)

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
- [ ] 릴리즈 노트 한글 형식 준수 ([release.md](./release.md) 참조).

## 파일별 책임 분리

| 파일 | 책임 |
|---|---|
| `scripts/release.sh` | 릴리즈 자동화 — draft(type별 한글 skeleton)/publish(bump+commit+태그+push+gh release)/backfill(과거 소급 태그+release). 버전 소스 plugin.json+marketplace.json 동기화. `RELEASE_DRY_RUN`/`GH_CMD`/`GIT_PUSH_CMD` mock. 노트 body 는 Claude 가 작성해 --notes-file 로 전달. |
| `commands/plan-dev.md` | 사용자 entry point. 단계별 가이드와 안티패턴. Phase 6 = `/fork` 스킬 직접 호출(세션 클로저). |
| `commands/plan-dev/troubleshooting-dispatch.md` | dispatch 진단 가이드 (문제 시에만 로드) — cmux-dispatch.md 의 정상 플로우와 분리된 launch 검증/진단 시퀀스/reap 판정 근거/wrapper 가용성 검증 상세. |
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
| `scripts/cmux-pane.sh` | cmux wrapper — launch/send/capture/wait-idle/kill/**reap**/**reap-orphans**/list/cleanup/status/**notify/set-status**/**watch**. `CMUX_BIN` env 로 mock 가능. `CBP_LIST_LINES` / `CLAUDE_FAKE_SELF_CMUX_WS` 로 테스트 mock 지원. state file 헬퍼(sanitize + mkdir-mutex + ts, pid 기반 stale reap). launch 는 count-read→cmux생성→state기록 을 단일 mkdir-mutex critical section 으로 묶어 병렬 dispatch race-safe (우회 `CBP_DISABLE_LAUNCH_LOCK=1` 은 테스트 red baseline 전용). launch 후 PTY 검증 재시도(`CBP_LAUNCH_VERIFY_TRIES`, 기본 5), 끝내 미기동 시 die(exit 3). `CBP_DISABLE_WARMUP=1` 시 검증 루프 스킵. 좀비 surface 방지: 생성 성공 직후부터 launch 완료까지 EXIT trap 으로 best-effort close-surface + state 제거. `CBP_LAUNCH_DEBUG=1` 로 진단 로깅(생성 경로, prev_surface, verify read-screen). send/capture/wait-idle/kill 의 surface 판정은 `_cbp_pane_flag` 헬퍼로 중앙화. `reap --pane=<ref>`: wait-idle → capture → ✅/❌ 감지 → 완료 자식 자동 close-surface. 완료 마커가 떴어도 자식 input box 에 미제출 텍스트(`❯ text`)가 남아있으면 `input-pending — kept` 로 회수 보류 (`CBP_REAP_IGNORE_PENDING=1` 강제 회수, `CBP_REAP_DRY_RUN=1` dry-run). done-marker 가 own-workspace 로 확인되면(`CBP_REAP_MARKER_TRUMPS_PENDING`, 디폴트 1) pending 보다 marker 우선 회수 — cmux workspace 잔존 composer draft/오버레이가 모든 자식 화면에 찍혀 pending 오탐하던 문제 대응(`0` 이면 구 동작 복원). `reap` argless/`--all`: state 의 모든 자식에 반복 실행, 마지막 줄 `reaped N / kept M / pending P` 요약. `watch` 서브커맨드(`--interval --max-iter --idle --timeout`, exit 0/2/4/6/7)로 표준 감시 루프를 wrapper 내부로 인터페이스화. send confirm rc2 분기(PTY detached 재전송, `CBP_SEND_CONFIRM_DETACHED_TRIES`). dead surface → `died`+exit 5, reap died 시 state 제거(좀비 차단). `reap-orphans` (2-phase lock): 전체 workspace dead surface 정리, `CBP_REAP_ORPHANS_GRACE_SEC`(디폴트 30) 신생 surface 보호, `CBP_REAP_ORPHANS_DRY_RUN=1` dry-run. `do_list`/`do_cleanup` state file 우선. reap fast-path: `hooks/notify-slice-done.sh` done-marker 매치 시 `do_wait_idle` 스킵, `CBP_REAP_FAST_CHECK`(디폴트 1)로 제어. |
| `scripts/detect-pane-env.sh` | 터미널 멀티플렉서 환경 감지. stdout: `tmux` \| `cmux` \| `default`. sourcing guard 포함. |
| `scripts/cmux-title-chpwd.sh` | zsh `chpwd` hook — cd 마다 (1) cmux tab/surface title 을 `basename $PWD` 로 rename, (2) single-surface workspace 면 사이드바 workspace 이름도 갱신. multi-surface workspace(dispatch grid 등)는 skip. `~/.zshrc` 에서 source. `CMUX_BIN` env 로 mock. |
| `scripts/dispatch-slice-pane.sh` | implementor 슬라이스를 worktree + tmux/cmux pane 으로 spawn. 멀티-driver: `--mode=tmux\|cmux\|pane\|auto\|subagent`. `--model=<alias>` 자식 model 선택 (디폴트 sonnet). `--type=<feat\|fix\|refactor\|test\|docs\|chore>` 브랜치 prefix 결정. `build_child_cmd` 순수 함수 분리. `DISPATCH_DRY_RUN=1` launch 없이 분기 검증. 세션당 1회 기존 자식 pane 자동 정리 (`DISPATCH_SKIP_CLEANUP=1` 우회, stamp 파일로 원자화). cmux 경로: 자식 claude TUI 기동 검증(`DISPATCH_VERIFY`/`DISPATCH_VERIFY_TRIES`) + 실패 시 exit 비0 + subagent 폴백 안내. 자식 셸에 `CBP_SELF_PANE` env 로 정확한 `surface:N` ref 주입(cd 이후, best-effort) — 자식 claude/Stop hook 이 상속. |
| `scripts/plan-dev-session.sh` | plan-dev 세션 marker 관리 (start/query/clear). start_ref, base_branch, work_branch, start_ts, start_pid, auto_branch 기록. detached HEAD 차단. 재진입(dead pid + within_24h) 시 start_ts/start_ref 보존. marker 기록 직후 cmux 환경에서 `reap-orphans` best-effort 호출 (`SKIP_CMUX_REAP=1` 우회). start 시 stale done-marker backstop rm. |
| `scripts/plan-dev-progress.sh` | plan-dev 진행률 cmux push 헬퍼 (start/tick/show). `PLAN_DEV_SESSION_BIN` / `CMUX_PANE_BIN` env 로 mock 가능. `PROGRESS_DRY_RUN=1` 로 notify/set-status dry-run. |
| `scripts/finish-plan-dev.sh` | develop/main 분기 push 자동화 + marker clear. 브랜치 이름 충돌 시 suffix -2~-5 자동 부여. push 직전 commit-advised marker 게이트 — `.git/plan-dev-commit-advised` 부재 시 exit 2. push 성공 직후 cmux 자식 surface 자동 cleanup + reap-orphans backstop. `SKIP_PLAN_DEV_FINISH` / `DISABLE_PLAN_DEV_FINISH` / `SKIP_COMMIT_ADVISOR_GATE` / `DISABLE_COMMIT_ADVISOR_GATE` / `SKIP_PLAN_DEV_CMUX_CLEANUP` / `DISABLE_PLAN_DEV_CMUX_CLEANUP` / `SKIP_CMUX_REAP` 우회 지원. |
| `hooks/track-cmux-edit-burst.sh` | PreToolUse Write\|Edit. cmux env Edit/Write 누적 N회 advisory (디폴트 임계치 **50**). 디폴트 advisory only. `CMUX_EDIT_BURST_STRICT=1` env 명시 시만 차단(exit 2). count file 은 cmux workspace 별 독립. mtime idle 기반 자동 리셋. 자식 worktree(git-dir != git-common-dir) 감지 시 자동 skip. |
| `hooks/enforce-cmux-dispatch.sh` | PreToolUse ExitPlanMode. cmux env 에서 plan Slice File Map 의 `direct-edit` 표셀 탐지 시 exit 2 차단. `CMUX_DIRECT_EDIT_OK=1` 의식적 escape (1회). `SKIP_CMUX_DISPATCH_GATE=1` / `DISABLE_CMUX_DISPATCH_GATE_HOOK=1` 우회. 비-cmux 환경 no-op. |
| `hooks/cmux-dispatch-hint.sh` | SessionStart. cmux env 시 dispatch-first advisory 를 stdout(additionalContext)으로 inject. 비-cmux 환경은 무출력. |
| `hooks/enforce-plan-mode.sh` | PreToolUse Write\|Edit. `/plan-dev` plan mode 진입 강제 — marker 활성 + plan mode 미진입 상태에서 Write/Edit 시도 시 exit 2 차단. 판정: marker `start_ts` 이후 작성된 plan 파일 존재 여부. 자식 worktree/marker 없음/24시간 stale → allow. skip-once marker `<git-common-dir>/cbp-skip-once-plan-mode`. 우회: `SKIP_PLAN_MODE_ENFORCE` / `DISABLE_PLAN_MODE_ENFORCE_HOOK`. |
| `hooks/enforce-dispatch-gate.sh` | PreToolUse Bash. `dispatch-slice-pane.sh --slice` 명령 감지 → plan-dev 세션 활성 + plan mode 거침 확인. 자식 worktree/bypassPermissions/plan mode 중 → skip. 24시간 stale → allow. skip-once marker `cbp-skip-once-dispatch-gate`. 우회: `SKIP_DISPATCH_GATE=1` / `DISABLE_DISPATCH_GATE_HOOK=1`. |
| `hooks/record-commit-advised.sh` | PostToolUse Task\|Agent. `subagent_type` 에 `commit-advisor` substring 감지 시 `plan-dev-commit-advised` marker 자동 touch — advisor agent 의 touch 이행(LLM 준수) 의존 취약점 보강. |
| `hooks/notify-slice-done.sh` | Stop hook (cmux 자식 worktree 전용). turn 종료 시 마지막 assistant 텍스트에서 ✅/❌ 판정 → cmux notify + done-marker 파일(2줄: surface ref, workspace id) 기록. 가드: `CMUX_WORKSPACE_ID` unset / 비-자식-worktree / 비-`.worktrees/*` → `CBP_NOTIFY_ANY_WORKTREE=1` 없으면 skip. 우회: `SKIP_SLICE_DONE_NOTIFY=1` / `DISABLE_SLICE_DONE_NOTIFY=1`. |
| `hooks/reap-on-stop.sh` | Stop hook (부모 세션 전용). turn 경계마다 done-marker 를 glob 소비 → 상한 5개까지 targeted reap. 분류는 `^reaped ` 매치 최우선(reaped-first). 우회: `SKIP_REAP_ON_STOP=1` / `DISABLE_REAP_ON_STOP=1`. wrapper override: `CBP_PANE_BIN`. |

## 비자명 gotcha (CLAUDE.md 잔류분 상세)

- `merge-settings.sh` 의 dedup 이 **cur 내부 + cur-vs-new 모두** 를 대상으로 하는 이유: 과거 inline jq 의 matcher 미-unique 로 SessionStart hook 이 1024× 로 더블링되는 버그가 실사례로 있었음 — 재발 방지를 위해 install 재실행(idempotent 요구)에도 안전해야 함.
- `cmux-pane.sh reap` 의 `CBP_REAP_MARKER_TRUMPS_PENDING`(디폴트 1) 이 pending 가드보다 marker 를 우선시키는 이유: cmux workspace 에 잔존하는 composer draft/오버레이가 모든 자식 surface 화면 캡처에 그대로 찍혀 input-pending 가드가 상시 오탐했음 — marker 로 own-workspace 확인되면 그 오탐을 trump.
