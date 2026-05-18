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
| `.claude/skills/fork/SKILL.md` | 자식 컨텍스트로 작업 위임, 요약만 반환. |
| `.claude/skills/tmux-orchestrate/SKILL.md` | 부모-자식 Claude tmux pane 협업 패턴 가이드. |
| `.claude/hooks/*.sh` | 런타임 강제. stderr 메시지에 우회 방법 항상 명시. |
| `.claude/hooks/limit-child-panes.sh` | 자식 tmux pane spawn 상한 강제 (`CLAUDE_MAX_CHILD_PANES`). |
| `.claude/hooks/statusline-tokens.sh` | (opt-in 대안) statusLine 으로 토큰 사용량 상시 표시. 기본은 `token-stats.sh` 의 inline 메시지. |
| `.claude/settings.json` | permissions(allow/deny) + hooks. 광역 `Bash(tmux*)` 금지 — 좁힌 패턴만. |
| `scripts/tmux-pane.sh` | tmux wrapper — launch/send/capture/wait-idle/kill/list/status. 외부 `tmux-cli` 와 명령 표면 정렬. |
| `scripts/dispatch-slice-pane.sh` | implementor 슬라이스를 worktree + tmux pane 으로 spawn. `plan-dev --mode=pane` 진입점. `--model=<alias>` 로 자식 model 선택 (디폴트 sonnet). `build_child_cmd` 순수 함수로 분리되어 단위 테스트 가능. 시작 시 기존 자식 pane 자동 정리 (`DISPATCH_SKIP_CLEANUP=1` 우회). |

## 추가 / 수정 체크리스트

새 command/agent/skill 추가 시:
- [ ] frontmatter `name` 값이 파일명과 일치하는가?
- [ ] description 한 줄로 호출 시점이 명확한가?
- [ ] 다른 agent/command 와 책임이 겹치지 않는가?
- [ ] 관련 하네스(hook) 가 필요한가? 있다면 같이 추가.
- [ ] README.md 의 "구성" / "사용" 섹션 업데이트.

새 hook 추가 시:
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

## 환경변수 (tmux 통합)

| 변수 | 기본 | 효과 |
|---|---|---|
| `CLAUDE_MAX_CHILD_PANES` | 5 | 자식 tmux pane 상한 — `limit-child-panes` hook 이 강제 |
| `DISABLE_PANE_LIMIT_HOOK` | unset | `limit-child-panes` hook 영구 비활성화 |
| `FORCE_SELF_KILL` | unset | `tmux-pane.sh kill` 의 자기 pane 거부 우회 |
| `TMUX_PANE_NO_LAYOUT` | unset | `tmux-pane.sh launch` 의 main-vertical layout 자동 적용 끄기 |
| `DISPATCH_CHILD_CMD` | unset | `dispatch-slice-pane.sh` 가 자식 명령으로 사용할 cmd 강제 (테스트용 substitute) |
| `DISPATCH_DEFAULT_MODEL` | sonnet | `dispatch-slice-pane.sh` 의 자식 model 디폴트 (--model arg 가 우선) |
| `DISPATCH_SKIP_CLEANUP` | unset | `dispatch-slice-pane.sh` 의 시작 시 자식 pane 자동 정리 끄기 |

## 향후 작업 (플러그인화)

본 repo 는 최종적으로 Claude Code 플러그인 형태로 패키징될 예정. 그 시점에:
- `install.sh` 는 플러그인 manifest 로 대체.
- `.claude/` 디렉토리 구조는 유지하되 plugin 메타데이터 추가.
- 글로벌 / 프로젝트 scope 는 플러그인 enable 방식으로.

지금은 sh 기반 설치로 충분 — 플러그인화는 안정화된 후.
