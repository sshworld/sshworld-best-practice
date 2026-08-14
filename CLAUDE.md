# CLAUDE.md — claude-best-practice repo 가이드

이 repo 자체를 작업할 때 Claude 가 따라야 할 규칙. (이 repo 가 제공하는 워크플로의 사용법은 [README.md](./README.md) 참조)

## 정체성

- 본 repo 는 **개인용 Claude Code 워크플로 모음**. 사용자(@shsong) 가 다양한 프로젝트에 글로벌/로컬로 깔아 쓰는 공통 자산.
- 핵심 가치: **"콘텐츠(commands/agents/skills) + 하네스(settings/hooks)" 이중 방어**. 모델 가이드와 런타임 강제를 같이 둔다.
- 베이스: [shanraisshan/claude-code-best-practice](https://github.com/shanraisshan/claude-code-best-practice).

## 변경 시 원칙

1. **콘텐츠와 하네스 짝 맞추기** — 새 룰은 콘텐츠(에이전트 프롬프트)만 두지 말고 하네스(hook/permission)로 강제력을 같이 부여한다. 반대로 하네스만 있고 콘텐츠 가이드가 없으면 사용자가 차단 이유를 모름 → 양쪽 다 명시.
2. **강제는 "판단 강제"로 설계** — 일률 차단/통과보다, 사용자에게 매번 한 번의 의식적 결정을 시키는 방향이 낫다. 예: `enforce-doc-sync.sh` 는 `DOC_IMPACT=none|updated` 환경변수로 결정을 명시하게 함.
3. **plan 파일은 200줄 이하** — implementor 가 자식 컨텍스트에서 통째로 읽기 좋게. 길어지면 슬라이스를 더 쪼개는 신호.
4. **Vertical slice — Horizontal phases 금지** — 슬라이스는 cross-layer feature 단위(DB+service+UI 같이). 슬라이스별 산출 파일 목록(`Slice File Map`)을 plan 에 명시, 다른 슬라이스와 같은 파일·영역 수정 시 단일 슬라이스로 병합 또는 순차 강등.
5. **README/CLAUDE.md 동기화** — `.claude/` 또는 `install.sh` 의 동작이 바뀌면 README.md 의 해당 섹션을 같이 업데이트. commit 의 `DOC_IMPACT` prefix 로 이를 강제.
6. **독자가 다르면 파일을 나눈다 (수명 분리)** — 한 파일이 사람과 기계를 같이 섬기면 순서가 한쪽으로 기울고 다른 쪽이 묻힌다. 사람용 = `~/.claude/design/<repo>/<slug>.md` (**개인 머신** 영속·누적, 파일 단위 = **롤백 단위**), 기계용 = plan 파일 (폐기). 섹션 순서를 조정하는 게 아니라 수명을 갈라야 200줄 캡과 사람 가독성이 동시에 성립한다.

## 릴리즈 & 체크리스트 (상세는 링크)

- 릴리즈 절차 / semver 기준 / 태그 컨벤션 / 노트 형식: [docs/release.md](./docs/release.md)
- command·agent·skill·hook·permission 추가 체크리스트 + 파일별 책임 전체: [docs/contributing.md](./docs/contributing.md)

## 비자명 gotcha

- 플러그인 버전 bump(예 1.3.4→1.3.5)+reload 후에도 **실행 중이던 세션**은 stale `CLAUDE_PLUGIN_ROOT`(옛 versioned 경로 GC됨) → `Hook script appears to be missing` 노이즈. 코드 결함 아님 — `/clear` 로 세션 재시작해야 새 plugin root 반영.
- `merge-settings.sh` 의 hook dedup 은 **cur 내부 + cur-vs-new 모두** 대상 — 과거 inline jq 의 matcher 미-unique 로 SessionStart hook 이 1024× 더블링되던 버그 재발 방지 (install 재실행해도 안전해야 하는 이유).
- `cmux-pane.sh reap` 의 `CBP_REAP_MARKER_TRUMPS_PENDING`(디폴트 on) — done-marker 가 own-workspace 로 확인되면 input-pending 가드보다 marker 를 우선해 회수한다. cmux workspace 잔존 composer draft/오버레이가 모든 자식 화면에 찍혀 pending 을 상시 오탐하던 문제 대응.

## 환경변수

전체 표는 **README.md 가 canonical home**(상세 각 스크립트 `--help` 참조). 자주 참조하는 것: `CLAUDE_MAX_CHILD_PANES`(`hooks/limit-child-panes.sh` 상한), `TMUX_PANE_NO_LAYOUT`(`scripts/tmux-pane.sh` 레이아웃 자동적용 끄기), `DISPATCH_DEFAULT_MODEL`(`scripts/dispatch-slice-pane.sh` 자식 model 디폴트), `CBP_LAUNCH_DEBUG`/`CBP_REAP_IGNORE_PENDING`(`scripts/cmux-pane.sh` launch 진단 / `reap` 강제회수).

관련 스크립트/스킬: `scripts/tmux-pane.sh`, `scripts/dispatch-slice-pane.sh`, `scripts/cmux-pane.sh`(reap 포함), `hooks/limit-child-panes.sh`, `skills/tmux-orchestrate`, `commands/parallel-consult.md`, `.claude/workflows/*.mjs` — 상세는 [docs/contributing.md](./docs/contributing.md).

## 안티패턴

- ❌→ℹ️ 플러그인 버전 bump 직후 실행 중이던 세션의 stale plugin root 노이즈 — `/clear` 로 해결, 코드 결함 아님(위 gotcha 참조).
- ❌ Dead code 판정 시 사용처 grep + 테스트 prop 직접 주입 확인 누락 — 부모가 prop 으로 set 하는 분기를 "도달 불가" 로 오판해 삭제하면 기존 테스트가 회귀로 catch.
- ❌ 검증용 단순 curl / sleep 단독 호출 — Bash 자동 background 진입으로 동기 결과 못 받음. `timeout 5 curl ...` 또는 cmux browser eval 사용.
- ❌ 테스트에 now 와의 관계를 가정한 절대 날짜 리터럴(2026-01-01 식 start_ts 등) — 시점 지나면 rot. now-offset(relative)으로.
- ❌ 병렬 슬라이스 통합 시 worktree 점유 브랜치를 rebase 시도 / rebase+cleanup 을 한 `&&` 체인에 — 중간 실패가 미머지 브랜치를 삭제. worktree remove 먼저, cleanup 은 머지 후. disjoint 슬라이스(파일 비충돌)는 rebase 말고 `cherry-pick` 권장.
- ❌ 자식(cmux surface / tmux pane / bg 세션 / subagent)을 띄우고 **계보를 기록하지 않기** — Claude 세션 레코드엔 부모 필드가 없어서(2026-08-14 실측) spawn 시점에 안 적으면 "누가 내 자식인가" 를 영영 알 수 없고, 회수가 전역 스윕으로 밀린다. spawn=`reap-agents.sh record`, 회수=`reap-agents.sh reap`. **원천은 보존, 자식만 회수.** 📎 [계약](./commands/plan-dev/troubleshooting-dispatch.md)
- ❌ `_pid_chain | grep -qx "$pid"` 로 자기 보호 판정 — `grep -q` 가 매치 즉시 파이프를 닫아 SIGPIPE(141)가 나고 `set -o pipefail` 이 그걸 파이프라인 결과로 삼아 **매치했는데 거짓**이 된다(자기 보호가 조용히 꺼짐). 파이프 없는 루프로 판정할 것.
- ❌ 실제 cmux/tmux 를 건드리는 스크립트(`finish-plan-dev.sh` 의 `do_cmux_cleanup` 등)를 테스트에서 우회 선언 없이 실행 — 가드가 `CMUX_WORKSPACE_ID` 존재뿐이라 dispatch 자식 안에서 돌면 자기/형제 surface 를 닫는다(= 자식 자살, 2026-08-13 실측). 해당 스위트는 `export SKIP_PLAN_DEV_CMUX_CLEANUP=1` + `export SKIP_CMUX_REAP=1` 필수. 📎 [진단](./commands/plan-dev/troubleshooting-dispatch.md)
- ❌ **개인 작업 기록(설계 문서)을 repo 에 커밋** — 공개 저장소면 그대로 공개되고, 팀 저장소면 타인에게 읽기·유지를 강요한다. 기본은 repo 밖 `~/.claude/design/<repo>/`(홈의 `~/.claude/` 이지 **repo 안 `.claude/` 가 아니다** — 후자는 repo 별 gitignore 로 소실된다). 팀과 공유할 문서만 `CBP_DESIGN_DIR` 로 repo 안 경로를 명시.
- ❌ 필수 동작을 선택 단계(`Phase 3.5 — Review (선택)` 등) 안에 배치 — 그 단계를 건너뛰는 세션이 필수 동작을 같이 건너뛴다. 필수는 필수 단계에 (실측 write-back 을 3.5 → 4-0 으로 옮긴 이유).
- ❌ 콘텐츠만 추가 / 하네스 없음, 또는 그 반대 — 양쪽 다 필요 (예외: `/fork` 같은 스킬 호출은 hook 으로 강제 불가 — Stop hook 은 turn 재개만 가능하고 액션 지정 불가, 이 경우는 콘텐츠 전용이 정당한 설계).

> 📎 dispatch/cmux/plan-dev 관련 안티패턴(30항목 상세)은 [commands/plan-dev/antipatterns.md](./commands/plan-dev/antipatterns.md) 가 canonical.
