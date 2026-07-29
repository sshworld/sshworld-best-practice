## 안티패턴 — 절대 하지 말 것

핵심 7개만 잔류 — 각 항목의 상세 배경은 canonical 파일 링크 참조.

- ❌ `git merge <type>/<slug>` 사용 — merge 커밋이 슬라이스 라벨·잡음을 히스토리에 노출. 항상 rebase fast-forward. 📎 [cmux dispatch 가이드 — Phase 3 머지 방법](./cmux-dispatch.md#phase-3--worktree-머지-방법)
- ❌ pane/cmux 모드에서 자식 결과(`✅` / `❌`) **회수 전 머지** 시도 — 미완료 상태를 머지해 부모 브랜치가 오염될 수 있음. 📎 [cmux dispatch 가이드 — 부모가 회수](./cmux-dispatch.md)
- ❌ `S1`/`S2` 등 슬라이스 라벨 또는 `merge:` 를 최종 커밋 메시지·브랜치명에 노출 — 협업자는 슬라이스 번호를 모른다. 📎 [commit-advisor.md](../../agents/commit-advisor.md)
- ❌ Phase 1-4 ExitPlanMode 사용자 승인 게이트를 우회하고 Phase 2 진입 — plan 미승인 상태의 구현은 되돌리기 비용이 큼.
- ❌ 다른 슬라이스가 점유한 worktree/브랜치의 파일을 교차 수정 — Slice File Map 의 Files 교집합으로 사전 점검, 겹치면 순차 강등 또는 병합.
- ❌ 슬라이스 worktree 안에서 직접 `git commit` / `git push` — 통합은 Phase 3(rebase) → Phase 4(commit-advisor) → Phase 5(finish-plan-dev.sh) 흐름으로만.
- ❌ 사용자 opt-in 없이 `Workflow` 툴 호출 — 수십 agent 비용 발생. 📎 [Workflow 통합 가이드](./workflow-integration.md)

> 📎 cmux 환경별 Mode 규칙(direct-edit 금지 등) canonical: [cmux dispatch 가이드](./cmux-dispatch.md)
