# Spec: SessionStart inline 명령 경로 일관화 (S1, fix/session-start-path-consistency)

## 목표
repo `.claude/settings.json` 의 SessionStart inline 명령의 두 부분 (호출 경로 + 표시 메시지) 을 `${CLAUDE_PROJECT_DIR}/scripts/...` 단일 형태로 통일.

**효과**: user-scope gsub 변환 후 `$HOME/scripts/...` 로 정규화 → 글로벌 settings 의 기존 form 과 문자열 일치 → install.sh 의 matcher/command union dedup 성공 → 글로벌 재배포 idempotent.

## 산출 파일

### 수정
1. `.claude/settings.json` — SessionStart `[0].hooks[0].command` 한 줄

### 신규
2. `tests/install_user_scope_session_idempotent.sh` — TDD

## TDD 순서

### Red: tests/install_user_scope_session_idempotent.sh

테스트는 두 가지 검증:
- (a) `HOME=$TMP install.sh user` 두 번 실행 → SessionStart hooks 배열 길이 일정 (idempotent)
- (b) 변환된 inline command 가 `$HOME/scripts/detect-pane-env.sh` 형태 포함 (정규화 결과 확인)

```bash
#!/usr/bin/env bash
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0; FAILED=()
run() { local name="$1"; shift; if "$@" >/dev/null 2>&1; then echo "✔ $name"; PASS=$((PASS+1)); else echo "✘ $name"; FAIL=$((FAIL+1)); FAILED+=("$name"); fi; }

t_idempotent() {
  local TMP; TMP=$(mktemp -d) || return 1
  trap "rm -rf $TMP" RETURN
  HOME="$TMP" "$REPO/install.sh" user >/dev/null 2>&1 || return 1
  local N1; N1=$(jq '.hooks.SessionStart[0].hooks | length' "$TMP/.claude/settings.json")
  HOME="$TMP" "$REPO/install.sh" user >/dev/null 2>&1 || return 1
  local N2; N2=$(jq '.hooks.SessionStart[0].hooks | length' "$TMP/.claude/settings.json")
  [ "$N1" = "$N2" ]
}

t_user_scope_normalized() {
  local TMP; TMP=$(mktemp -d) || return 1
  trap "rm -rf $TMP" RETURN
  HOME="$TMP" "$REPO/install.sh" user >/dev/null 2>&1 || return 1
  # inline command 안에 "$HOME/scripts/detect-pane-env.sh" 패턴이 있어야 (단순화 결과)
  jq -e '.hooks.SessionStart[0].hooks[].command | contains("$HOME/scripts/detect-pane-env.sh")' \
     "$TMP/.claude/settings.json" >/dev/null 2>&1
}

run "user-scope SessionStart idempotent (2회 install 길이 동일)" t_idempotent
run "변환 결과가 \$HOME/scripts/ 형태" t_user_scope_normalized

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && echo "✅ all pass" || { echo "❌ FAILED: ${FAILED[*]}"; exit 1; }
```

### Green: .claude/settings.json 변경

**대상**: SessionStart hooks 배열의 첫 번째 항목 (matcher="") 의 첫 번째 hook 의 command. 현재 line 118 부근.

**Before** (한 줄, 가독성 위해 줄바꿈 표시):
```
if git rev-parse --git-dir > /dev/null 2>&1; then
  echo '=== 진행 중 worktree ===';
  git worktree list;
  echo '';
  echo '=== 미커밋 변경 ===';
  git status -s;
fi;
_env=$(bash "${CLAUDE_PROJECT_DIR}/.claude/../scripts/detect-pane-env.sh" 2>/dev/null || echo unknown);
if [ "$_env" = "default" ]; then
  echo "=== 멀티플렉서: default (driver: subagent 모드 사용) ===";
else
  echo "=== 멀티플렉서: $_env (driver: scripts/${_env}-pane.sh) ===";
fi
```

**After** (두 부분 통일 — `${CLAUDE_PROJECT_DIR}/scripts/...`):
```
if git rev-parse --git-dir > /dev/null 2>&1; then
  echo '=== 진행 중 worktree ===';
  git worktree list;
  echo '';
  echo '=== 미커밋 변경 ===';
  git status -s;
fi;
_env=$(bash "${CLAUDE_PROJECT_DIR}/scripts/detect-pane-env.sh" 2>/dev/null || echo unknown);
if [ "$_env" = "default" ]; then
  echo "=== 멀티플렉서: default (driver: subagent 모드 사용) ===";
else
  echo "=== 멀티플렉서: $_env (driver: ${CLAUDE_PROJECT_DIR}/scripts/${_env}-pane.sh) ===";
fi
```

핵심 변경 두 곳:
- `${CLAUDE_PROJECT_DIR}/.claude/../scripts/detect-pane-env.sh` → `${CLAUDE_PROJECT_DIR}/scripts/detect-pane-env.sh`
- `driver: scripts/${_env}-pane.sh` → `driver: ${CLAUDE_PROJECT_DIR}/scripts/${_env}-pane.sh`

JSON 한 줄 형식 유지 — Edit 로 정확히 두 substring 만 교체.

## Verification (구현 완료 후)
```bash
# 신규
bash tests/install_user_scope_session_idempotent.sh

# 회귀
bash tests/install_dry_run.sh
bash tests/install_merge_hooks.sh
bash tests/install_user_scope_braces.sh
bash tests/settings_perms.sh

# JSON 유효
python3 -m json.tool .claude/settings.json > /dev/null && echo "JSON OK"
```

모두 PASS 후 `✅ S1 complete — fix/session-start-path-consistency`. 실패 시 `❌ <원인>`.

## 완료 조건
1. .claude/settings.json line 118 의 두 substring 통일
2. tests/install_user_scope_session_idempotent.sh 신규 2 케이스 PASS
3. 회귀 4 종 PASS
4. JSON 유효
