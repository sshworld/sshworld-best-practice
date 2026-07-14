# Known Issues

감사에서 발견됐지만 이번 문서 정비(S5) 범위 밖이라 기록만 남기는 항목. 코드 수정 없음 — 추후 별도 슬라이스에서 처리.

| # | 위치 | 증상 | 심각도 |
|---|---|---|---|
| 1 | `scripts/trust-dir.sh` | read-modify-write lock 부재 — 병렬 dispatch 시 trust 시딩(hasTrustDialogAccepted) 유실 가능 | 중 |
| 2 | `scripts/release.sh` (publish) | 중간 실패 시 재개 불가 — tag/commit 잔존을 수동으로 untangle 해야 함 | 중 |
| 3 | `scripts/release.sh` (bump) | sed 가 marketplace.json 의 **모든** version 필드를 치환 — 플러그인 2개 이상 등재 시 의도치 않은 버전 변경 위험 | 상 |
| 4 | `scripts/cmux-pane.sh` (non-grid launch, 254-262행 부근) | launch 실패 시 ref 위조 반환 — 호출자가 실패를 성공으로 오인 가능 | 상 |
| 5 | `scripts/cmux-pane.sh` (do_list) | reconcile 이 substring 매치 — `surface:1` 이 `surface:12` 에 매치되는 오탐 | 중 |
| 6 | `scripts/cmux-pane.sh` (`_cbp_lock`) | stale-reap edge — pid 파일 기록 전 window / pid 재사용 시 launch hang 가능 | 중 |
| 7 | `scripts/plan-dev-session.sh` | `start_pid` 가 스크립트 자신의 pid — 즉시 종료돼 pid 가드가 사실상 dead code. PID 재사용 시 false-positive 재진입 거부 | 하 |
| 8 | `scripts/dispatch-slice-pane.sh` (auto-cleanup) | 비-plan-dev 연속 dispatch 시 auto-cleanup 이 자기파괴적으로 잔존 — stamp 는 plan-dev marker 있을 때만 적용됨 | 하 |
| 9 | `scripts/dispatch-slice-pane.sh` (cleanup stamp) | 크래시 후 24h 내 재진입 세션은 start_ts 보존으로 cleanup skip — tmux 잔존 자식을 수동 회수해야 함 | 하 |
| 10 | `hooks/enforce-cmux-context.sh` | quote-blind false-positive — 문자열 리터럴 내부의 tmux 명령도 오검출 가능 | 하 |
| 11 | `hooks/enforce-plan-mode.sh` | `PLAN_MODE_PLANS_DIR` 이 전역 glob(`~/.claude/plans`) — 다른 프로젝트의 plan 파일로 게이트가 풀리는 cross-project false-allow | 중 |
| 12 | `hooks/enforce-doc-sync.sh` | `git -C <path> commit` / `git -c k=v commit` 형태 미검출. 커밋 메시지 본문에 `DOC_IMPACT=` 문자열이 있으면 오인 가능 | 중 |
| 13 | `hooks/track-cmux-edit-burst.sh` | 차단된 Write 도 카운트에 포함됨 + count file 에 GC 없음(무한 누적) | 하 |
| 14 | `hooks/enforce-test-first.sh` | `find .` 전체 스캔 — 대형 repo 에서 지연 발생. `*test*` substring 매치가 `latest.ts` 같은 파일을 테스트로 오인 | 중 |
| 15 | `commands/plan-dev/` 하위 참조 문서 3개 | 유령 슬래시커맨드로 노출됨 (예: `/sshworld:plan-dev:antipatterns`) — 실제 호출 불가한데 커맨드 목록에 나타날 수 있음 | 하 |
| 16 | `.claude-plugin/marketplace.json` | `allowCrossMarketplaceDependenciesOn: ["caveman"]` — 용도 불명 죽은 설정 의심 | 하 |
| 17 | `scripts/cmux-pane.sh` (reap-orphans grace) | `CBP_LAUNCH_VERIFY_TRIES` / `CBP_WARMUP_SLEEP` 를 확대하면 warmup 시간이 reap-orphans grace(기본 30초)를 초과할 수 있음 — 그 경우 정상 launch 중인 surface 가 오살될 위험 | 중 |
| 18 | cmux dispatch 전반 (2026-07-08 관측) | cmux 자식 세션 4/4 회 crash 관측 — 비결정적 자식 사망 빈도가 높음. subagent 폴백 경로는 검증됨 | 상 |
| 19 | `hooks/enforce-doc-sync.sh` (worktree cwd) | subagent 가 worktree 안에서 커밋해도 hook 프로세스가 main repo cwd 에서 `git diff --cached` 를 실행 — staged 없음으로 오탐 차단 (2026-07-08 실측). 우회는 `SKIP_DOC_SYNC=1`. hook 이 `git -C` 로 대상 repo 를 명령에서 유추하거나 `CLAUDE_PROJECT_DIR` 대신 명령 cwd 를 써야 함 | 중 |
| 20 | `scripts/cmux-pane.sh` (`_send_is_submitted`) | `LC_ALL=C` 환경에서 `[❯>]` bracket expression 이 byte 단위로 해석 — box-drawing 문자(0xE2 선두 바이트)가 오매치될 수 있어 rc1(false-keep)로 이어져 정상 완료 pane 이 안 닫히는 (누수) 케이스 가능 | 중 |
| 21 | `scripts/cmux-pane.sh` (`_do_reap_one` DONE_PATTERN) | DONE_PATTERN 이 화면 전체를 grep — spec 본문이나 echo 출력에 `✅`/`❌` 리터럴이 우연히 포함되면 조기 reap 가능. pending 체크(`_send_is_submitted`)가 이를 막는 유일한 가드 | 중 |
