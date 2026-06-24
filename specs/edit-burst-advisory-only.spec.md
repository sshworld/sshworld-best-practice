# Spec — Edit-burst hook strict off + 임계치 5 (S2)

## 목적

cmux `track-cmux-edit-burst.sh` hook 의 strict 차단 종결. **advisory only** + 임계치 2→5.

## 산출 파일

1. `.claude/settings.json` — PreToolUse Write|Edit hook command 의 inline `CMUX_EDIT_BURST_STRICT=1` 제거
2. `.claude/hooks/track-cmux-edit-burst.sh` — 디폴트 임계치 `THRESHOLD:-2` → `:-5`
3. `tests/track_cmux_edit_burst_strict_default.sh` — 시나리오 갱신

## 1. `.claude/settings.json`

L79 현재:
```json
"command": "CMUX_EDIT_BURST_STRICT=1 $CLAUDE_PROJECT_DIR/.claude/hooks/track-cmux-edit-burst.sh"
```

변경:
```json
"command": "$CLAUDE_PROJECT_DIR/.claude/hooks/track-cmux-edit-burst.sh"
```

= inline `CMUX_EDIT_BURST_STRICT=1` 완전 제거. strict 디폴트 off (사용자가 명시 set 시만 차단).

## 2. `.claude/hooks/track-cmux-edit-burst.sh`

L51 현재:
```bash
THRESHOLD="${CMUX_EDIT_BURST_THRESHOLD:-2}"
```

변경:
```bash
THRESHOLD="${CMUX_EDIT_BURST_THRESHOLD:-5}"
```

= 디폴트 임계치 2→5. 부모 5 Edit 까지 정상, 6번째부터 stderr advisory.

advisory 메시지 (L56~67) 그대로 유지. strict 분기 (L70~74) 그대로 유지 (env 로 명시 set 시만 작동).

## 3. `tests/track_cmux_edit_burst_strict_default.sh`

기존 5 시나리오 중 갱신/추가:

**갱신**:
- `t_settings_inline_strict` → `t_settings_no_inline_strict`
  ```bash
  t_settings_no_inline_strict() {
    # settings.json hook command 에 CMUX_EDIT_BURST_STRICT=1 inline 없음
    ! grep -F 'CMUX_EDIT_BURST_STRICT=1' "$REPO/.claude/settings.json"
  }
  ```
- `t_hook_threshold_default_2` → `t_hook_threshold_default_5`
  ```bash
  t_hook_threshold_default_5() {
    grep -F 'CMUX_EDIT_BURST_THRESHOLD:-5' "$REPO/.claude/hooks/track-cmux-edit-burst.sh" >/dev/null
  }
  ```

**기존 유지**:
- `t_skip_advisory_message` (advisory 메시지 그대로)
- `t_hook_skips_in_child_worktree` (자식 worktree skip — 변경 없음)

**갱신**:
- `t_hook_active_in_main_worktree` — strict env 없이 부모에서 6회째 advisory exit 0 검증:
  ```bash
  t_hook_advisory_only_default() {
    local tmp=$(mktemp -d)
    local fake_repo=$tmp/repo
    mkdir -p $fake_repo
    git -C $fake_repo init -q
    git -C $fake_repo commit --allow-empty -q -m init 2>/dev/null
    local count_file=$tmp/burst.count
    echo 5 > $count_file  # 이미 5
    local payload='{"tool_name":"Edit"}'
    CMUX_WORKSPACE_ID=test-ws \
    CBP_BURST_FILE=$count_file \
      bash -c "cd $fake_repo && printf '%s' '$payload' | $REPO/.claude/hooks/track-cmux-edit-burst.sh" 2>/dev/null
    local exit_code=$?
    local after_count=$(cat $count_file)
    rm -rf $tmp
    # 6회째: advisory (stderr) + exit 0 (차단 아님)
    [ "$exit_code" = "0" ] && [ "$after_count" = "6" ]
  }
  ```

**추가**:
- `t_hook_pass_under_threshold` — 부모에서 4회까지 silently pass:
  ```bash
  t_hook_pass_under_threshold() {
    local tmp=$(mktemp -d)
    local fake_repo=$tmp/repo
    mkdir -p $fake_repo
    git -C $fake_repo init -q
    git -C $fake_repo commit --allow-empty -q -m init 2>/dev/null
    local count_file=$tmp/burst.count
    echo 3 > $count_file
    local payload='{"tool_name":"Edit"}'
    CMUX_WORKSPACE_ID=test-ws \
    CBP_BURST_FILE=$count_file \
      bash -c "cd $fake_repo && printf '%s' '$payload' | $REPO/.claude/hooks/track-cmux-edit-burst.sh" 2>/dev/null
    local exit_code=$?
    local after_count=$(cat $count_file)
    rm -rf $tmp
    # 4회: 임계치 5 미만 → 메시지 없이 exit 0
    [ "$exit_code" = "0" ] && [ "$after_count" = "4" ]
  }
  ```

**추가**:
- `t_hook_strict_env_still_blocks` — `CMUX_EDIT_BURST_STRICT=1` env 명시 시 차단 보존 (회귀 가드):
  ```bash
  t_hook_strict_env_still_blocks() {
    local tmp=$(mktemp -d)
    local fake_repo=$tmp/repo
    mkdir -p $fake_repo
    git -C $fake_repo init -q
    git -C $fake_repo commit --allow-empty -q -m init 2>/dev/null
    local count_file=$tmp/burst.count
    echo 5 > $count_file
    local payload='{"tool_name":"Edit"}'
    CMUX_WORKSPACE_ID=test-ws \
    CBP_BURST_FILE=$count_file \
    CMUX_EDIT_BURST_STRICT=1 \
      bash -c "cd $fake_repo && printf '%s' '$payload' | $REPO/.claude/hooks/track-cmux-edit-burst.sh" 2>/dev/null
    local exit_code=$?
    rm -rf $tmp
    # strict env 명시 → exit 2
    [ "$exit_code" = "2" ]
  }
  ```

run 라인:
```bash
run "settings.json inline strict 부재" t_settings_no_inline_strict
run "hook 디폴트 임계치 5" t_hook_threshold_default_5
run "SKIP 메시지 권고 보존" t_skip_advisory_message
run "자식 worktree skip" t_hook_skips_in_child_worktree
run "임계치 미만 silently pass" t_hook_pass_under_threshold
run "임계치 초과 advisory only (차단 없음)" t_hook_advisory_only_default
run "STRICT env 명시 시 차단 보존" t_hook_strict_env_still_blocks
```

## TDD

- Red: 갱신 테스트가 현재 settings/hook 상태에서 FAIL (strict inline 존재, threshold 2)
- Green: settings.json + hook 수정 → 전 시나리오 PASS
- Refactor: 없음 (소규모 변경)

## 완료 조건

```bash
! grep -q "CMUX_EDIT_BURST_STRICT=1" .claude/settings.json
grep -q "CMUX_EDIT_BURST_THRESHOLD:-5" .claude/hooks/track-cmux-edit-burst.sh
bash tests/track_cmux_edit_burst_strict_default.sh
bash -n .claude/hooks/track-cmux-edit-burst.sh
```

모두 PASS 시 `✅ S2 done` 출력.
