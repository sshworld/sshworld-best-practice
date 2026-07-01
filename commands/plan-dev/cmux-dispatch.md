# cmux dispatch 가이드 (Phase 2 상세)

`commands/plan-dev.md` 의 Phase 2 모드 선택 + 환경별 Mode 룰 + Phase 3 worktree 머지 + Phase 6 종료 전 bash 예시.

---

## 환경별 기본 Mode 룰 (1-3 Phase Review 맥락)

> 🚀 **환경별 기본 Mode 룰**:
> - **cmux 환경(`CMUX_WORKSPACE_ID` set)**: **dispatch(cmux) 만** — plan Slice File Map 에 `direct-edit` 표셀 넣으면 `enforce-cmux-dispatch` hook 이 **ExitPlanMode 차단**. 각 슬라이스는 `${CLAUDE_PLUGIN_ROOT}/scripts/dispatch-slice-pane.sh --mode=cmux` 로 자식 surface 에 띄워 작업 (사용자가 cmux 사이드바에서 진행 시각화). SessionStart 의 `cmux-dispatch-hint` advisory 가 이를 상기시킴.
>   - cmux 에서 `direct-edit` 가 정말 필요하면 **plan 콘텐츠가 아니라 out-of-band env**: `CMUX_DIRECT_EDIT_OK=1` 로 ExitPlanMode 게이트를 의식적으로 1회 통과. "정책/문서/하네스 파일이라서 direct-edit" 라는 일반화는 잘못됨 — 자기수정도 dispatch 기본. escape 는 dispatch 자체가 불가한 환경 등 진짜 예외만.
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

**cmux dispatch (cmux 환경 기본)**: cmux 환경에서는 슬라이스 기본 mode. `--mode=cmux` 면 부모 workspace 안에 자식 surface 가 grid 분할되어 사용자가 화면에서 직접 진행 확인. 자식 토큰은 부모 token-stats 로 추적 안 됨 (trade-off — 비-cmux 면 subagent mode 가 토큰 추적). cmux 에서 direct-edit 가 정말 필요하면 plan Mode 컬럼이 아니라 `CMUX_DIRECT_EDIT_OK=1` escape — "이 파일은 정책/문서라서 direct-edit" 라는 일반화는 잘못됨. **자기수정(plan-dev 자신의 hook·문서 편집)도 cmux 환경에서는 dispatch(cmux) 기본**. 진짜 예외(dispatch 자체가 불가한 환경)일 때만 escape 사용.

#### cmux dispatch 동작 모델 (진단 가이드)

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
- 부모가 회수: `${CLAUDE_PLUGIN_ROOT}/scripts/cmux-pane.sh reap --pane=surface:<N>` — 완료 감지 시 자동 탭 종료, 미완료면 보존. (내부적으로 wait-idle → capture → grep ✅/❌ → close-surface 흐름. finish-plan-dev 의 bulk cleanup 은 backstop 으로 남음.) reap 가 `died`(exit 5) 반환 시 = 자식 비정상 종료 → 재dispatch 또는 subagent 폴백.
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

#### cross-WS dead orphan 자동 정리 (reap-orphans)

`cmux-pane.sh reap-orphans` 는 **현재 workspace 뿐 아니라 모든 workspace** 의 잔존 dead surface 를 회수한다. 이전 plan-dev 세션이 `finish-plan-dev.sh` 없이 종료됐거나 crash 로 cleanup 을 못 한 경우에도 다음 plan-dev 시작 시 자동으로 dead orphan 을 정리한다.

- `plan-dev-session.sh start` (Phase 0 시작) 및 `finish-plan-dev.sh` (Phase 5 완료 후 backstop) 가 best-effort 로 자동 호출.
- 살아있는 타 세션 자식 surface 는 **보호** (alive 판정 = `cmux read-screen` rc0). self surface 는 항상 skip.
- 수동 실행 (미리보기 포함):
  ```bash
  # 미리보기 (실제 close 없음)
  CBP_REAP_ORPHANS_DRY_RUN=1 ${CLAUDE_PLUGIN_ROOT}/scripts/cmux-pane.sh reap-orphans
  # 실제 회수
  ${CLAUDE_PLUGIN_ROOT}/scripts/cmux-pane.sh reap-orphans
  ```
- 우회: `SKIP_CMUX_REAP=1` (plan-dev 자동 호출 skip). `CBP_STATE_DIR` 로 스캔 디렉토리 override.

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

> ❌ `git merge <type>/<slug>` **절대 금지** — merge 커밋이 `S1`/`merge:` 잡음을 협업 히스토리에 영구 노출. 항상 rebase fast-forward 만 사용.

### 병렬 슬라이스 순차 통합 시 주의사항

병렬 dispatch 슬라이스를 순차 통합할 때: worktree 가 **점유 중인 브랜치는 `git rebase` 불가** (`fatal: 'branch' is already used by worktree`). 올바른 순서:

**(1) worktree 먼저 `git worktree remove --force` → (2) `git rebase` → (3) `git merge --ff-only`**

cleanup(`git branch -D` / `worktree remove`)은 **머지 성공 확인 후**. `rebase && ... && branch -D` 를 한 배치 `&&` 체인으로 묶지 말 것 — 중간 rebase 실패 시 뒤 cleanup 이 **미머지 브랜치를 삭제**(dangling 커밋 → cherry-pick 복구 필요).

```bash
# 올바른 순차 통합 패턴 (슬라이스 A → B 순서 예)
# 1. worktree 먼저 제거 (브랜치 점유 해제)
git worktree remove --force .worktrees/<slug-a>
# 2. rebase (점유 해제 후에만 가능)
git rebase feat/<slug-a>
# 3. 머지 성공 확인 후 브랜치 삭제
git branch -D feat/<slug-a>

# 다음 슬라이스도 동일 패턴 반복
git worktree remove --force .worktrees/<slug-b>
git rebase feat/<slug-b>
git branch -D feat/<slug-b>
```

### disjoint 슬라이스는 cherry-pick 권장

슬라이스들이 **서로 다른 파일 영역**을 건드리면(파일 교집합 없음 = disjoint), 위 rebase dance 대신 **`git cherry-pick` 이 더 안전하고 간단**하다. worktree 점유 해제나 main HEAD 이동 걱정이 없고 충돌 위험도 없다:

```bash
# disjoint 슬라이스 통합 (파일 영역 안 겹칠 때) — main 에서 바로
git cherry-pick feat/<slug-a>       # 해당 커밋만 main 에 얹기
git cherry-pick feat/<slug-b>
# 확인 후 정리
git worktree remove --force .worktrees/<slug-a> && git branch -D feat/<slug-a>
git worktree remove --force .worktrees/<slug-b> && git branch -D feat/<slug-b>
```

rebase(fast-forward)는 슬라이스가 **같은 파일 영역**을 건드려 순서가 중요할 때만 사용한다. 판단 기준 = Slice File Map 의 Files 교집합 여부.

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
