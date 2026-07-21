# claude-best-practice

나만의 Claude Code 워크플로 모음. **`/sshworld:plan-dev` TDD 워크플로 + 컨텍스트 관리 + 강제 가드(하네스)** 한 세트.

`shanraisshan/claude-code-best-practice` 가이드를 베이스로, 실사용 중에 다듬은 규칙을 콘텐츠(commands/agents/skills)와 하네스(settings/hooks) 양쪽으로 구성.

---

## 구성

```
.claude-plugin/
├── plugin.json               # 플러그인 manifest (name: sshworld)
└── marketplace.json          # marketplace 배포 메타데이터
commands/
│   ├── plan-dev.md           # Phase 0~6 워크플로 (Session Start → Plan → TDD → Verify → Commit → Branch & Push → Context 정리)
│   └── parallel-consult.md   # 자식 Claude pane 띄워 한 번 질문하고 답 회수
agents/
│   ├── implementor.md        # TDD Red→Green→Refactor, <type>/<slug> worktree 격리 (+ tmux pane 모드 지원)
│   ├── verifier.md           # Read-only 빌드/테스트 실행 + diff 제안
│   ├── reviewer.md           # 치명적 이슈만 블로킹, 나머지 제안
│   └── commit-advisor.md     # 한글 Conventional Commit + DOC 영향 평가 + 다중 커밋 분석 + 히스토리 위생/squash 추천
skills/
│   ├── fork/SKILL.md         # 자식 컨텍스트에서 처리하고 요약만 반환
│   ├── tmux-orchestrate/SKILL.md # 부모-자식 Claude tmux pane 협업 패턴
│   ├── yagni/SKILL.md        # 코드 추가 前 필요성 검사 — 추측성 추상화·미사용 코드 방지
│   └── terse-output/SKILL.md # 응답 군더더기 제거 — 기술 substance 유지, 토큰 절감
hooks/
│   ├── hooks.json            # 플러그인 hooks 정의 (${CLAUDE_PLUGIN_ROOT} 기반 경로)
│   ├── enforce-test-first.sh # production 파일 작성 전 테스트 존재 검사
│   ├── enforce-doc-sync.sh   # commit 시점 DOC 영향 평가 강제
│   ├── limit-child-panes.sh  # 자식 tmux pane spawn 상한 (CLAUDE_MAX_CHILD_PANES)
│   ├── enforce-cmux-context.sh # cmux 안에서 tmux 계열 명령 시도 시 advisory warning
│   ├── track-cmux-edit-burst.sh # cmux env Edit/Write 누적 advisory (dispatch-first 유도). 자식 worktree 감지 시 skip
│   ├── enforce-plan-mode.sh  # PreToolUse Write|Edit — /sshworld:plan-dev plan mode 미진입 시 차단. 비-plan-dev 세션 no-op
│   ├── enforce-cmux-dispatch.sh # PreToolUse ExitPlanMode — cmux env plan direct-edit 차단
│   ├── cmux-dispatch-hint.sh # SessionStart — cmux env 면 "dispatch 기본" advisory inject (비-cmux 무출력)
│   ├── enforce-dispatch-gate.sh # PreToolUse Bash — plan mode 미진입 시 dispatch-slice-pane.sh 실행 차단
│   ├── record-commit-advised.sh # PostToolUse Task|Agent — commit-advisor 호출 감지 시 plan-dev-commit-advised marker 자동 touch
│   ├── statusline-tokens.sh  # (opt-in) 하단 status bar 모드 — 기본은 token-stats.sh 사용
│   └── token-stats.sh        # Stop hook 으로 직전 응답 토큰 사용량 + 캐시 히트율 inline 노출
.claude/
└── settings.json             # permissions(allow/deny) + hooks (project-scope dogfooding)
scripts/
├── tmux-pane.sh              # 얇은 tmux wrapper — launch/send/capture/wait-idle/kill/list/status
├── cmux-pane.sh              # 얇은 cmux wrapper — launch/send/capture/kill/reap/list/cleanup/status + state file 헬퍼
├── detect-pane-env.sh        # 터미널 환경 감지 — tmux | cmux | default
├── dispatch-slice-pane.sh    # implementor 슬라이스를 tmux/cmux pane 으로 dispatch (plan-dev --mode=pane)
├── plan-dev-session.sh       # plan-dev 세션 marker 관리 (start/query/clear)
├── plan-dev-progress.sh      # plan-dev 진행률 cmux push 헬퍼 (start/tick/show)
├── finish-plan-dev.sh        # develop/main 분기 push 자동화 + marker clear
├── trust-dir.sh              # 자식 worktree trust 자동 시딩 — cross-machine bypass (hasTrustDialogAccepted)
├── release.sh                # 릴리즈 자동화 — draft/publish/backfill (버전 bump+태그+push+gh release)
├── merge-settings.sh         # settings.json 병합 헬퍼 — allow/deny union + hooks dedup (idempotent install)
└── cmux-title-chpwd.sh       # zsh chpwd hook — cd 마다 cmux tab/workspace 제목 자동 갱신
```

---

## 설치

> ⚠️ `install.sh` 는 **deprecated**. Claude Code 플러그인으로 설치하세요.

```bash
/plugin marketplace add sshworld/sshworld-best-practice
/plugin install sshworld
```
> 명령은 `/sshworld:plan-dev` 로 호출 (플러그인 command 는 `플러그인명:command` 네임스페이스).

기존 `~/.claude` 설치본은 수동 정리(또는 `/plugin` 설치 후 중복 hook 제거) 필요.

### 동반설치 + 가역

위 `/plugin install sshworld` 한 번에 `taste-skill`·`andrej-karpathy-skills` 가 **자동으로 함께 설치**됩니다 (별도 명령 불필요). `caveman` 은 opt-in(아래).

### 토큰 절약 레이어

| 레이어 | 수단 | 비고 |
|---|---|---|
| 출력 | caveman (opt-in) | 응답 스타일 압축 |
| 스코프 | yagni skill | 추측성 코드 방지 |
| 검색 | codegraph | npx auto-fetch, per-project `init` 필요 |
| 압축 | headroom | 별도 서버 opt-in |

인프라 상세: [docs/infra-setup.md](docs/infra-setup.md)

**caveman (opt-in):** 출력 스타일을 압축 모드로 바꾸므로 기본 비활성. 원하면 별도 설치:

```bash
/plugin install caveman@sshworld-best-practice
# 또는
/plugin enable caveman
```

**제거:**

```bash
claude plugin uninstall <plugin> --prune   # 특정 플러그인 + 고아 의존성 제거
claude plugin prune                        # 고아 플러그인 일괄 정리
```

### 권장 permissions (사용자 settings.json 에 추가)

`hooks/hooks.json` 이 hook 정의를 담지만, permissions 는 플러그인이 번들할 수 없어 사용자가 수동 추가:

```json
{
  "permissions": {
    "allow": [
      "Bash(git status*)", "Bash(git diff*)", "Bash(git log*)",
      "Bash(git branch*)", "Bash(git checkout*)", "Bash(git switch*)",
      "Bash(git fetch*)", "Bash(git pull*)", "Bash(git add*)",
      "Bash(git commit*)", "Bash(git stash*)", "Bash(git merge*)",
      "Bash(git rebase*)", "Bash(git remote*)", "Bash(git tag*)",
      "Bash(git worktree*)", "Bash(git restore*)",
      "Bash(tmux new-window*)", "Bash(tmux send-keys*)",
      "Bash(tmux capture-pane*)", "Bash(tmux display-message*)",
      "Bash(tmux list-panes*)", "Bash(tmux kill-pane*)", "Bash(tmux-cli*)",
      "Bash(cmux new-workspace*)", "Bash(cmux new-pane*)", "Bash(cmux new-split*)",
      "Bash(cmux send *)", "Bash(cmux send-key*)", "Bash(cmux read-screen*)",
      "Bash(cmux list-workspaces*)", "Bash(cmux list-panes*)",
      "Bash(cmux list-pane-surfaces*)", "Bash(cmux close-surface*)",
      "Bash(cmux close-workspace*)", "Bash(cmux tree*)", "Bash(cmux ping*)",
      "Bash(cmux identify*)", "Bash(cmux notify*)", "Bash(cmux set-status*)",
      "Bash(cmux set-progress*)", "Bash(cmux clear-status*)", "Bash(cmux clear-progress*)",
      "Bash(cmux rename-tab*)", "Bash(cmux workspace-action*)",
      "Bash(*/scripts/tmux-pane.sh*)", "Bash(*/scripts/cmux-pane.sh*)",
      "Bash(*/scripts/detect-pane-env.sh*)", "Bash(*/scripts/dispatch-slice-pane.sh*)",
      "Bash(*/scripts/finish-plan-dev.sh*)", "Bash(*/scripts/plan-dev-progress.sh*)"
    ],
    "deny": [
      "Bash(rm -rf*)", "Bash(git push --force*)", "Bash(git push -f*)",
      "Bash(git commit --no-verify*)", "Bash(git reset --hard*)",
      "Bash(tmux kill-server*)"
    ]
  }
}
```

---

## 사용

### 메인 워크플로 — `/sshworld:plan-dev`

```text
/sshworld:plan-dev "이메일 인증 회원가입 추가"
```

자동 진행 흐름:
0. **Session Start** (Phase 0): `plan-dev-session.sh start` 자동 호출 — start_ref, base_branch 기록
1. **Explore**: 관련 파일 자동 스캔 — 단축키·라우팅·전역 listener 류 작업은 `page.tsx` / `layout.tsx` 같은 상위 컨테이너 컴포넌트 포함
2. **빈틈 진단**: `AskUserQuestion` 으로 요구사항 명확화 반복 (옵션 list 제시 시 plain text dump 금지)
3. **EnterPlanMode**: plan 파일 작성 (200줄 이하 권장) + slice 별 type 결정 + Slice File Map 의 `Mode` / `DOC_IMPACT` 컬럼 미리 결정
4. **Staff Engineer Plan Review**: Plan 서브에이전트 비평 (선택)
5. **ExitPlanMode**: 사용자 승인
6. **TDD Execute**: 병렬 implementor → `<type>/<slug>` worktree 격리, Red→Green→Refactor — 진단 기록은 plan 파일 또는 `<plan>-notes.md` 에 즉시 기록
7. **Verify**: rebase fast-forward 머지 + verifier 빌드/테스트 (max 5회 루프)
8. **Review**: reviewer 치명적 이슈 점검 (선택)
9. **Commit**: commit-advisor 다중 커밋 분석 → 한글 메시지 + `<type>/<slug>` 브랜치명 추천
10. **Branch & Push** (Phase 5): `finish-plan-dev.sh` 로 develop/main 분기 push 자동화
11. **Context 정리** (Phase 6): **`/fork` 스킬을 직접 호출** — 잔여 정리(unlocked worktree-agent-* cleanup 등) + 세션 요약 후, fork 가 마지막 줄에 다음 명령(`/clear`/`/compact`) 추천
12. **Goal Statement**: plan 의 `## Goal Statement` — Phase 1-1 Acceptance criteria 를 측정가능 form(`<!-- machine-checks -->` bash one-liner) 으로 옮긴 것. Phase 3 Verify 에서 모델이 직접 실행해 완료 판정.
13. **자식 surface 자동 cleanup** (Phase 5 끝): `finish-plan-dev.sh` 가 push 성공 직후 cmux 자식 surface (`cbp-*` 등 state file 등록 surface) 일괄 close. 사용자 수동 정리 0.
14. **cross-WS dead orphan 자동 정리**: `plan-dev-session.sh start`(Phase 0) 및 `finish-plan-dev.sh`(Phase 5) 가 best-effort 로 `cmux-pane.sh reap-orphans` 를 호출 — 이전 세션이 finish 없이 종료해 잔존하는 dead 자식 surface 를 모든 `~/.cache/cbp/children-*.json` 에 걸쳐 회수. 살아있는 타 세션 자식은 보호, self surface 제외. 우회: `SKIP_CMUX_REAP=1`.

### 보조 — `/fork`

현재 흐름의 작업을 격리된 서브에이전트에 위임하고 부모 세션엔 요약만 반환:

```text
/fork
```

---

## Workflow 통합 (dynamic workflows)

Claude Code 의 **dynamic workflows**(`Workflow` 툴 — JS 스크립트로 subagent fan-out / pipeline / loop 를 결정론 오케스트레이션)를 `/sshworld:plan-dev` 특정 Phase 에 **opt-in** 으로 결합한다. plan-dev 는 슬래시 커맨드이므로 그 가이드가 Workflow 호출을 지시하는 것 자체가 적법한 opt-in 트리거.

### 어디에 쓰나 (A / B / C)

| 구분 | plan-dev 위치 | Workflow 패턴 |
|---|---|---|
| **A** Plan/Review 보강 | Phase 1-3 / 3.5 | judge panel(독립 비평 N→합성) · multi-dimension 적대 verify(refute 다수결) |
| **B** workflow 실행 모드 | Phase 2 (opt-in) | `pipeline(slices, implement, verify)` + `isolation:'worktree'` |
| **C** 대규모 escape hatch | audit / migration | loop-until-dry · multi-modal sweep · `resume` |

reference 스크립트: `.claude/workflows/{plan-review-panel,slice-pipeline,codebase-audit}.mjs` — `Workflow({scriptPath})` 로 실행하거나 inline `script:` 로 paste. (`.claude/workflows/` 는 Workflow 툴 reference — 이동하지 않음.)

- `vuln-scan-pipeline.mjs` — 정적 vuln 스캔 파이프라인 프로토타입. defending-code-reference-harness 의 find→grade→judge→report 를 Workflow 골격으로 재현. vuln-class 별 FIND → JS dedup(JUDGE) → 적대 다수결(GRADE) → severity 랭킹(REPORT). 코드 실행/빌드 없는 정적 한정.

### ⚠️ cmux ⇄ workflow 상호배타 (트레이드오프)

| | cmux dispatch | Workflow 툴 |
|---|---|---|
| 자식 표현 | cmux 사이드바 surface (attach/시각화) | `/workflows` 진행 트리 (내부 Task 러너) |
| 적합 | 시각적 슬라이스 실행 | 비시각·추론집약·대규모 |
| 토큰 추적 | 부모 token-stats ✗ | budget 공유 풀 |

Workflow agent 는 **cmux surface 가 아니다** — 다른 런타임이라 한 작업에서 둘을 섞지 말고 슬라이스 단위로 분리한다. opt-in 발동: 사용자가 "workflow"/"multi-agent" 명시, 또는 명시 지시(예: "모든 수로 검증"), ultracode on.

---

## 병렬 Claude 협업 (tmux pane)

부모 Claude 세션에서 **다른 tmux pane** 의 CLI 에이전트(또 다른 Claude / 디버거 / 장시간 스크립트)와 통신.

### Prerequisite

- `tmux` — `brew install tmux`
- (권장) 외부 `tmux-cli` — `uv tool install claude-code-tools`. 미설치 시 본 repo 의 `scripts/tmux-pane.sh` 가 폴백.

### `/parallel-consult` — 자식 Claude 에게 한 번 묻기

```text
/parallel-consult "이 함수의 시간복잡도는?"
```

부모가 자식 Claude pane 을 띄워 질문 → 응답 회수 → 부모 세션에 요약 + "자식 pane 유지/kill" 묻기. 자세한 흐름은 `commands/parallel-consult.md`.

### Branch Convention

| 규칙 | 설명 |
|---|---|
| 브랜치명 형식 | `<type>/<slug>` — `feature/user-signup`(type=feat→branch prefix feature/), `fix/auth-token`, `test/session-marker` 등 |
| type 결정 시점 | plan 파일의 Vertical Slices 섹션에서 각 slice 별로 결정 |
| 머지 방식 | **rebase fast-forward** — `git rebase <type>/<slug>` + `git branch -D` (merge commit 없음). `git merge` 금지 — merge 커밋이 S라벨·잡음을 협업 히스토리에 누출. |
| `slice/` prefix | 폐기됨 — `<type>/<slug>` 로 전환 (기존 `slice/` 브랜치는 dispatch 가 재사용 가능) |
| push | `finish-plan-dev.sh` 가 develop 있으면 feature branch, 없으면 main 직접 push |

### `dispatch-slice-pane.sh --mode` — dispatch driver 선택

`scripts/dispatch-slice-pane.sh` 의 `--mode` 디폴트는 **`auto`** (env `DISPATCH_DEFAULT_MODE` override). auto 는 `detect-pane-env.sh` 결과로 분기:

| 환경 | auto 결과 |
|---|---|
| TMUX 안 (`$TMUX` set) | tmux pane dispatch |
| cmux 안 (`$CMUX_WORKSPACE_ID` set) | cmux workspace dispatch (부모 workspace 안 grid split — 사용자 화면에 자식 surface 분할 가시화) |
| 둘 다 아님 (default) | die — `--mode=subagent` 명시 권장 |

명시 가능 모드: `subagent`(Agent tool, 토큰 추적 ✓), `tmux`/`pane`, `cmux`, `auto`. `--mode=cmux` 사용 시 사용자가 cmux 화면 분할 + attach 로 작업을 직접 시각화 가능 (단점: 자식 토큰은 부모 token-stats 로 추적 안 됨).

### 직접 호출 (수동)

```bash
pane=$(scripts/tmux-pane.sh launch zsh)
scripts/tmux-pane.sh send "claude" --pane=$pane
scripts/tmux-pane.sh wait-idle --pane=$pane
scripts/tmux-pane.sh send "분석해줘: ..." --pane=$pane
scripts/tmux-pane.sh wait-idle --pane=$pane --idle=5
scripts/tmux-pane.sh capture --pane=$pane
scripts/tmux-pane.sh kill --pane=$pane
```

`tmux-orchestrate` skill 가이드 (`skills/tmux-orchestrate/SKILL.md`) 에 안티패턴 + 호출 시퀀스 정리.

### 자식 pane 라이프사이클

새 `/parallel-consult` / `/sshworld:plan-dev --mode=pane` 작업 시작 시 **이전 자식 pane 자동 정리**:
- 정리 대상: `tmux-pane-mgr` 세션 전체 + 현재 attached window 의 active/self 외 split pane
- 보존: 사용자가 attach 중인 active pane + wrapper 가 도는 self pane
- 우회: `DISPATCH_SKIP_CLEANUP=1`
- 수동 정리: `scripts/tmux-pane.sh cleanup`

### cmux 자식 라이프사이클 (grid split)

cmux 앱 안에서 실행 중일 때 (`CMUX_WORKSPACE_ID` set) `scripts/cmux-pane.sh launch` 는 새 workspace 대신 **부모 workspace 안 grid split** 으로 자식 surface 를 생성합니다.

- 첫 자식: `cmux new-pane --direction right --workspace $CMUX_WORKSPACE_ID` → 부모 우측 분할.
- 이후 자식: 직전 자식 surface 기준으로 라운드로빈 방향 split (count 홀수 → `down`, 짝수 → `right`).
- 각 자식의 surface ref 는 `CBP_STATE_FILE` (기본 `~/.cache/cbp/children-<ws>.json`) 에 누적 기록.
- `cmux-pane.sh kill --pane=surface:N` 으로 개별 surface close + state 제거.
- `cmux-pane.sh reap --pane=surface:N` 으로 완료(✅/❌) 자식 자동 회수 — wait-idle → capture → done 감지 시 자동 close, 미완료면 보존. **완료 마커가 떴어도 자식 input box 에 미제출 사용자 텍스트(`❯ text`)가 남아있으면 `input-pending — kept` 로 회수 보류** — 강제 회수: `CBP_REAP_IGNORE_PENDING=1`. `CBP_REAP_DRY_RUN=1` dry-run 지원 (pending 시 "would keep (input-pending)").
- `cmux-pane.sh reap` (`--pane` 생략) 또는 `cmux-pane.sh reap --all` → state 의 모든 자식을 fast-probe(기본 `--idle=2 --timeout=10`)로 순회, 자식마다 subshell 실행(개별 실패가 루프 전체를 안 죽임). ts 기준 age < `CBP_REAP_ORPHANS_GRACE_SEC`(기본 30) 인 신생 자식은 probe 없이 "grace — kept". 마지막 줄 `reaped N / kept M / pending P` 요약(pending 은 kept 로 흡수되지 않음), exit 0. 부모 감시 루프가 `--pane` 없이 반복 폴링해도 더 이상 exit 2 헛돌지 않음.
- `cmux-pane.sh send/capture/wait-idle --pane=surface:N` → `--surface` flag 자동 dispatch. `workspace:N` ref 는 기존 `--workspace` (회귀 zero).
- `cmux-pane.sh list` → state file 의 자식 surface 우선, 폴백으로 cbp- workspace 목록. cmux tree 와 lazy reconcile (mock 환경 자동 감지).
- `cmux-pane.sh cleanup` → state file 의 surface 일괄 `close-surface` + state 제거 후, 기존 cbp- workspace cleanup 도 실행 (호환).
- `cmux-pane.sh reap-orphans` → `~/.cache/cbp/children-*.json` **전체** 스캔 (cross-workspace). self surface 제외 + alive surface 보존 + dead surface best-effort close-surface + 빈 state file 제거. `CBP_REAP_ORPHANS_DRY_RUN=1` dry-run (close 없이 "would reap" 출력). `CBP_STATE_DIR` 로 스캔 경로 override 가능. `plan-dev-session.sh start` 및 `finish-plan-dev.sh` 가 best-effort 로 자동 호출 — 이전 세션 finish 누락 시에도 다음 plan-dev 시작 시 cross-WS dead orphan 이 자동 정리됨.

`CBP_SPLIT_POLICY` 환경변수로 방향을 `down` / `right` 고정 가능 (unset 시 라운드로빈 고정).

`CMUX_WORKSPACE_ID` unset 환경에서는 기존 new-workspace 흐름 그대로 (회귀 zero).

#### cmux dispatch 진단 가이드 (자식이 진행 안 하는 듯할 때)

`scripts/dispatch-slice-pane.sh --mode=cmux` 는 **launch·자식 기동 검증으로 silent 실패를 방지**한다:
- surface PTY 가 terminal 상태인지 검증(`CBP_LAUNCH_VERIFY_TRIES`, 기본 5회 재시도) — 실패 시 exit 3. 실패 종료 시 (verify-fail die 및 이후 send die 포함) trap 이 best-effort `close-surface` + state 제거를 수행 — 좀비 surface(생성만 되고 state/실surface 로 영구 잔존) 방지.
- 자식 claude TUI 기동 신호 검증(`DISPATCH_VERIFY_TRIES`, 기본 3회 재시도) — 실패 시 exit 비0. 끝내 실패 시 `--mode=subagent` 폴백 권장.
- `CBP_LAUNCH_DEBUG=1` 로 launch 진단 로깅 활성화 — verify 각 시도의 read-screen 출력, 생성 경로(new-pane/new-split), prev_surface 를 stderr 로 dump. 기본(off) 시 동작·출력 완전 불변(추가 read-screen 호출 없음).

spec prompt 송신은 **자동 `--enter-count=2`** 적용 — Claude TUI paste mode 끝의 첫 Enter 가 newline 으로 처리되어 자식이 spec 받고도 명령 실행 안 하던 이슈 해소.

그래도 자식이 멈춰 보이면 진단:

```bash
# 1. surface 살아 있는지
cmux tree | grep surface:<N>

# 2. PTY 활성화 확인 — "Terminal surface not found" 면 detached
cmux read-screen --surface surface:<N> --lines 5

# 3. detached 면 Enter 송신으로 활성화
cmux send-key --surface surface:<N> Enter
cmux send-key --surface surface:<N> Enter

# 4. 활성화 후 read-screen 재시도 — Forming/Undulating/Actioning 이면 정상
cmux read-screen --surface surface:<N> --lines 30
```

부모 회수 패턴:
```bash
# 완료 자동 감지 + 탭 종료 (reap — 권장, 단일 자식)
scripts/cmux-pane.sh reap --pane=surface:<N> --idle=15 --timeout=900
# 부모 감시 루프: --pane 생략(argless) 또는 --all → state 의 모든 자식 fast-probe 일괄 회수
scripts/cmux-pane.sh reap --all
# 수동 회수 (tmux/기타 모드)
scripts/cmux-pane.sh wait-idle --pane=surface:<N> --idle=15 --timeout=900
cmux read-screen --surface surface:<N> --lines 30 | grep -E '^[[:space:]]*(⏺[[:space:]]*)?(✅|❌)'  # ⏺/들여쓰기 prefix 허용
```

사용자 시각 확인: cmux 사이드바의 surface 탭 클릭 → 자식 화면 attach.

### cmux 진행률 push (`plan-dev-progress.sh`)

`plan-dev` 실행 중 cmux 좌측 사이드바 status pill 및 알림 패널에 슬라이스 진행률을 실시간 push.

```bash
# 세션 시작 + status pill 초기화 (총 슬라이스 수 지정)
scripts/plan-dev-progress.sh start --total=3

# 슬라이스 완료 시 카운트 +1 + pill / 알림 갱신
scripts/plan-dev-progress.sh tick --slug=user-signup

# 현재 진행률 표 + 최근 알림 출력
scripts/plan-dev-progress.sh show
```

`plan-dev --mode=cmux` 흐름에서 각 implementor slice 완료 후 자동 호출됨 — 사용자는 cmux 사이드바에서 `✨ 1/3` → `✨ 2/3` → `✨ 3/3` 으로 진행률 추적 가능.

cmux 환경이 아닐 때(tmux/default)는 `tick` 이 진행률 문자열만 stdout 출력하고 notify/set-status 는 no-op.

### 권장 `~/.tmux.conf` 설정 (세션명 표시)

자식 pane 들이 어떤 세션에 속하는지 한눈에 보기 위해 status bar 좌측에 `[#S]` 형태로 세션명 상시 표시:

```bash
# ~/.tmux.conf
set -g status-left "#[fg=cyan,bold][#S] #[default]"
set -g status-left-length 30
set -g mouse on  # 휠 스크롤로 자식 pane scrollback 확인
```

리로드: `tmux source-file ~/.tmux.conf`. 본 wrapper 와는 독립이라 적용 안 해도 동작에는 영향 없음.

---

## 하네스 가드

매 commit / 매 코드 변경 시점에 자동 발동.

### 1) enforce-test-first.sh (PreToolUse: Write|Edit)

production 코드 파일(`src/main/`, `lib/`, `app/`, `internal/`, `pkg/`)을 Write/Edit 하기 직전에 대응 테스트 파일 존재 검사.

```bash
# 기본은 경고만
# strict 모드 (위반 시 차단):
export CLAUDE_TDD_STRICT=1
```

### 2) enforce-doc-sync.sh (PreToolUse: Bash, `git commit`)

매 commit 마다 **DOC 영향 평가를 강제**. 다음 두 가지 중 하나로 명시해야 통과:

```bash
# 영향 없음 (내부 fix·refactor)
DOC_IMPACT=none git commit -m "..."

# 영향 있음 (README/CLAUDE.md 함께 staged)
git add README.md
DOC_IMPACT=updated git commit -m "..."
```

`DOC_IMPACT` 미지정 시 차단. 가드 비활성화: `export DISABLE_DOC_SYNC_HOOK=1`

### 3) limit-child-panes.sh (PreToolUse: Bash)

자식 pane spawn 명령(`tmux-pane.sh launch`, `cmux-pane.sh launch`, `dispatch-slice-pane.sh`) 직전 **tmux pane + cmux child 합산** 수를 검사해 상한 초과 시 차단.

cmux 카운트 우선순위:
1. `CMUX_WORKSPACE_ID` set + state file 존재 → state file 라인 수 (실제 자식 surface 수)
2. 폴백: `cmux list-workspaces` 의 `cbp-` prefix workspace 수

에러 메시지 형식: `tmux pane: X, cmux child: Y, total: Z`

```bash
# 한도 상향
CLAUDE_MAX_CHILD_PANES=10

# hook 영구 비활성
export DISABLE_PANE_LIMIT_HOOK=1
```

### 4) token-stats.sh (Stop)

응답이 끝날 때 직전 turn (마지막 user 메시지 이후 모든 assistant 줄) 의 토큰 사용량과 캐시 히트율을 한 줄로 inline 노출:

```
💰 in=15 cache_c=150 cache_r=1.1k out=60 | cache hit 87%
```

`DISABLE_TOKEN_STATS=1` 로 끄기.

> ℹ️ `statusline-tokens.sh` 는 같은 데이터를 화면 하단 status bar 로 상시 표시하는 **opt-in 대안** — settings.json 의 `statusLine.command` 에 등록하고 `hooks.Stop` 에서 token-stats 제거해서 전환 가능. 기본은 Stop hook 의 inline 메시지.

### 5) enforce-cmux-context.sh (PreToolUse: Bash)

cmux 앱 안에서 실행 중일 때(`CMUX_WORKSPACE_ID` set), 부모 Claude 가 `tmux` / `tmux-cli` / `tmux-pane.sh` 계열 명령을 호출하면 advisory 경고.

- **디폴트: advisory only** (경고만 출력, exit 0 통과). 본 repo 의 `hooks/hooks.json` 및 `.claude/settings.json` 모두 hook command 에 `CMUX_CONTEXT_HOOK_STRICT=1` 을 **inline 으로 강제하지 않는다** — 프로젝트/플러그인 설치 환경 전부 advisory 가 기본.
- 차단(exit 2) 을 원하면 **사용자가 자신의 환경에** `CMUX_CONTEXT_HOOK_STRICT=1` 을 명시적으로 export 해야 한다 (opt-in strict).
- `*/cmux-pane.sh` 는 권장 도구라 매치 대상이 아님 — cmux 환경에서 이 wrapper 를 쓰면 애초에 advisory 도 뜨지 않는다.

```bash
# advisory (기본) — 경고만 출력, 실행은 통과
CMUX_WORKSPACE_ID=ws:1 bash scripts/tmux-pane.sh launch zsh
# stderr: ⚠️  cmux 안에서 tmux 계열 명령 시도 — cmux 환경에선 ${CLAUDE_PLUGIN_ROOT}/scripts/cmux-pane.sh 사용 권장.

# strict 모드 opt-in — 차단
CMUX_CONTEXT_HOOK_STRICT=1 CMUX_WORKSPACE_ID=ws:1 bash scripts/tmux-pane.sh launch zsh
# exit 2

# 1회 우회 (advisory 자체를 억제)
SKIP_CMUX_CONTEXT_HOOK=1 bash scripts/tmux-pane.sh launch zsh

# 영구 비활성화
export DISABLE_CMUX_CONTEXT_HOOK=1
```

#### skip-once marker-file escape (enforce-plan-mode / enforce-cmux-dispatch / enforce-dispatch-gate 공통)

`enforce-cmux-context.sh` 와 달리, plan-dev 게이트 3종(`enforce-plan-mode.sh`, `enforce-cmux-dispatch.sh`, `enforce-dispatch-gate.sh`)은 env 우회 외에 **1회용 marker 파일**로도 escape 가능. 파일이 존재하면 hook 이 검사 시점에 그 파일을 `rm` 하며 통과(자동 1회 소모):

| hook | marker 파일명 |
|---|---|
| `enforce-plan-mode.sh` | `cbp-skip-once-plan-mode` |
| `enforce-cmux-dispatch.sh` | `cbp-skip-once-cmux-dispatch` |
| `enforce-dispatch-gate.sh` | `cbp-skip-once-dispatch-gate` |

경로: git repo 면 `<git-common-dir>/<marker 파일명>`, 비-git cmux 폴백은 `$HOME/.cache/cbp/<marker 파일명>-<sanitized CMUX_WORKSPACE_ID>` (`enforce-cmux-dispatch.sh` 한정, 나머지 두 hook 은 git-common-dir 만 지원).

```bash
touch "$(git rev-parse --git-common-dir 2>/dev/null || echo "$HOME/.cache/cbp")/cbp-skip-once-plan-mode"
```

### 6) track-cmux-edit-burst.sh (PreToolUse: Write|Edit) — **자식 worktree 자동 skip**

cmux 환경에서 Edit/Write 누적 횟수를 카운트해 임계치(기본 50회) 도달 시 `dispatch-slice-pane.sh --mode=cmux` 사용을 안내하는 advisory 출력. 5분 idle 시 자동 리셋. `dispatch-slice-pane.sh` launch 시 명시 리셋.

```bash
CMUX_EDIT_BURST_STRICT=1       # 차단 모드 (exit 2, 디폴트 unset)
CMUX_EDIT_BURST_THRESHOLD=N    # 임계치 조정 (디폴트 50)
SKIP_CMUX_EDIT_BURST=1         # 1회 우회
DISABLE_CMUX_EDIT_BURST_HOOK=1 # 영구 비활성화
```

- **본 repo 의 settings.json**: inline `CMUX_EDIT_BURST_STRICT=1` 은 제거됨 → 디폴트 **advisory only** (임계치 50). 51번째부터 stderr 메시지만, 차단 X. 강제 차단 원하면 사용자 환경에 `export CMUX_EDIT_BURST_STRICT=1` 명시.

### 7) cmux-dispatch-hint.sh (SessionStart)

cmux 환경(`CMUX_WORKSPACE_ID` set) 세션 시작 시 **dispatch-first advisory** 를 stdout(additionalContext)으로 inject — "cmux 환경에선 plan-dev Slice 가 **dispatch(cmux) 기본**, direct-edit 는 dispatch 자체가 불가한 환경 등 진짜 예외만". 비-cmux 환경은 무출력(exit 0). **하드 차단 아님** — advisory nudge. 자기수정(plan-dev 자신의 hook·문서 편집)도 cmux 환경에서는 dispatch 기본.

> cmux workspace 에서 plan-dev 가 자꾸 direct-edit 로 가던 문제(글로벌 정책이 direct-edit 기본이었음)를 바로잡기 위해, cmux 환경 한정으로 dispatch 를 기본으로 reframe. 비-cmux 환경은 영향 없음.

### 8) SessionStart inline

세션 시작 시 git worktree 목록 + 미커밋 변경 + **멀티플렉서 환경 1줄** 자동 출력.

```
=== 멀티플렉서: cmux (driver: scripts/cmux-pane.sh) ===
```

`default` 환경(tmux/cmux 없음)이면 `(driver: subagent 모드 사용)` 으로 표시.

### 9) enforce-plan-mode.sh (PreToolUse: Write|Edit) — **plan mode 진입 강제**

`/sshworld:plan-dev` 는 plan mode 진입(EnterPlanMode → plan 파일 작성 → ExitPlanMode 승인)이 필수다. 콘텐츠 가이드만으로는 모델이 `plan-dev-session.sh start` 만 돌리고 plan mode 를 건너뛴 채 바로 Edit/Write 로 직행할 수 있어, 이를 하네스로 차단한다.

- plan-dev 세션 마커(`<git-common-dir>/plan-dev-session.json`)가 **없으면 no-op** — 비-plan-dev 세션은 전혀 영향 없음.
- "plan mode 거침" 판정 = **marker 의 `start_ts` 이후 작성된 plan 파일(`~/.claude/plans/*.md`)이 존재** (plan mode 진입 = plan 파일 작성). 존재 → 통과.
  - `permission_mode==plan`(plan mode 중) / `==bypassPermissions`(dispatch 자식·명시 우회) → 통과.
  - 자식 worktree(git-dir≠git-common-dir) → skip.
  - start_ts 파싱 불가 → conservative 통과.
  - 그 외(마커 활성 + plan mode 미진입) → **exit 2 차단**.
- ⚠️ marker **파일 mtime** 이 아니라 **`start_ts` JSON 필드** 기준 — `plan-dev-progress.sh` 가 marker 를 재기록하며 mtime 을 bump 해서, mtime 기준이면 progress start 직후 매번 false-positive 차단됨. start_ts 는 progress 가 보존하므로 안정.
- **한계**: plan 을 reject 해도 plan 파일은 남아 통과. 목적은 "plan mode 아예 미진입" catch 이지 "plan reject 후 강행" 방지가 아님.
- (구 버그: `permission_mode==plan` 시 flag 를 찍는 방식이었으나 plan 파일 write 가 PreToolUse Write 경로를 안 타 flag 미기록 → 승인 후 모든 Edit 를 false-positive 차단. start_ts 신호로 교체 수정.)

```bash
SKIP_PLAN_MODE_ENFORCE=1        # 1회 우회
DISABLE_PLAN_MODE_ENFORCE_HOOK=1 # 영구 비활성화
```

### 10) enforce-cmux-dispatch.sh (PreToolUse: ExitPlanMode) — **cmux plan direct-edit 차단**

cmux 환경(`CMUX_WORKSPACE_ID` set)에서 plan 의 Slice File Map Mode 컬럼에 `direct-edit` 표셀이 있으면 **ExitPlanMode 차단**. cmux 기본은 `dispatch(cmux)` — 반사적 direct-edit 를 plan mode 게이트에서 잡음.

- `CMUX_WORKSPACE_ID` 미set → no-op (비-cmux 환경, direct-edit 기본 유지).
- plan 본문에서 파이프 표셀(`|..direct-edit..|`) 탐지 — 산문 오탐 없음.
- cmux 에서 direct-edit 가 정말 필요하면(dispatch 자체가 불가한 환경 등 진짜 예외) out-of-band escape: `CMUX_DIRECT_EDIT_OK=1`. "정책/하네스/문서 파일이라서" 는 escape 정당 사유 아님 — 자기수정도 dispatch 기본.

```bash
CMUX_DIRECT_EDIT_OK=1              # 의식적 escape — ExitPlanMode 게이트 1회 통과
SKIP_CMUX_DISPATCH_GATE=1          # 1회 우회
DISABLE_CMUX_DISPATCH_GATE_HOOK=1  # 영구 비활성
```

### 11) enforce-dispatch-gate.sh (PreToolUse: Bash) — **dispatch 승인 게이트**

`dispatch-slice-pane.sh` 는 Bash 도구라 `enforce-plan-mode`(Write/Edit 전용) 를 타지 않는다. plan mode 미진입 상태에서 dispatch 가 실행되는 갭을 막는 가드.

- **enforce-dispatch-gate.sh**: command 가 `dispatch-slice-pane.sh` **그리고** `--slice` 를 둘 다 포함(=실제 dispatch)할 때만 검사. plan-dev 세션 활성 + plan mode 미진입(marker `start_ts` 이후 작성된 plan 파일 없음)이면 exit 2 차단. plan 작성됨 / `permission_mode==plan|bypassPermissions` / 자식 worktree → 통과.
  - plan-dev 세션 marker 없음 → no-op (비-plan-dev 세션 무관).
  - 파싱 실패 → conservative exit 0 (비차단).
  - 우회: `SKIP_DISPATCH_GATE=1`(1회) / `DISABLE_DISPATCH_GATE_HOOK=1`(영구).

```bash
SKIP_DISPATCH_GATE=1           # 1회 우회
DISABLE_DISPATCH_GATE_HOOK=1   # 영구 비활성
```

### 12) record-commit-advised.sh (PostToolUse: Task|Agent) — **commit-advised marker 자동 기록**

Phase 4 의 `commit-advisor` agent 호출을 hook 이 직접 감지해 `plan-dev-commit-advised` marker 를 자동 touch — `finish-plan-dev.sh` push 게이트가 advisor agent 본인의 touch 이행에 의존하던 구조적 취약점(LLM 이 지시를 빼먹으면 게이트가 오차단) 을 보강한다.

- `tool_name` 이 `Task` 또는 `Agent` **그리고** `tool_input.subagent_type` 에 `commit-advisor` substring 포함 시(플러그인 네임스페이스 `sshworld:commit-advisor` 대응) marker touch.
- jq 미사용 — grep/sed 로 파싱.
- 비-git cwd / 빈·깨진 stdin 등 모든 실패 경로에서 조용히 exit 0 — 세션을 절대 막지 않음.
- `agents/commit-advisor.md` 의 agent 본인 touch 는 이제 belt(best-effort) — hook 이 primary.

### 13) notify-slice-done.sh (Stop, 자식 worktree 전용) — **완료 알림 + reap fast-path 신호**

cmux dispatch 자식이 작업을 마치면 부모 사이드바에 cmux 알림 패널을 즉시 push 하고, 부모의 `cmux-pane.sh reap` 이 `wait-idle` 을 건너뛰고 바로 회수하도록 done-marker 파일을 남긴다 — 감시 루프의 `sleep 30` 대기 없이 완료를 즉시 인지.

- 우회: `SKIP_SLICE_DONE_NOTIFY=1`(1회) / `DISABLE_SLICE_DONE_NOTIFY=1`(영구).

### 14) reap-on-stop.sh (Stop, 부모 세션 전용) — **완료 자식 자동 회수**

자식이 완료(notify-slice-done 이 남긴 done-marker)되면, 부모가 별도 감시 루프 없이도 **다음 turn 경계마다** 최대 5개까지 해당 surface 를 자동 reap 한다. 회수됐으면 `♻️ reap-on-stop: reaped <ref>`, 자식 input box 에 미제출 텍스트가 남아있으면 `⏸ input-pending — <ref> 보류` 로 한 줄 알려준다.

- 우회: `SKIP_REAP_ON_STOP=1`(1회) / `DISABLE_REAP_ON_STOP=1`(영구).

---

## 환경변수 정리

| 변수 | 기본 | 효과 |
|---|---|---|
| `CLAUDE_TDD_STRICT=1` | off | TDD 위반 시 Write/Edit 차단 |
| `DOC_IMPACT=none|updated` | (미지정 시 차단) | commit 시 DOC 영향 명시 |
| `SKIP_DOC_SYNC=1` | off | doc-sync hook 1회 우회 |
| `DISABLE_DOC_SYNC_HOOK=1` | off | doc-sync hook 영구 비활성화 |
| `DISABLE_TOKEN_STATS=1` | off | token-stats hook 비활성화 |
| `CLAUDE_MAX_CHILD_PANES=N` | 99 | 자식 tmux+cmux pane 합산 상한 (limit-child-panes hook, 사실상 무제한) |
| `DISABLE_PANE_LIMIT_HOOK=1` | off | limit-child-panes hook 비활성화 |
| `FORCE_SELF_KILL=1` | off | tmux-pane.sh kill 의 자기 pane 거부 우회 |
| `TMUX_PANE_NO_LAYOUT=1` | off | tmux-pane.sh launch 의 main-vertical layout 자동 적용 끄기 |
| `DISPATCH_DEFAULT_MODEL=<alias>` | sonnet | dispatch-slice-pane.sh 의 자식 model 디폴트 (--model arg 가 우선) |
| `DISPATCH_DEFAULT_TYPE=<type>` | feat | dispatch-slice-pane.sh 의 --type 미지정 시 기본 type |
| `DISPATCH_DEFAULT_MODE=<mode>` | auto | dispatch-slice-pane.sh 의 --mode 미지정 시 기본 driver (auto/tmux/cmux/pane/subagent). 기존 동작 복원: `pane` |
| `DISPATCH_SKIP_CLEANUP=1` | off | dispatch-slice-pane.sh 가 main 진입 시 자식 pane 자동 정리 끄기 |
| `DISPATCH_VERIFY=0` | 1 (on) | dispatch-slice-pane.sh cmux 자식 claude TUI 기동 검증. `0` 이면 스킵 (기존 동작 보존). |
| `DISPATCH_VERIFY_TRIES=<n>` | 3 | dispatch-slice-pane.sh TUI 기동 검증 최대 재시도 횟수. |
| `DISPATCH_PERMISSION_MODE=<mode>` | `bypassPermissions` | dispatch-slice-pane.sh 가 자식 claude 에 `--permission-mode <mode>` flag 전달. `default` 시 flag 생략. `DISPATCH_CHILD_CMD` set 시 무시. |
| `SKIP_PLAN_DEV_FINISH=1` | off | Phase 5 (finish-plan-dev.sh) 1회 우회 |
| `SKIP_PLAN_DEV_CMUX_CLEANUP=1` | off | finish-plan-dev.sh push 후 cmux 자식 surface cleanup 1회 우회. |
| `DISABLE_PLAN_DEV_CMUX_CLEANUP=1` | off | cmux cleanup 영구 비활성. |
| `SKIP_CMUX_REAP=1` | off | `plan-dev-session.sh start` 및 `finish-plan-dev.sh` 의 reap-orphans best-effort 호출 skip. |
| `CBP_REAP_IGNORE_PENDING=1` | off | `cmux-pane.sh reap` 이 완료 마커는 떴지만 자식 input box 에 미제출 사용자 텍스트가 남은 pane 을 `input-pending — kept` 로 보존하는 기본 동작을 우회 — pending 무시하고 강제 회수(reaped). |
| `CBP_REAP_ORPHANS_DRY_RUN=1` | off | `cmux-pane.sh reap-orphans` dry-run — close 없이 "would reap" 출력만 (state file 변경 없음). 실제 회수 전 미리보기용. |
| `CBP_STATE_DIR=<path>` | `~/.cache/cbp` | `cmux-pane.sh reap-orphans` 가 스캔하는 state file 디렉토리 override (테스트 mock). |
| `SKIP_COMMIT_ADVISOR_GATE=1` | off | finish-plan-dev.sh push 직전 commit-advisor 게이트 1회 우회. |
| `DISABLE_COMMIT_ADVISOR_GATE=1` | off | finish-plan-dev.sh commit-advisor 게이트 영구 비활성화. |
| `SKIP_PLAN_MODE_ENFORCE=1` | off | enforce-plan-mode.sh (PreToolUse) 1회 우회 — plan mode 미진입 차단 bypass |
| `DISABLE_PLAN_MODE_ENFORCE_HOOK=1` | off | enforce-plan-mode.sh 영구 비활성화 |
| `PLAN_MODE_SESSION_FILE=<path>` | auto | enforce-plan-mode.sh 마커 경로 override (테스트 mock) |
| `PLAN_MODE_PLANS_DIR=<path>` | `$HOME/.claude/plans` | enforce-plan-mode.sh 의 plan 파일 디렉토리 override (테스트 mock) |
| `SKIP_DISPATCH_GATE=1` | off | enforce-dispatch-gate.sh 1회 우회 — dispatch 승인 게이트 bypass |
| `DISABLE_DISPATCH_GATE_HOOK=1` | off | enforce-dispatch-gate.sh 영구 비활성화 |
| `DISPATCH_GATE_SESSION_FILE=<path>` | auto | enforce-dispatch-gate.sh 의 세션 marker 경로 override (테스트 mock). `PLAN_MODE_PLANS_DIR` 도 dispatch 게이트의 plan 파일 탐색에 사용됨. |
| `DISABLE_PLAN_DEV_FINISH=1` | off | Phase 5 영구 비활성화 |
| `FINISH_AUTO_PUSH_WITHOUT_MARKER=1` | off | marker 없을 때 silent skip 대신 현재 HEAD branch 로 `git push -u origin` 자동 시도 |
| `GIT_PUSH_CMD=<cmd>` | `git push` | finish-plan-dev.sh 의 push 명령 override (테스트용) |
| `PLAN_DEV_SESSION_BIN=<path>` | `scripts/plan-dev-session.sh` | 세션 헬퍼 경로 override (`finish-plan-dev.sh` / `plan-dev-progress.sh` 공용, 테스트용) |
| `CMUX_PANE_BIN=<path>` | `scripts/cmux-pane.sh` | `plan-dev-progress.sh` 가 cmux push 에 사용할 wrapper 경로 override (테스트용) |
| `PROGRESS_DRY_RUN=1` | off | `plan-dev-progress.sh` 의 notify/set-status 단계 dry-run (`cmux-pane.sh` 가 처리) |
| `CMUX_BIN=<path>` | `cmux` | cmux-pane.sh / detect-pane-env.sh 가 사용할 cmux 바이너리 경로 (테스트 mock 에 사용) |
| `CBP_STATE_FILE=<path>` | `~/.cache/cbp/children-<ws>.json` | cmux-pane.sh state file 경로 override (ws sanitize 규칙: `${CMUX_WORKSPACE_ID//[:\/]/_}`) |
| `CBP_WORKSPACE_PREFIX=<str>` | `cbp-` | cmux-pane.sh launch 의 workspace 이름 prefix |
| `CBP_LIST_LINES=<str>` | unset | cmux-pane.sh list/cleanup/status 의 list-workspaces 입력 mock (테스트용) |
| `CLAUDE_FAKE_SELF_CMUX_WS=<ref>` | unset | cmux-pane.sh kill/cleanup 의 자기 workspace ref mock (테스트용) |
| `CBP_SPLIT_POLICY=<dir>` | unset (라운드로빈) | cmux-pane.sh grid split 방향 고정 (`down` 또는 `right`). unset 시 라운드로빈 (홀수→down, 짝수→right) |
| `CBP_LAUNCH_VERIFY_TRIES=<n>` | 5 | cmux-pane.sh launch 후 PTY terminal 검증 루프 최대 시도 횟수. 끝내 실패 시 die(exit 3). `CBP_DISABLE_WARMUP=1` 시 스킵. |
| `CBP_LAUNCH_DEBUG=1` | off | cmux-pane.sh launch 진단 로깅 — 생성 경로(new-pane/new-split raw_out), prev_surface, verify 루프 각 시도의 read-screen 출력을 stderr 로 dump. off 시 동작·출력 완전 불변. |
| `CMUX_CONTEXT_HOOK_STRICT=1` | off | enforce-cmux-context.sh strict 모드 — cmux 안 tmux 계열 명령 차단(exit 2) |
| `SKIP_CMUX_CONTEXT_HOOK=1` | off | enforce-cmux-context.sh 1회 우회 (advisory 억제) |
| `DISABLE_CMUX_CONTEXT_HOOK=1` | off | enforce-cmux-context.sh 영구 비활성화 |

---

## Permissions (settings.json)

기본 allow:
- `git status`, `diff`, `log`, `branch`, `checkout`, `switch`, `fetch`, `pull`, `add`, `commit`, `stash`, `merge`, `rebase`, `remote`, `tag`, `worktree`, `restore`
- `BUILD_CMD` / `TEST_CMD` / `RUN_CMD` TODO 자리 (사용자가 프로젝트 빌드 명령으로 치환)
- tmux 좁힌 패턴: `tmux new-window*`, `tmux send-keys*`, `tmux capture-pane*`, `tmux display-message*`, `tmux list-panes*`, `tmux kill-pane*`, `tmux-cli*`
- cmux 관리: `cmux new-workspace*`, `cmux new-pane*`, `cmux new-split*`, `cmux rename-tab*`, `cmux workspace-action*`, `cmux send *`, `cmux send-key*`, `cmux read-screen*`, `cmux capture-pane*`, `cmux list-workspaces*`, `cmux list-panes*`, `cmux list-pane-surfaces*`, `cmux close-surface*`, `cmux close-workspace*`, `cmux tree*`, `cmux ping*`, `cmux identify*`
- cmux 사이드바 UX: `cmux notify*`, `cmux set-status*`, `cmux set-progress*`, `cmux clear-status*`, `cmux clear-progress*` (plan-dev 진행률 push 용)
- scripts: `*/scripts/tmux-pane.sh*`, `*/scripts/cmux-pane.sh*`, `*/scripts/detect-pane-env.sh*`, `*/scripts/dispatch-slice-pane.sh*`, `*/scripts/finish-plan-dev.sh*`, `*/scripts/plan-dev-progress.sh*`

기본 deny:
- `rm -rf*`, `git push --force*`, `git push -f*`, `git commit --no-verify*`, `git reset --hard*`, `tmux kill-server*`

---

## 릴리즈 / 버전

- 릴리즈 노트는 [GitHub Releases](https://github.com/sshworld/sshworld-best-practice/releases) 에서 확인.
- 태그 컨벤션 `sshworld--vX.Y.Z`.
- 업데이트: `/plugin update sshworld`.
- (개발자용) 릴리즈는 `scripts/release.sh` 로 발행 — 상세는 CLAUDE.md "릴리즈 & 버저닝 규칙".

---

## 베이스 출처

- GitHub: [shanraisshan/claude-code-best-practice](https://github.com/shanraisshan/claude-code-best-practice)
- 핵심 인용: Boris Cherny (Claude Code), Thariq (세션 관리), Dex Horthy (context % 가이드)

---

## 로드맵

- [ ] Claude Code 플러그인 형태로 패키징
- [ ] BUILD/TEST/RUN 명령 자동 감지 (gradle/npm/pytest 등)
- [ ] reviewer 룰 확장
- [ ] 다른 IDE/터미널 연동 가이드
