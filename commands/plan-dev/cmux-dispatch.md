# cmux dispatch 가이드 (Phase 2 상세)

`commands/plan-dev.md` 의 Phase 2 모드 선택 + 환경별 Mode 룰 + Phase 3 worktree 머지 + Phase 6 종료 전 bash 예시.

---

## 환경별 기본 Mode 룰 (1-3 Phase Review 맥락)

> 🚀 **환경별 기본 Mode 룰**:
> - **cmux 환경(`CMUX_WORKSPACE_ID` set)**: **dispatch(cmux) 만** — plan Slice File Map 에 `direct-edit` 표셀 넣으면 `enforce-cmux-dispatch` hook 이 **ExitPlanMode 차단**. 각 슬라이스는 `${CLAUDE_PLUGIN_ROOT}/scripts/dispatch-slice-pane.sh --mode=cmux` 로 자식 surface 에 띄워 작업 (사용자가 cmux 사이드바에서 진행 시각화). SessionStart 의 `cmux-dispatch-hint` advisory 가 이를 상기시킴.
>   - cmux 에서 `direct-edit` 가 정말 필요하면 **plan 콘텐츠가 아니라 out-of-band env**: `CMUX_DIRECT_EDIT_OK=1` 로 ExitPlanMode 게이트를 의식적으로 1회 통과.
> - **비-cmux 환경**: `direct-edit` 가 기본, dispatch 가 opt-in (시각화/격리 가치 시).
>
> cmux dispatch 경로(`${CLAUDE_PLUGIN_ROOT}/scripts/dispatch-slice-pane.sh --mode=cmux`)는 항상 보존.
>
> 본 repo 의 settings.json 의 cmux Edit/Write 누적 hook(`track-cmux-edit-burst`)은 **advisory only** (디폴트 임계치 50) — 차단 없음. `CMUX_EDIT_BURST_STRICT=1` env 명시 시만 차단.

---

### Phase 2 모드 선택

> ⚠️ `dispatch-slice-pane.sh` 의 `--mode` 디폴트는 **`auto`** (env `DISPATCH_DEFAULT_MODE` override). auto = `detect-pane-env.sh` 결과로 분기 — TMUX 안 → tmux, cmux 안 → cmux, default 환경 → die (사용자가 `--mode=subagent` 명시).

| 모드 | 효과 |
|---|---|
| `--mode=auto` (기본) | 환경 자동 감지 |
| `--mode=subagent` | Agent(implementor) — 부모 token-stats 추적 ✓, cmux 화면 분할 ✗ |
| `--mode=pane` / `--mode=tmux` | tmux pane dispatch |
| `--mode=cmux` | cmux workspace dispatch (부모 workspace 안 grid split — 사용자가 attach/시각화) |
| `Workflow` 툴 (mode=workflow) | dispatch-slice-pane **미경유** — 부모가 `Workflow` 툴로 `pipeline(slices,...)` fan-out. 비시각·대규모·자동 verify. opt-in. `/workflows` 트리로 관찰. ➜ "Workflow 통합" 섹션 참조 |

**cmux dispatch (cmux 환경 기본)**: cmux 환경에서는 슬라이스 기본 mode. `--mode=cmux` 면 부모 workspace 안에 자식 surface 가 grid 분할되어 사용자가 화면에서 직접 진행 확인. 자식 토큰은 부모 token-stats 로 추적 안 됨 (trade-off — 비-cmux 면 subagent mode 가 토큰 추적). cmux 환경에서 direct-edit 가 필요하면 plan Mode 컬럼이 아니라 `CMUX_DIRECT_EDIT_OK=1` escape.

#### cmux dispatch 동작 모델 (진단 가이드)

- `dispatch-slice-pane.sh --mode=cmux` 호출 → `${CLAUDE_PLUGIN_ROOT}/scripts/cmux-pane.sh launch` 가 cmux new-split 으로 surface 생성 + zsh + 자식 `claude --permission-mode bypassPermissions` 실행 + spec prompt 송신.
- spec prompt 송신은 자동으로 **`--enter-count=2`** 적용 (Claude TUI paste mode 끝의 첫 Enter 는 newline 으로 처리되어 명령 실행 안 됨 — 추가 Enter 필요). 단, **cmux 신규 surface 가 PTY detached 인 케이스** 에서는 첫 Enter 만으로 PTY 가 활성화되고 명령 실행이 안 될 수 있음.
- 진단 시퀀스 (자식이 진행 안 하는 듯할 때):
  1. `cmux tree | grep surface:<N>` — surface 살아 있는지.
  2. `cmux read-screen --surface surface:<N>` — `Terminal surface not found` 이면 detached. `cmux send-key --surface surface:<N> Enter` 1~2회로 활성화.
  3. 활성화 후 자식이 spec prompt 받은 상태 (`✳ Forming…` / `Undulating…` 등 thinking) 이면 정상.
- 부모가 회수: `${CLAUDE_PLUGIN_ROOT}/scripts/cmux-pane.sh reap --pane=surface:<N>` — 완료 감지 시 자동 탭 종료, 미완료면 보존. (내부적으로 wait-idle → capture → grep ✅/❌ → close-surface 흐름. finish-plan-dev 의 bulk cleanup 은 backstop 으로 남음.)
- 사용자가 직접 자식 화면 보기: cmux 사이드바의 surface 탭 클릭.
- **자식 worktree trust 자동 시딩** (`trust-dir.sh`, cross-machine): dispatch 는 worktree launch 직전 `hasTrustDialogAccepted` 를 자동 set — fresh 머신에서 trust 다이얼로그에 막혀 자식이 멈추는 케이스 회피. 우회: `SKIP_DISPATCH_TRUST=1`.

#### Dispatch wrapper 가용성 검증 (회복력 룰)

- (a) wrapper PWD-relative path (`${CLAUDE_PLUGIN_ROOT}/scripts/dispatch-slice-pane.sh`) 가 안 보이면 → **알려진 절대경로** (`~/scripts/dispatch-slice-pane.sh` 글로벌 설치 결과, 또는 SessionStart system-reminder 가 노출한 driver 경로) 로 직접 호출 시도. 검색 결과 부재 ≠ 실행 불가.
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
${CLAUDE_PLUGIN_ROOT}/scripts/dispatch-slice-pane.sh \
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
# cmux 모드: reap 이 wait-idle → capture → done 감지 → 자동 탭 종료 (미완료면 보존)
$wrapper reap --pane=$pane --idle=10 --timeout=1800
# tmux/기타 모드: 수동 회수
$wrapper wait-idle --pane=$pane --idle=10 --timeout=1800
$wrapper capture   --pane=$pane | tail -50 | grep -E '^[[:space:]]*(⏺[[:space:]]*)?(✅|❌)'
```

슬라이스 ✅ 확인 후:
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/plan-dev-progress.sh tick --slug=<slice>
```

---

## Phase 3 — worktree 머지 방법

**worktree 머지 방법 (rebase fast-forward, merge commit 없음):**
```bash
git rebase <type>/<slug>     # 각 완료 슬라이스마다
git branch -D <type>/<slug>  # 슬라이스 브랜치 삭제
git worktree remove .worktrees/<slug>
```
충돌 발생 시: 즉시 `git rebase --abort` → 충돌 파일 목록 사용자 보고.

---

## Phase 6 — 종료 직전 bash 예시

**종료 직전** 진행률 최종 확인:
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/plan-dev-progress.sh show
```

**종료 직전** unlocked `worktree-agent-*` 자동 cleanup:
```bash
git worktree list --porcelain
# locked 없는 worktree-agent-<hash> 만 → git worktree remove --force + git branch -D
# locked worktree 는 건드리지 않음
```
