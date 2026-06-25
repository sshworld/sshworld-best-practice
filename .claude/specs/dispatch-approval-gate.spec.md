# Slice S2 — dispatch-approval-gate (type: feat)

## 목표
plan-dev **Phase 2 dispatch** 를 ExitPlanMode 승인 후에만 허용하도록 하네스 강제. 현재 `dispatch-slice-pane.sh` 는 Bash 라 `enforce-plan-mode`(Write/Edit 전용) 를 안 타서, **ExitPlanMode 승인 전에도 자식 dispatch 가 가능**한 갭이 있다. 이걸 막는다.

## 확인된 기술 근거 (그대로 신뢰)
- **PostToolUse 는 도구 성공 시에만 발화** → `ExitPlanMode` 가 **승인**되면 발화, **reject/interrupt 면 미발화**. = 신뢰 가능한 "plan 승인" 신호.
- **PreToolUse:Bash** hook 은 stdin JSON 으로 `tool_input.command`(전체 명령 문자열), `tool_name`, `permission_mode`, `session_id`, `cwd` 수신.

## 절대 규칙
- **TDD Red→Green→Refactor**. 테스트 먼저 FAIL 확인.
- 커밋 메시지에 `S2`/`슬라이스`/`merge:` 등 내부 라벨 금지. 깨끗한 `feat: …` 한글 한 문장.
- 기존 hook 스타일 미러: `hooks/enforce-plan-mode.sh`, `hooks/enforce-cmux-dispatch.sh` (stderr 에 우회법 명시, conservative fallback, `SKIP_*`/`DISABLE_*_HOOK` env).
- 완료 시 `✅` / 실패 `❌`.

## 변경 대상
1. `hooks/mark-plan-approved.sh` (신규)
2. `hooks/enforce-dispatch-gate.sh` (신규)
3. `scripts/plan-dev-session.sh` (start 시 approved marker rm)
4. `scripts/finish-plan-dev.sh` (clear_marker 가 approved marker 도 rm)
5. `hooks/hooks.json` + `.claude/settings.json` (두 hook 등록)
6. `tests/enforce_dispatch_gate.sh` (신규)
7. `CLAUDE.md`, `README.md` (문서 동기화)

---

## 1. `hooks/mark-plan-approved.sh` (PostToolUse:ExitPlanMode)
- stdin JSON 읽음. `tool_name` != `ExitPlanMode` → exit 0.
- plan-dev 세션 marker(`$CLAUDE_PROJECT_DIR/.git/plan-dev-session.json`, 없으면 `git rev-parse --git-common-dir`/plan-dev-session.json) 없으면 exit 0 (비-plan-dev).
- `session_id` 추출 → `<git-common-dir>/plan-dev-plan-approved` 에 기록 (파일 내용 = session_id).
- python3/jq 부재·파싱 실패 시 conservative exit 0 (절대 비차단 — PostToolUse 는 차단용 아님).
- override env (테스트 mock): `PLAN_APPROVED_MARKER` (marker 경로). `chmod +x`.

## 2. `hooks/enforce-dispatch-gate.sh` (PreToolUse:Bash)
판정 순서 (enforce-plan-mode.sh 미러):
- `DISABLE_DISPATCH_GATE_HOOK=1` → exit 0. `SKIP_DISPATCH_GATE=1` → exit 0.
- stdin JSON 읽음. `tool_name` != `Bash` → exit 0.
- `tool_input.command` 에 `dispatch-slice-pane.sh` 문자열 **없으면** → exit 0 (관심 명령 아님).
- 세션 marker 없음 → exit 0 (비-plan-dev).
- 자식 worktree (`git rev-parse --git-dir` != `--git-common-dir`) → exit 0.
- `permission_mode` == `bypassPermissions` → exit 0 (명시 우회/자식).
- approved marker(`<git-common-dir>/plan-dev-plan-approved`) 존재 **AND** 내용(session_id) == stdin `session_id` → exit 0 (승인됨).
  - marker 부재 또는 session_id 불일치(stale 다른 세션) → 차단.
- 차단: exit 2 + stderr:
  ```
  🛑 [enforce-dispatch-gate] plan-dev 세션인데 ExitPlanMode 승인 전 dispatch 시도.
     먼저 EnterPlanMode → plan 작성 → ExitPlanMode 로 사용자 승인 후 dispatch 할 것.
     우회: SKIP_DISPATCH_GATE=1 (1회) / DISABLE_DISPATCH_GATE_HOOK=1 (영구).
  ```
- session_id 추출 불가 등 파싱 실패 → conservative **exit 0** (false-block 회피, enforce-plan-mode 패턴).
- override env (테스트 mock): `DISPATCH_GATE_SESSION_FILE`, `PLAN_APPROVED_MARKER`. `chmod +x`.

## 3. `scripts/plan-dev-session.sh`
- `start` 서브커맨드에서 marker 기록 직후, stale approved marker 제거: `rm -f "<git-common-dir>/plan-dev-plan-approved"` (fresh 세션은 미승인 상태로 시작). 기존 start 로직·필드 보존, 재진입 보존 로직 깨지 말 것.

## 4. `scripts/finish-plan-dev.sh`
- `clear_marker()` 함수에 `rm -f "${COMMON_DIR}/plan-dev-plan-approved"` 추가 (session marker·commit-advised marker 와 함께 정리). **주의: 이 파일은 S1 에서 이미 MARKER_ADVISED rm 가 추가돼 있음 — 그 옆에 한 줄 추가.**

## 5. 등록 — `hooks/hooks.json` + `.claude/settings.json`
- `hooks/hooks.json`: PreToolUse `Bash` matcher 배열에 `enforce-dispatch-gate.sh` 추가. **PostToolUse** 이벤트 신규 추가 — matcher `ExitPlanMode`, hook `mark-plan-approved.sh`. 경로 형식 `"${CLAUDE_PLUGIN_ROOT}"/hooks/<name>.sh`.
- `.claude/settings.json`: 동일 두 hook 을 프로젝트 scope 경로 형식(`$CLAUDE_PROJECT_DIR/hooks/...` 등 기존 settings 형식에 맞춤)으로 등록. 기존 hooks 보존, 중복 금지.
- 두 JSON 모두 valid 유지: `python3 -c "import json;json.load(open('hooks/hooks.json'))"`, settings.json 동일.

## 6. 테스트 — `tests/enforce_dispatch_gate.sh`
더미 git repo fixture + JSON payload 를 stdin 으로 hook 에 파이프. 케이스:
- **C1**: 세션 marker 활성 + approved marker 부재 + command 에 `dispatch-slice-pane.sh` → exit **2**.
- **C2**: approved marker 존재(내용=payload session_id) → exit **0**.
- **C3**: command 가 dispatch 무관(`echo hi`) → exit **0**.
- **C4**: `SKIP_DISPATCH_GATE=1` + 차단 조건 → exit **0**.
- **C5**: 세션 marker 없음 → exit **0**.
- **C6**: `mark-plan-approved.sh` 에 ExitPlanMode payload(session_id=X) 파이프 → approved marker 생성 + 내용 == X.
`PLAN_APPROVED_MARKER`/`DISPATCH_GATE_SESSION_FILE` env 로 경로 mock. 마지막 줄 `PASS`. `chmod +x`.

## 7. 문서
- `CLAUDE.md`: 파일별 책임 표에 `mark-plan-approved.sh`, `enforce-dispatch-gate.sh` 행 추가. 환경변수 표에 `SKIP_DISPATCH_GATE`, `DISABLE_DISPATCH_GATE_HOOK`, (S1 의 `SKIP_COMMIT_ADVISOR_GATE` 등은 S1 이 추가) 추가.
- `README.md`: 하네스 가드 섹션 + 환경변수 표에 두 env 추가.

## 검증 (완료 전 필수)
```bash
bash tests/enforce_dispatch_gate.sh                  # PASS
python3 -c "import json;json.load(open('hooks/hooks.json'))"
python3 -c "import json;json.load(open('.claude/settings.json'))"
bash tests/finish_plan_dev_cmux_cleanup.test.sh      # 회귀 없음
```
자가검증: `grep -q plan-dev-plan-approved hooks/enforce-dispatch-gate.sh && grep -q PostToolUse hooks/hooks.json && grep -q enforce-dispatch-gate hooks/hooks.json`.

## 커밋
`DOC_IMPACT=updated git commit -m "feat: ExitPlanMode 승인 전 dispatch 차단하는 게이트 추가"`
