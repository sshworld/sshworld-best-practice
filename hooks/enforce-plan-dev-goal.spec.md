# Unit Test Scenarios — enforce-plan-dev-goal.sh

Test file: `tests/hooks/enforce-plan-dev-goal.test.sh`

## Results

| # | Scenario | Expected | Result |
|---|---|---|---|
| 1 | marker 없음 (SESSION_FILE not found) | exit 0 | ✅ |
| 2 | marker 있고 plan 파일 없음 | exit 0 | ✅ |
| 3 | machine-checks 전부 PASS | exit 0 | ✅ |
| 4 | 하나 fail → exit 2 + stderr "FAIL" | exit 2 | ✅ |
| 5 | SKIP_PLAN_DEV_GOAL=1 | exit 0 (skipped) | ✅ |
| 6 | DISABLE_PLAN_DEV_GOAL_HOOK=1 | exit 0 (disabled) | ✅ |

## Run

```bash
bash tests/hooks/enforce-plan-dev-goal.test.sh
```

Expected output: `✅ all 6 scenarios passed`
