# claude-best-practice

나만의 Claude Code 워크플로 모음. **`/plan-dev` TDD 워크플로 + 컨텍스트 관리 + 강제 가드(하네스)** 한 세트.

`shanraisshan/claude-code-best-practice` 가이드를 베이스로, 실사용 중에 다듬은 규칙을 콘텐츠(commands/agents/skills)와 하네스(settings/hooks) 양쪽으로 구성.

---

## 구성

```
.claude/
├── commands/
│   ├── plan-dev.md           # 6단계 워크플로 (Explore → Plan → Review → TDD → Verify → Commit → Context 정리)
│   └── parallel-consult.md   # 자식 Claude pane 띄워 한 번 질문하고 답 회수
├── agents/
│   ├── implementor.md        # TDD Red→Green→Refactor, worktree 격리 (+ tmux pane 모드 지원)
│   ├── verifier.md           # Read-only 빌드/테스트 실행 + diff 제안
│   ├── reviewer.md           # 치명적 이슈만 블로킹, 나머지 제안
│   └── commit-advisor.md     # 한글 Conventional Commit + DOC 영향 평가
├── skills/
│   ├── fork/SKILL.md         # 자식 컨텍스트에서 처리하고 요약만 반환
│   └── tmux-orchestrate/SKILL.md # 부모-자식 Claude tmux pane 협업 패턴
├── hooks/
│   ├── enforce-test-first.sh # production 파일 작성 전 테스트 존재 검사
│   ├── enforce-doc-sync.sh   # commit 시점 DOC 영향 평가 강제
│   ├── limit-child-panes.sh  # 자식 tmux pane spawn 상한 (CLAUDE_MAX_CHILD_PANES)
│   ├── statusline-tokens.sh  # (opt-in) 하단 status bar 모드 — 기본은 token-stats.sh 사용
│   └── token-stats.sh        # Stop hook 으로 직전 응답 토큰 사용량 + 캐시 히트율 inline 노출
└── settings.json             # permissions(allow/deny) + 4 hooks
scripts/
├── tmux-pane.sh              # 얇은 tmux wrapper — launch/send/capture/wait-idle/kill/list/status
├── cmux-pane.sh              # 얇은 cmux wrapper — launch/send/capture/kill/list/cleanup/status + state file 헬퍼
├── detect-pane-env.sh        # 터미널 환경 감지 — tmux | cmux | default
└── dispatch-slice-pane.sh    # implementor 슬라이스를 tmux/cmux pane 으로 dispatch (plan-dev --mode=pane)
```

---

## 설치

```bash
# 글로벌 (~/.claude/) — 모든 프로젝트에서 사용
./install.sh user

# 프로젝트 로컬 (현재 디렉토리/.claude/)
./install.sh project

# 특정 디렉토리에 설치
./install.sh project /path/to/your/project

# 제거
./install.sh uninstall user
./install.sh uninstall project [TARGET_DIR]
```

기존 파일이 있으면 `.bak` 확장자로 백업한 뒤 덮어씁니다. `settings.json` 은 자동 병합하지 않고 `settings.example.json` 으로 복사 — 사용자가 수동 병합.

---

## 사용

### 메인 워크플로 — `/plan-dev`

```text
/plan-dev "이메일 인증 회원가입 추가"
```

자동 진행 흐름:
1. **Explore**: 관련 파일 자동 스캔
2. **빈틈 진단**: `AskUserQuestion` 으로 요구사항 명확화 반복
3. **EnterPlanMode**: plan 파일 작성 (200줄 이하 권장)
4. **Staff Engineer Plan Review**: Plan 서브에이전트 비평 (선택)
5. **ExitPlanMode**: 사용자 승인
6. **TDD Execute**: 병렬 implementor → worktree 격리, Red→Green→Refactor
7. **Verify**: verifier 빌드/테스트 (max 5회 루프)
8. **Review**: reviewer 치명적 이슈 점검 (선택)
9. **Commit**: commit-advisor 한글 메시지 추천 + DOC 영향 평가
10. **Context 정리**: 다음 추천 명령 (`/clear` / `/compact` / `/fork`) 노출

### 보조 — `/fork`

현재 흐름의 작업을 격리된 서브에이전트에 위임하고 부모 세션엔 요약만 반환:

```text
/fork
```

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

부모가 자식 Claude pane 을 띄워 질문 → 응답 회수 → 부모 세션에 요약 + "자식 pane 유지/kill" 묻기. 자세한 흐름은 `.claude/commands/parallel-consult.md`.

### `/plan-dev --mode=pane` — implementor 를 tmux pane 으로

기본 subagent 모드 대신 `--mode=pane` 시 `scripts/dispatch-slice-pane.sh` 가 각 슬라이스를 tmux pane 에 띄움. 사용자가 `tmux attach -t tmux-pane-mgr` 로 자식 작업을 직접 모니터링/개입 가능.

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

`tmux-orchestrate` skill 가이드 (`.claude/skills/tmux-orchestrate/SKILL.md`) 에 안티패턴 + 호출 시퀀스 정리.

### 자식 pane 라이프사이클

새 `/parallel-consult` / `/plan-dev --mode=pane` 작업 시작 시 **이전 자식 pane 자동 정리**:
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
- `cmux-pane.sh send/capture/wait-idle --pane=surface:N` → `--surface` flag 자동 dispatch. `workspace:N` ref 는 기존 `--workspace` (회귀 zero).
- `cmux-pane.sh list` → state file 의 자식 surface 우선, 폴백으로 cbp- workspace 목록. cmux tree 와 lazy reconcile (mock 환경 자동 감지).
- `cmux-pane.sh cleanup` → state file 의 surface 일괄 `close-surface` + state 제거 후, 기존 cbp- workspace cleanup 도 실행 (호환).

`CBP_SPLIT_POLICY` 환경변수로 방향을 `down` / `right` 고정 가능 (unset 시 라운드로빈 고정).

`CMUX_WORKSPACE_ID` unset 환경에서는 기존 new-workspace 흐름 그대로 (회귀 zero).

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

### 6) SessionStart inline

세션 시작 시 git worktree 목록 + 미커밋 변경 자동 출력.

---

## 환경변수 정리

| 변수 | 기본 | 효과 |
|---|---|---|
| `CLAUDE_TDD_STRICT=1` | off | TDD 위반 시 Write/Edit 차단 |
| `DOC_IMPACT=none|updated` | (미지정 시 차단) | commit 시 DOC 영향 명시 |
| `SKIP_DOC_SYNC=1` | off | doc-sync hook 1회 우회 (deprecated — DOC_IMPACT 사용) |
| `DISABLE_DOC_SYNC_HOOK=1` | off | doc-sync hook 영구 비활성화 |
| `DISABLE_TOKEN_STATS=1` | off | token-stats hook 비활성화 |
| `CLAUDE_MAX_CHILD_PANES=N` | 5 | 자식 tmux pane 상한 (limit-child-panes hook) |
| `DISABLE_PANE_LIMIT_HOOK=1` | off | limit-child-panes hook 비활성화 |
| `FORCE_SELF_KILL=1` | off | tmux-pane.sh kill 의 자기 pane 거부 우회 |
| `TMUX_PANE_NO_LAYOUT=1` | off | tmux-pane.sh launch 의 main-vertical layout 자동 적용 끄기 |
| `DISPATCH_DEFAULT_MODEL=<alias>` | sonnet | dispatch-slice-pane.sh 의 자식 model 디폴트 (--model arg 가 우선) |
| `DISPATCH_SKIP_CLEANUP=1` | off | dispatch-slice-pane.sh 가 main 진입 시 자식 pane 자동 정리 끄기 |
| `CMUX_BIN=<path>` | `cmux` | cmux-pane.sh / detect-pane-env.sh 가 사용할 cmux 바이너리 경로 (테스트 mock 에 사용) |
| `CBP_STATE_FILE=<path>` | `~/.cache/cbp/children-<ws>.json` | cmux-pane.sh state file 경로 override (ws sanitize 규칙: `${CMUX_WORKSPACE_ID//[:\/]/_}`) |
| `CBP_WORKSPACE_PREFIX=<str>` | `cbp-` | cmux-pane.sh launch 의 workspace 이름 prefix |
| `CBP_LIST_LINES=<str>` | unset | cmux-pane.sh list/cleanup/status 의 list-workspaces 입력 mock (테스트용) |
| `CLAUDE_FAKE_SELF_CMUX_WS=<ref>` | unset | cmux-pane.sh kill/cleanup 의 자기 workspace ref mock (테스트용) |
| `CBP_SPLIT_POLICY=<dir>` | unset (라운드로빈) | cmux-pane.sh grid split 방향 고정 (`down` 또는 `right`). unset 시 라운드로빈 (홀수→down, 짝수→right) |

---

## Permissions (settings.json)

기본 allow:
- `git status`, `diff`, `log`, `branch`, `checkout`, `switch`, `fetch`, `pull`, `add`, `commit`, `stash`, `merge`, `rebase`, `remote`, `tag`, `worktree`, `restore`
- `BUILD_CMD` / `TEST_CMD` / `RUN_CMD` TODO 자리 (사용자가 프로젝트 빌드 명령으로 치환)

기본 deny:
- `rm -rf*`, `git push --force*`, `git push -f*`, `git commit --no-verify*`, `git reset --hard*`

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
