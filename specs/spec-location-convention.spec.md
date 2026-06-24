# Spec: Spec 파일 위치 컨벤션 통일 (S1, docs/spec-location-convention)

## 목표
plan-dev workflow 의 dispatch spec 파일 위치를 **`.claude/specs/<slug>.spec.md`** 로 통일. `/tmp/` 사용은 classifier transcript-blind 시 dispatch 거부 위험 — 안티패턴화.

이 spec 파일 자체가 새 컨벤션 적용 사례 (eat-your-own-dog-food).

## 산출 파일

### 수정
1. `.claude/commands/plan-dev.md` — Phase 2 가이드 + 안티패턴
2. `scripts/dispatch-slice-pane.sh` — header 주석 + usage() 출력 문구 (동작 변경 없음)
3. `CLAUDE.md` — 안티패턴 표 한 줄

## 변경 상세

### 1. `.claude/commands/plan-dev.md`

#### (a) Phase 2 dispatch 호출 예시 (line ~111-119)
**Before**:
```markdown
호출 예:
\`\`\`bash
scripts/dispatch-slice-pane.sh \
  --slice=<kebab> \
  --type=<feat|fix|refactor|test|docs|chore> \
  --spec-file=<spec.md> \
  [--mode=auto|cmux|tmux|subagent]   [--model=<alias>]
# stdout: {"pane":"...","worktree":"...","branch":"<type>/<slug>","driver":"tmux|cmux"}
\`\`\`
```

**After** (spec-file 경로를 `.claude/specs/<slug>.spec.md` 로 명시):
```markdown
호출 예:
\`\`\`bash
scripts/dispatch-slice-pane.sh \
  --slice=<kebab> \
  --type=<feat|fix|refactor|test|docs|chore> \
  --spec-file=.claude/specs/<kebab>.spec.md \
  [--mode=auto|cmux|tmux|subagent]   [--model=<alias>]
# stdout: {"pane":"...","worktree":"...","branch":"<type>/<slug>","driver":"tmux|cmux"}
\`\`\`
```

#### (b) Phase 2 모드 선택 끝 "Dispatch wrapper 가용성 검증" 박스 **다음** 에 새 박스 추가

"슬라이스 ✅ 확인 후:" 문구 위 어딘가에 자연스럽게. 권장 위치: `#### Dispatch wrapper 가용성 검증 (회복력 룰)` 박스 다음 줄.

**추가할 박스 (그대로 복붙)**:
```markdown

#### Spec 파일 위치 (컨벤션)

- **위치**: `.claude/specs/<slug>.spec.md` (slug = `--slice=<slug>` 와 동일 kebab-case)
- **명명**: `<slug>.spec.md` 접미사 사용
- **추적**: commit 가능 (`b2ad060` 의 reference spec 들처럼 보존 OK). 일회용도 무방, 사용자가 정리.
- **금지**: `/tmp/<slug>-spec.md` 같은 외부 임시 디렉토리 — classifier 가 같은 turn 의 Write 추적 못 해 dispatch 거부될 수 있음.
```

#### (c) 안티패턴 섹션 끝에 1줄 추가

기존 마지막 안티패턴 줄 (`❌ 작업 중 발견한 별개 버그를...`) 다음에:
```markdown
- ❌ dispatch spec-file 을 `/tmp/<slug>-spec.md` 등 repo 밖 임시 디렉토리에 쓰기 — classifier 가 같은 turn 의 Write 추적 못 해 dispatch 거부 위험. `.claude/specs/<slug>.spec.md` 사용.
```

### 2. `scripts/dispatch-slice-pane.sh`

#### (a) header 주석 (line 1-7 부근) — `# 사용:` 블록 안에 권장 위치 한 줄

**Before** (line 4-7):
```bash
# 사용:
#   dispatch-slice-pane.sh --slice=<kebab> --spec-file=<path> \
#                          [--worktree=<path>] [--mode=tmux|cmux|pane|auto|subagent] \
#                          [--model=<alias>] [--type=feat|fix|refactor|test|docs|chore]
```

**After** (예시 spec-file 을 `.claude/specs/<kebab>.spec.md` 로 명시):
```bash
# 사용:
#   dispatch-slice-pane.sh --slice=<kebab> --spec-file=.claude/specs/<kebab>.spec.md \
#                          [--worktree=<path>] [--mode=tmux|cmux|pane|auto|subagent] \
#                          [--model=<alias>] [--type=feat|fix|refactor|test|docs|chore]
#
# 권장 spec-file 위치: .claude/specs/<slug>.spec.md (kebab-case slug + .spec.md 접미사).
# /tmp/ 등 repo 밖 위치는 classifier transcript-blind 시 dispatch 거부될 수 있어 비권장.
```

#### (b) usage() 함수 출력 (line ~47-67) — `--spec-file=<path>` 에 권장 위치 안내 추가

**Before** (usage 문구):
```bash
dispatch-slice-pane.sh --slice=<kebab> --spec-file=<path> \
                       [--worktree=<path>] [--mode=tmux|cmux|pane|auto|subagent] \
                       [--model=<alias>] [--type=feat|fix|refactor|test|docs|chore]
```

**After**:
```bash
dispatch-slice-pane.sh --slice=<kebab> --spec-file=.claude/specs/<kebab>.spec.md \
                       [--worktree=<path>] [--mode=tmux|cmux|pane|auto|subagent] \
                       [--model=<alias>] [--type=feat|fix|refactor|test|docs|chore]

권장 spec-file 위치: .claude/specs/<slug>.spec.md (kebab-case + .spec.md).
```

usage 안 다른 텍스트는 그대로 유지. 절대경로/상대경로 둘 다 허용 — 인자 검증 동작 변경 없음.

### 3. `CLAUDE.md` 안티패턴 표

기존 안티패턴 목록 (현 `❌ dispatch-slice-pane.sh 의 spec 본문을 wrapper send 로 inline 전송...` 줄 부근) 에 1줄 append:
```markdown
- ❌ dispatch spec-file 을 `/tmp/<slug>-spec.md` 등 repo 밖에 두기 — classifier transcript-blind 시 dispatch 거부 위험. `.claude/specs/<slug>.spec.md` 컨벤션 사용.
```

## 일반화 검증
- 다른 프로젝트/회사명 절대 없음. 추상 용어만: "classifier", "transcript-blind", "spec-file", "kebab-case", "slug", "b2ad060" (본 repo 내부 commit 참조라 OK).

## Verification (구현 완료 후)
```bash
# 가이드 등장
grep -F ".claude/specs/" .claude/commands/plan-dev.md
grep -F "/tmp/<slug>-spec" .claude/commands/plan-dev.md
grep -F ".claude/specs/" scripts/dispatch-slice-pane.sh
grep -F ".claude/specs/" CLAUDE.md

# 회귀 (dispatch 동작 변경 없음 확인)
bash tests/dispatch-slice-pane_smoke.sh
bash tests/dispatch_slice_default_mode.sh
bash tests/dispatch_slice_branch_type.sh
bash tests/dispatch-slice-pane_model.sh
bash tests/dispatch-slice-pane_auto_cleanup.sh
bash tests/docs_sync.sh

# syntax
bash -n scripts/dispatch-slice-pane.sh
```

모두 PASS 후 `✅ S1 complete — docs/spec-location-convention`. 실패 시 `❌ <원인>`.

## 완료 조건
1. 위 3개 파일 변경
2. grep 검증 4종 매치
3. 회귀 테스트 6 종 PASS
4. dispatch-slice-pane.sh syntax OK
5. CLAUDE.md staged → DOC_IMPACT=updated 으로 commit 가능
