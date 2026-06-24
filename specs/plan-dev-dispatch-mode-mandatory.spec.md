# Spec: plan-dev Mode 컬럼 의무화 + Phase 3 통합 테스트 룰 (S2, docs/plan-dev-dispatch-mode-mandatory)

## 목표

`.claude/commands/plan-dev.md` 4 위치 변경:
1. Phase 1-2 Slice File Map 정의 — **Mode 컬럼 필수**, 빈 셀 금지. `direct-edit` 선택 시 1줄 justification 의무.
2. Phase 1-3 (충돌 사전 점검 다음) — **dispatch default 박스**: cmux 환경에서 모든 슬라이스 dispatch default. direct-edit 은 명시 사유 (단일 파일 / <20줄 / 시각화 가치 없음) 필요.
3. Phase 3 — rebase 후 verifier 가 **슬라이스별 격리 테스트 + 전체 통합 테스트 둘 다** 실행. 격리 PASS + 통합 FAIL 의 root cause 분석 의무.
4. 안티패턴 2줄 추가.

## 산출 파일

### 수정 (단일)
`.claude/commands/plan-dev.md`

## 변경 상세

### (a) Slice File Map 정의 강화 (line 60-69)

**Before** (line 60-69):
```markdown
**Slice File Map** — 각 슬라이스의 산출 파일 목록 (Write/Edit 대상). rebase fast-forward 충돌 예방 목적. 형식:
| Slice | Files | Mode | DOC_IMPACT |
|---|---|---|---|
| S1 | scripts/foo.sh, README.md | dispatch | updated |
| S2 | .claude/agents/bar.md | direct-edit | none |

- `Mode` — `dispatch` (cmux/tmux/subagent dispatch) / `direct-edit` (부모가 직접 Edit) 중 슬라이스 처리 방식 plan 단계에 미리 결정.
- `DOC_IMPACT` — `none` / `updated` 중 plan 단계에 미리 결정 (commit 시점에 발견하면 hook 차단 후 재시도 비용).
```

**After**:
```markdown
**Slice File Map** — 각 슬라이스의 산출 파일 목록 (Write/Edit 대상). rebase fast-forward 충돌 예방 목적. 형식:
| Slice | Files | Mode | DOC_IMPACT |
|---|---|---|---|
| S1 | scripts/foo.sh, README.md | dispatch | updated |
| S2 | .claude/agents/bar.md | direct-edit (단일 파일 <20줄) | none |

- `Mode` — `Mode 컬럼 필수`, 빈 셀 금지. `dispatch` (cmux/tmux/subagent dispatch) / `direct-edit` (부모가 직접 Edit) 중 슬라이스 처리 방식 plan 단계에 미리 결정. **`direct-edit` 선택 시 1줄 justification 의무** (예: "단일 파일 <20줄", "config 한 줄 변경", "시각화 가치 없음").
- `DOC_IMPACT` — `none` / `updated` 중 plan 단계에 미리 결정 (commit 시점에 발견하면 hook 차단 후 재시도 비용).
```

### (b) Phase 1-3 충돌 사전 점검 다음에 dispatch default 박스 추가

**대상 위치**: line 74 `**충돌 사전 점검**: Slice File Map 의 파일 교집합 존재 시 그 슬라이스들은 의존성 있음으로 분류 — 병렬 X, 순차로 강등하거나 단일 슬라이스로 병합.` 뒤 빈 줄 다음.

**삽입할 박스**:
```markdown

> 🚀 **dispatch default 룰** (cmux 환경): 모든 슬라이스는 **dispatch default**. `direct-edit` 은 명시 justification 필요. 사유 카테고리:
> - 단일 파일 + 변경 <20줄 → direct-edit 허용
> - 사용자가 화면에서 자식 진행을 볼 가치 없는 mechanical 변경 → direct-edit 허용
> - 그 외 — Mode 컬럼에 `dispatch (cmux)` 명시 후 `scripts/dispatch-slice-pane.sh --mode=cmux` 호출.
>
> 본 repo 의 settings.json 은 cmux 환경에서 Edit/Write 누적 2회 시 hook 으로 차단 (`CMUX_EDIT_BURST_STRICT=1` inline). 우회는 SKIP env 명시.
```

### (c) Phase 3 verify 룰 추가

**대상 위치**: Phase 3 섹션 안 `**verifier 루프:**` 직후 또는 `verifier` 호출 설명 다음.

기존 (line ~190 부근):
```markdown
**verifier 루프:**
- rebase 완료 후 `verifier` 에이전트 호출.
- 실패 시 원인 + 수정안 적용 → 재호출. 최대 5회.
```

**After** — 위 단락 뒤에 다음 박스 1개 추가 (다음 섹션 헤더 `## Phase 3.5 — Review` 직전):
```markdown

> 🔬 **통합 테스트 의무** (격리 dispatch 사용 시): rebase 후 verifier 는 **슬라이스별 격리 테스트** (각 worktree 안에서 PASS 확인된 것) + **전체 통합 테스트** (rebase 머지 후 부모 branch 에서 BUILD + TEST 전체 실행) 둘 다 실행. 격리 PASS 인데 통합 FAIL = 슬라이스 간 숨은 의존성 노출 — root cause 분석 후 fix 슬라이스 추가 또는 슬라이스 재분해. 격리만 보고 PASS 처리 금지.
```

### (d) 안티패턴 섹션 끝에 2줄 추가

기존 마지막 안티패턴 줄 (`❌ 사용자가 메시지에 명시한 옵션 (A 또는 B) 을...`) 다음:
```markdown
- ❌ Slice File Map 의 Mode 컬럼 비워두거나 모호하게 ("적당히") 두기 — plan 단계 dispatch/direct-edit 분기 흐려져 Phase 2 진입 후 디폴트로 direct-edit 흐름. 빈 셀 = ExitPlanMode 차단 신호로 self-check.
- ❌ cmux 환경에서 justification 없이 direct-edit 선택 — 시각화/병렬 가치 날림. dispatch default + direct-edit 사유 명시 룰 따름.
```

## Verification (구현 완료 후)

```bash
# 추가 문구 존재
grep -F "Mode 컬럼 필수" .claude/commands/plan-dev.md
grep -F "direct-edit 선택 시 1줄 justification" .claude/commands/plan-dev.md
grep -F "dispatch default 룰" .claude/commands/plan-dev.md
grep -F "통합 테스트 의무" .claude/commands/plan-dev.md
grep -F "격리만 보고 PASS 처리 금지" .claude/commands/plan-dev.md
grep -F "Mode 컬럼 비워두거나" .claude/commands/plan-dev.md
grep -F "justification 없이 direct-edit" .claude/commands/plan-dev.md

# 안티패턴 라인 수 +2 이상 (이전 20 → 22)
N=$(grep -c '^- ❌' .claude/commands/plan-dev.md)
[ "$N" -ge 22 ] || { echo "안티패턴 부족: $N"; exit 1; }

# 회귀
bash tests/docs_sync.sh
```

모두 PASS 후 `✅ S2 complete — docs/plan-dev-dispatch-mode-mandatory`. 실패 시 `❌ <원인>`.

## 일반화 검증
- 다른 프로젝트/회사명 없음. 본 repo 의 hook 이름 (`track-cmux-edit-burst`) 만 참조.

## DOC_IMPACT

`none` — plan-dev.md 자체가 workflow 가이드. CLAUDE.md/README 의 책임 분리 표나 환경변수 표 변경 없음.

## 완료 조건
1. .claude/commands/plan-dev.md 4 위치 변경
2. grep 7 종 매치
3. 안티패턴 줄 수 22 이상
4. docs_sync.sh 회귀 없음
