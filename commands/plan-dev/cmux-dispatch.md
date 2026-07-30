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

#### cmux dispatch 동작 모델

`dispatch-slice-pane.sh --mode=cmux` 호출 → cmux new-split 으로 surface 생성 + 자식 `claude --permission-mode bypassPermissions` 실행 + spec prompt 송신 (자동 `--enter-count=2`, launch 자동 검증으로 silent dead surface 방지). 사용자가 직접 자식 화면 보기: cmux 사이드바의 surface 탭 클릭.

> 📎 launch 검증 단계 / 진단 시퀀스 / trust 자동 시딩 / notify-slice-done 내부 / 자동 회수 체인 / dispatch wrapper 가용성 검증 룰: [dispatch 진단 가이드](./troubleshooting-dispatch.md)

⚠️ **Phase 5 `do_cmux_cleanup`(finish-plan-dev.sh push 후 자동 호출)은 pending 을 무시하고 닫는 destructive backstop** — input-pending 상태와 무관하게 자식 surface 를 일괄 close 한다. reap 표준 감시 루프로 pending 을 먼저 사용자에게 보고/처리한 뒤 Phase 5 로 넘어갈 것.

**reap 계약** (`${CLAUDE_PLUGIN_ROOT}/scripts/cmux-pane.sh reap --pane=surface:<N>`):

| 자식 상태 | input-pending 無 | input-pending 有 |
|---|---|---|
| done-marker 有 | 회수 | 회수 + `(pending-input 무시: <텍스트>)` 부기 (marker trumps pending, 디폴트 on) |
| ✅/❌ 화면 감지 (marker 無) | 회수 | `input-pending — kept` 보존 |
| not done | `not done — kept` 보존 | 보존 |
| died (exit 5) | 재dispatch 또는 subagent 폴백 | 동일 |

강제 회수: `CBP_REAP_IGNORE_PENDING=1`. 요약 줄: `reaped N / kept M / pending P`.

#### 애드혹 dispatch (Slice File Map 밖 편집)

plan 승인 후 원래 Slice 에 없던 편집 요청도 direct-edit 대신 위와 동일한 `dispatch-slice-pane.sh` 흐름으로 짧은 인라인 spec dispatch — 상세는 `commands/plan-dev.md` 의 "Phase 2 — 애드혹 편집" 참조.

#### Spec 파일 위치 (컨벤션)

- **위치/명명**: `.claude/specs/<slug>.spec.md` (slug = `--slice=<slug>` 와 동일 kebab-case, `<slug>.spec.md` 접미사).
- **추적/금지**: commit 가능(`b2ad060` 의 reference spec 들처럼 보존 OK, 일회용도 무방·사용자가 정리) — 단 `/tmp/<slug>-spec.md` 같은 외부 임시 디렉토리는 금지(classifier 가 같은 turn 의 Write 추적 못 해 dispatch 거부될 수 있음).

호출 예:
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/dispatch-slice-pane.sh \
  --slice=<kebab> \
  --type=<feat|fix|refactor|test|docs|chore> \
  --spec-file=.claude/specs/<kebab>.spec.md \
  [--mode=auto|cmux|tmux|subagent]   [--model=<alias>]
# stdout: {"pane":"...","worktree":"...","branch":"<type>/<slug>","driver":"tmux|cmux"}
```

`--type` 미지정 시 `DISPATCH_DEFAULT_TYPE` env → 없으면 `feat`. `--model` 미지정 시 `DISPATCH_DEFAULT_MODEL` env → 없으면 `sonnet`. `--mode` 미지정 시 `DISPATCH_DEFAULT_MODE` env → 없으면 `auto`.

사용자가 자식 pane 에 직접 attach: `tmux attach -t tmux-pane-mgr`

pane 모드 완료 회수:
```bash
# cmux 모드: reap 이 wait-idle → capture → done 감지 → 자동 탭 종료 (미완료면 보존)
$wrapper reap --pane=$pane --idle=10 --timeout=1800
# tmux/기타 모드: 수동 회수
$wrapper wait-idle --pane=$pane --idle=10 --timeout=1800
$wrapper capture   --pane=$pane | tail -50 | grep -E '^[[:space:]]*(⏺[[:space:]]*)?(✅|❌)'
```

**병렬 dispatch 예시** — 의존성 없는 슬라이스 2개는 감시 루프 시작 전에 dispatch 를 연속 2회(또는 한 메시지 병렬 Bash 호출) 끝내고, 감시 루프는 **1개**만 돌린다:
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/dispatch-slice-pane.sh --slice=<slug-a> --spec-file=.claude/specs/<slug-a>.spec.md --mode=cmux
${CLAUDE_PLUGIN_ROOT}/scripts/dispatch-slice-pane.sh --slice=<slug-b> --spec-file=.claude/specs/<slug-b>.spec.md --mode=cmux
# 아래 "표준 감시 루프 — cmux-pane.sh watch" 로 두 자식 동시 회수
```
launch 는 mkdir-mutex 로 직렬화되지만 자식 작업 자체는 병렬 진행 — dispatch→회수→다음 dispatch 순차 진행은 병렬 이점을 없앤다.

**여러 자식을 한 번에 회수** — `reap --all` (argless 도 동일): 전 자식 순회, 완료(✅/❌)분만 회수하고 미완료는 "not done — kept" 로 보존, 신규 자식은 grace 로 skip. **완료 마커는 떴지만 자식 input box 에 미제출 사용자 텍스트(`❯ text` 프롬프트)가 남아있으면 원칙적으로 `input-pending — kept` 로 별도 보존** — 아직 부모에게 전달 안 된 후속 지시일 수 있어 kept 로 흡수하지 않는다. 단 **done-marker 가 있으면(marker trumps pending, 디폴트 on) pending 을 무시하고 회수 후 `reaped ... (pending-input 무시: <텍스트>)` 로 부기** — cmux composer draft/오버레이 오탐 대응(위 "부모가 회수" 절 참조). 강제 회수는 `CBP_REAP_IGNORE_PENDING=1`(marker 유무 무관 전면 무시). 마지막 줄에 `reaped N / kept M / pending P` 요약, exit 0.
```bash
$wrapper reap --all
# 또는 인자 없이 (argless 도 --all 과 동일 동작)
$wrapper reap
```

#### 표준 감시 루프 — `cmux-pane.sh watch`

marker fast-path + `reap --all` belt 를 묶은 foreground 감시 루프는 `cmux-pane.sh` 의 `watch` 서브커맨드로 인터페이스화(과거 fossil 쉘 루프에서 승격 이관): `$wrapper watch [--interval=2] [--max-iter=60] [--idle=3] [--timeout=30]`

- exit 코드: `0` 전원 회수 / `2` usage 오류 / `4` max-iter 도달 / `6` input-pending 감지 중단 / `7` reap 에러가드 중단.
- **기본 회수는 `hooks/reap-on-stop.sh` 자동 체인** — `watch` 는 즉시성이 더 필요할 때만 foreground 보조로 사용.

#### cross-WS dead orphan 자동 정리 (reap-orphans)

`cmux-pane.sh reap-orphans` 는 **현재 workspace 뿐 아니라 모든 workspace** 의 잔존 dead surface 를 회수한다. `plan-dev-session.sh start`(Phase 0 시작) 및 `finish-plan-dev.sh`(Phase 5 완료 후 backstop) 가 best-effort 로 자동 호출.

> 📎 수동 실행 / 미리보기(`CBP_REAP_ORPHANS_DRY_RUN=1`) / 우회 env 상세: [dispatch 진단 가이드](./troubleshooting-dispatch.md)

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
git rebase feature/<slug-a>
# 3. 머지 성공 확인 후 브랜치 삭제
git branch -D feature/<slug-a>

# 다음 슬라이스도 동일 패턴 반복
git worktree remove --force .worktrees/<slug-b>
git rebase feature/<slug-b>
git branch -D feature/<slug-b>
```

### disjoint 슬라이스는 cherry-pick 권장

슬라이스들이 **서로 다른 파일 영역**을 건드리면(파일 교집합 없음 = disjoint), 위 rebase dance 대신 **`git cherry-pick` 이 더 안전하고 간단**하다. worktree 점유 해제나 main HEAD 이동 걱정이 없고 충돌 위험도 없다:

```bash
# disjoint 슬라이스 통합 (파일 영역 안 겹칠 때) — main 에서 바로
git cherry-pick feature/<slug-a>       # 해당 커밋만 main 에 얹기
git cherry-pick feature/<slug-b>
# 확인 후 정리
git worktree remove --force .worktrees/<slug-a> && git branch -D feature/<slug-a>
git worktree remove --force .worktrees/<slug-b> && git branch -D feature/<slug-b>
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
