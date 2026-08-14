# dispatch 진단 가이드 (문제 발생 시)

## 계보 원장 · 회수 계약 (`scripts/reap-agents.sh`)

**전제**: Claude 세션 레코드(`~/.claude/sessions/<pid>.json`)에는 **부모 필드가 없다** (2026-08-14 실측 — `pid`/`sessionId`/`cwd`/`kind`/`status` 뿐). 데몬 로그의 `spawned-by` 는 데몬 실행자이지 세션 계보가 아니다. 즉 **spawn 시점에 우리가 기록하지 않으면 "누가 내 자식인가" 를 영영 알 수 없고**, 회수는 전역 스윕(`reap-orphans`)에 의존하게 된다 — 그게 자기·형제 surface 를 닫던 사고의 뿌리다.

**계약**:

| 시점 | 동작 |
|---|---|
| spawn | `reap-agents.sh record --kind=<cmux\|tmux\|bg\|subagent> --ref=<ref>` — `dispatch-slice-pane.sh` 가 자동 호출 (`SKIP_SPAWN_LEDGER=1` 우회) |
| 회수 | `reap-agents.sh reap [--apply] [--orphans]` — **원장에 적힌 것만** 회수 |
| 감사 | `reap-agents.sh audit` — 회수 없이 원장 + 세션 현황만 |

원장 경로는 `${CBP_LEDGER_DIR:-~/.cache/cbp/ledger}/<origin>.jsonl`, `origin` 은 부모 세션 id.

**자기 보호가 구조로 보장된다**:
- `record` 는 자기 surface(`CMUX_SURFACE_ID`/`CBP_SELF_PANE`)와 조상 pid 를 **기록 자체를 거부**한다 → 원장에 자신이 없으니 회수 대상이 될 수 없다.
- `reap` 은 타 세션 원장을 기본으로 건드리지 않고, `--orphans` 를 줘도 **origin 이 살아있으면 보존**한다(원천 보존). origin 이 죽은 원장만 고아로 간주해 정리한다.
- 기본이 dry-run. `--apply` 를 줘야 실제로 나가고, `REAP_AGENTS_DRY_RUN=1` 이 그마저 무력화한다.

**비자명 함정 (구현 중 실측)**: 조상 pid 판정을 `_pid_chain | grep -qx "$pid"` 로 쓰면 안 된다. `grep -q` 가 매치 즉시 파이프를 닫아 `_pid_chain` 이 SIGPIPE(141)로 죽고, `set -o pipefail` 이 그 실패를 파이프라인 결과로 삼아 **매치했는데 조건이 거짓**이 된다 — 자기 보호가 조용히 꺼지는 형태다. 파이프 없는 루프(`_is_ancestor_pid`)로 판정한다.

## 자식이 작업 중반에 죽는다 — 자식 자살 (2026-08-13 원인 확정)

**증상**: 자식이 정상 작업하다 특정 Bash 호출 직후 응답 없이 사라진다. surface 가 `capture` 에서 `not_found`, 심하면 **형제 자식까지 동시에** 사라진다. 부분 산출물은 worktree 에 남는다.

**원인**: 자식이 `finish-plan-dev.sh` 를 (보통 테스트를 통해) 실행하면 push 성공 경로가 `do_cmux_cleanup()` 을 호출한다. 이 함수의 가드는 **`CMUX_WORKSPACE_ID` 존재 여부뿐**이고 dispatch 된 자식은 그 값을 상속한다 → 임시 repo 대상 테스트인데도 `cmux-pane.sh cleanup` + `reap-orphans` 가 **실제 workspace** 에 나가 자기/형제 surface 를 닫는다.

**진단** (2분): 자식 transcript 의 마지막 `tool_use` 를 본다 — `~/.claude/projects/<worktree 경로 sanitized>/*.jsonl` 의 마지막 줄이 `tool_result` + `attachment` 로 끝나고 뒤에 assistant 응답이 없으면 프로세스가 죽은 것(API 에러·graceful 종료는 메시지를 남긴다). 직전 명령이 `finish-plan-dev.sh` 를 타는 테스트면 이 케이스다.

**예방**: `finish-plan-dev.sh` 를 실제 실행하는 테스트는 상단에 반드시 선언한다.
```bash
export SKIP_PLAN_DEV_CMUX_CLEANUP=1
export SKIP_CMUX_REAP=1
```

**구별할 것**: launch 직후(첫 tool 실행 **전**) `Terminal surface not found` 로 죽는 건 **다른 기제**다 — surface 는 등록되나 terminal 이 attach 되지 않는 문제로 원인 미해결. `CBP_LAUNCH_DEBUG=1` 로 launch raw_out 확보가 다음 스텝.

`cmux-dispatch.md` 의 정상 플로우에서 문제가 생겼을 때만 읽는 문서 — 정상 dispatch/reap 흐름을 따라가는 중이면 이 파일이 필요 없다.

---

## cmux dispatch 동작 모델 — 내부 동작 상세

- `dispatch-slice-pane.sh --mode=cmux` 호출 → `${CLAUDE_PLUGIN_ROOT}/scripts/cmux-pane.sh launch` 가 cmux new-split 으로 surface 생성 + zsh + 자식 `claude --permission-mode bypassPermissions` 실행 + spec prompt 송신.
- **launch 시 자동 검증 (silent 실패 방지)**:
  - (a) **PTY 검증**: surface 생성 직후 `_cbp_surface_is_terminal` 로 PTY 가 terminal 상태인지 확인. 미기동 시 Enter 재전송 후 재시도 (최대 `CBP_LAUNCH_VERIFY_TRIES`, 기본 5회). 끝내 실패 시 die(exit 3). `CBP_DISABLE_WARMUP=1` 시 이 검증 루프 스킵(기존 동작 보존).
  - (b) **자식 claude TUI 기동 검증**: `dispatch-slice-pane.sh` 가 spec prompt 송신 후 자식 화면에서 Claude TUI 기동 신호를 확인. 미기동 시 Enter 재전송으로 재시도 (최대 `DISPATCH_VERIFY_TRIES`, 기본 3회). 끝내 실패 시 exit 비0. 우회: `DISPATCH_VERIFY=0`.
  - 이제 dispatch 는 silent dead surface 를 남기지 않고 loud-fail 한다. 끝내 실패 시 `--mode=subagent` 폴백 권장.
- spec prompt 송신은 자동으로 **`--enter-count=2`** 적용 (Claude TUI paste mode 끝의 첫 Enter 는 newline 으로 처리되어 명령 실행 안 됨 — 추가 Enter 필요).
- 진단 시퀀스 (자식이 진행 안 하는 듯할 때 — 검증 통과 후에도 멈춰 보이는 경우 보조 수단):
  1. `cmux tree | grep surface:<N>` — surface 살아 있는지.
  2. `cmux read-screen --surface surface:<N>` — `Terminal surface not found` 이면 detached. `cmux send-key --surface surface:<N> Enter` 1~2회로 활성화.
  3. 활성화 후 자식이 spec prompt 받은 상태 (`✳ Forming…` / `Undulating…` 등 thinking) 이면 정상.
- **reap 의 marker/pending 판정 근거**: 부모가 회수하는 `${CLAUDE_PLUGIN_ROOT}/scripts/cmux-pane.sh reap --pane=surface:<N>` 는 완료 감지 시 자동 탭 종료, 미완료면 보존한다. 완료 마커는 떴지만 자식 input box 에 미제출 사용자 텍스트가 남아있으면 원칙적으로 `input-pending — kept` 로 보존한다(강제 회수: `CBP_REAP_IGNORE_PENDING=1`). 단, done-marker 가 own-workspace 로 확인되면 이 pending 가드보다 marker 를 우선시켜(`CBP_REAP_MARKER_TRUMPS_PENDING`, 디폴트 1) 자동 회수하고 출력에 `reaped ... (pending-input 무시: <텍스트>)` 로 무시된 입력을 부기한다 — cmux workspace 에 잔존하는 composer draft/오버레이(예: `❯ push it`)가 모든 자식 surface 의 화면 캡처에 그대로 찍혀 input-pending 가드가 상시 오탐하는 문제가 실증됐기 때문(갓 만든 자식 2개가 동일 텍스트를 보인 것으로 확인). marker 가 없는 경로는 기존 보수 가드(`input-pending — kept`) 그대로 유지. (내부적으로 wait-idle → capture → grep ✅/❌ → close-surface 흐름. finish-plan-dev 의 bulk cleanup 은 backstop 으로 남음.)
- 사용자가 직접 자식 화면 보기: cmux 사이드바의 surface 탭 클릭.
- **자식 worktree trust 자동 시딩** (`trust-dir.sh`, cross-machine): dispatch 는 worktree launch 직전 `hasTrustDialogAccepted` 를 자동 set — fresh 머신에서 trust 다이얼로그에 막혀 자식이 멈추는 케이스 회피. 우회: `SKIP_DISPATCH_TRUST=1`.
- **완료 push 알림** (`hooks/notify-slice-done.sh`, 자식 쪽 Stop hook): 자식이 turn 을 마칠 때마다 (a) `cmux notify` 로 부모 사이드바에 즉시 알림 push (`✅ <branch> 완료` / `❌ <branch> 실패` / 판정 불가 시 `🔔 <branch> turn 종료`), (b) `<git-common-dir>/cbp-slice-done-<branch sanitized: / → _>` done-marker 파일에 **2줄** 기록 — line1 surface ref(dispatch 주입 `$CBP_SELF_PANE` 우선, 폴백 `$CMUX_SURFACE_ID`), line2 `$CMUX_WORKSPACE_ID`(타 workspace 오사용 차단). 우회: `SKIP_SLICE_DONE_NOTIFY=1`(1회) / `DISABLE_SLICE_DONE_NOTIFY=1`(영구), 비-dispatch worktree escape `CBP_NOTIFY_ANY_WORKTREE=1`. ⚠️ Stop hook 은 **plugin 버전에 등록**되므로 sshworld plugin 버전을 올린 직후에는 이미 실행 중인 세션엔 반영 안 됨 — 새 세션(자식 재기동)부터 유효.
- **자동 회수 체인**: 자식 완료(notify+marker) → **부모 다음 turn 경계에 `hooks/reap-on-stop.sh`(부모 쪽 Stop hook) 가 marker 를 자동 소비해 targeted reap** (감시 루프 없이도 동작). 표준 감시 루프(`watch`)는 이 자동 회수의 **즉시성 보강 + hook 미배선(구버전 plugin) belt** 일 뿐 필수 경로가 아니다. 단, 부모가 완전히 idle(추가 turn 없음) 상태면 다음 turn 경계 자체가 없어 회수도 안 일어나는 게 본질 한계 — 이 경우 (a) notify 알림으로 사용자가 인지해 직접 회수하거나 (b) 감시 루프를 돌려 폴링으로 회수한다. 우회: `SKIP_REAP_ON_STOP=1`(1회) / `DISABLE_REAP_ON_STOP=1`(영구).

## Dispatch wrapper 가용성 검증 (회복력 룰)

- (a) wrapper PWD-relative path (`${CLAUDE_PLUGIN_ROOT}/scripts/dispatch-slice-pane.sh`) 가 안 보이면 → SessionStart system-reminder 가 노출한 driver 경로로 직접 호출 시도. 검색 결과 부재 ≠ 실행 불가.
- (b) 검색 권한 거부 (find/glob/grep 막힘) ≠ 실행 권한 거부. 검색 막혔다고 실행도 막혔다고 단정 금지 — 절대경로 호출 자체는 별도 권한.
- (c) classifier/sandbox 가 권한 거부 메시지에 "사용자에게 설명/확인" 안내를 포함하면 그대로 따른다. 자동 fallback 금지.
- (d) 사용자가 명시 선택한 mode 의 **핵심 가치** (cmux=시각화, subagent=토큰 추적, pane=tmux 격리) 를 날리는 fallback 결정은 **AskUserQuestion 으로 확인**. 자동 결정 금지.

## cross-WS dead orphan 자동 정리 (reap-orphans) — 수동 실행

`cmux-pane.sh reap-orphans` 는 **현재 workspace 뿐 아니라 모든 workspace** 의 잔존 dead surface 를 회수한다. 이전 plan-dev 세션이 `finish-plan-dev.sh` 없이 종료됐거나 crash 로 cleanup 을 못 한 경우에도 다음 plan-dev 시작 시 자동으로 dead orphan 을 정리한다.

살아있는 타 세션 자식 surface 는 **보호** (alive 판정 = `cmux read-screen` rc0). self surface 는 항상 skip.

수동 실행 (미리보기 포함):
```bash
# 미리보기 (실제 close 없음)
CBP_REAP_ORPHANS_DRY_RUN=1 ${CLAUDE_PLUGIN_ROOT}/scripts/cmux-pane.sh reap-orphans
# 실제 회수
${CLAUDE_PLUGIN_ROOT}/scripts/cmux-pane.sh reap-orphans
```

우회: `SKIP_CMUX_REAP=1` (plan-dev 자동 호출 skip). `CBP_STATE_DIR` 로 스캔 디렉토리 override.
