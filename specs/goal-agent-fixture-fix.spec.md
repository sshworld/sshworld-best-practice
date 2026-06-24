# Slice S1 — enforce_plan_dev_goal_agent 테스트 fixture 수정 (type=test)

## 목표
`tests/enforce_plan_dev_goal_agent.test.sh` 의 PLAN fixture 가 구식 `## Semantic goal` 헤더
형식이라 hook(`.claude/hooks/enforce-plan-dev-goal.sh`)의 인라인 `**Semantic goal**:` 추출과
mismatch → 추출 빈값 → agent layer skip → Scenario 2(agent FAIL→exit2) 미발생 → `set -e` exit 1.
**hook 은 정상.** fixture 만 인라인 형식으로 교체하면 6 scenario 전부 통과.

## 정확한 변경 (단 1곳)
`tests/enforce_plan_dev_goal_agent.test.sh` 의 PLAN heredoc 안:

기존:
```
## /machine-checks -->

## Semantic goal
Agent layer added to hook.
```
(정확히는 `<!-- /machine-checks -->` 다음의)
```
## Semantic goal
Agent layer added to hook.
```
→ 교체:
```
**Semantic goal**: Agent layer added to hook.
```

즉 `## Semantic goal` 헤더 줄과 다음 줄 본문을 인라인 `**Semantic goal**: Agent layer added to hook.` 한 줄로.
다른 fixture/Scenario 로직은 건드리지 말 것.

## 검증 (TDD Green 확인)
```bash
bash tests/enforce_plan_dev_goal_agent.test.sh   # "✅ all 6 scenarios passed"
grep -q '\*\*Semantic goal\*\*:' tests/enforce_plan_dev_goal_agent.test.sh
! grep -q '^## Semantic goal' tests/enforce_plan_dev_goal_agent.test.sh
```

## 완료 시
3개 검증 전부 PASS 면 `✅ S1 done` 출력. 실패면 `❌` + 원인.
