# Spec: install.sh union 정책 hook 파일명 dedup (S1, feat/install-hook-filename-dedup)

## 목표

`install.sh` 의 jq merge 식 dedup key 를 `.command` 전체 문자열 → `hooks/<name>.sh` 파일명으로 변경. 같은 hook 파일명에서 repo 가 winner (STRICT/ENV prepend 등 source of truth). 사용자 비-겹침 customize 보존.

문제 케이스: 기존 글로벌 settings.json 에 `$HOME/.claude/hooks/track-cmux-edit-burst.sh` (plain) 가 있고, repo 가 `CMUX_EDIT_BURST_STRICT=1 $HOME/.claude/hooks/track-cmux-edit-burst.sh` 를 배포. 현 정책은 string dedup 이라 둘 다 union 결과에 보존됨 (dup). → hook 파일명 기준 dedup + repo winner 로 fix.

## 산출 파일

### 수정
1. `install.sh` — line 219-220 의 jq dedup 식 교체
2. `tests/install_merge_hooks.sh` — T7 + T8 신규 케이스 추가
3. `README.md` — hook merge 정책 설명 1줄 갱신

## TDD 순서

### Red: tests/install_merge_hooks.sh

기존 T6 (`t6_other_top`) 뒤에 T7, T8 추가. `run "T6 ..." t6_other_top` 라인 다음 `echo "PASS=..."` 직전에 다음 함수 정의 + `run` 호출 2줄 삽입:

```bash
# T7: STRICT prepend dedup — 기존 plain hook + repo STRICT=1 inline 시, repo 가 winner (1라인만 + STRICT 포함)
t7_strict_prepend_dedup() {
  local TMP; TMP=$(mktemp -d); trap "rm -rf $TMP" RETURN
  mk_existing_settings "$TMP" '{
    "hooks": {
      "PreToolUse": [
        { "matcher": "Write|Edit",
          "hooks": [{"type":"command","command":"$HOME/.claude/hooks/track-cmux-edit-burst.sh"}] }
      ]
    }
  }'
  HOME="$TMP" "$REPO/install.sh" user > /dev/null 2>&1 || return 1
  local count
  count=$(jq '[.hooks.PreToolUse[] | select(.matcher == "Write|Edit") | .hooks[] | select(.command | test("track-cmux-edit-burst\\.sh"))] | length' "$TMP/.claude/settings.json")
  [ "$count" -eq 1 ] || return 1
  jq -e '.hooks.PreToolUse[] | select(.matcher == "Write|Edit") | .hooks[] | select(.command | test("track-cmux-edit-burst\\.sh")) | .command | contains("CMUX_EDIT_BURST_STRICT=1")' \
    "$TMP/.claude/settings.json" >/dev/null || return 1
  return 0
}

# T8: 비-hook custom 명령 보존 — hooks/ 경로 아닌 사용자 custom 은 그대로
t8_custom_non_hook_preserved() {
  local TMP; TMP=$(mktemp -d); trap "rm -rf $TMP" RETURN
  mk_existing_settings "$TMP" '{
    "hooks": {
      "PreToolUse": [
        { "matcher": "Write|Edit",
          "hooks": [{"type":"command","command":"my-custom-bash-script.sh"}] }
      ]
    }
  }'
  "$REPO/install.sh" project "$TMP" > /dev/null 2>&1 || return 1
  jq -e '[.hooks.PreToolUse[] | select(.matcher == "Write|Edit") | .hooks[] | .command] | index("my-custom-bash-script.sh") | . != null' \
    "$TMP/.claude/settings.json" >/dev/null || return 1
  return 0
}

run "T7 STRICT prepend dedup (repo winner)" t7_strict_prepend_dedup
run "T8 비-hook custom 명령 보존" t8_custom_non_hook_preserved
```

### Green: install.sh

**대상**: line 219-220 (현 jq merge 식 안 핵심 두 줄)

**Before**:
```jq
| ($cur_hooks | map(.command)) as $cur_cmds
| $cur_hooks + ($new_hooks | map(select(.command as $c | $cur_cmds | index($c) | not)))
```

**After** (hook 파일명 기준 dedup + repo winner):
```jq
| ($new_hooks | map((.command | capture("hooks/(?<n>[a-zA-Z0-9_.-]+\\.sh)"; "x")?.n) // .command)) as $new_keys
| ($cur_hooks | map(select(
    ((.command | capture("hooks/(?<n>[a-zA-Z0-9_.-]+\\.sh)"; "x")?.n) // .command) as $k
    | $new_keys | index($k) | not
  ))) + $new_hooks
```

핵심 변경:
- dedup key = `hooks/<name>.sh` 캡처 + `.command` fallback
- 순서 reverse: 기존 (cur) 중 repo 와 안 겹치는 것 keep + repo (new) 전체 append → repo winner

주변 jq 식 (`($cur_hooks | map(.hooks // []) | add) // []` 등) 은 그대로 유지.

### README.md 갱신

기존 hook merge 정책 설명 부분 (검색: `command 단위` 또는 `union` 키워드). 1줄 교체:

**After**:
> `settings.json` 의 `hooks` 는 **matcher / hook 파일명 단위 union** — 같은 hook 파일명 (`hooks/<name>.sh`) 이면 repo 가 winner (STRICT/ENV prepend 등 source of truth). 비-겹침 customize 는 보존.

실제 README 의 정확한 문구는 구현 시 grep 으로 위치 찾아 갱신.

## Verification

```bash
bash tests/install_merge_hooks.sh         # T1~T8 8 케이스 모두 PASS
bash tests/install_dry_run.sh             # 회귀
bash tests/install_user_scope_braces.sh   # 회귀
bash tests/install_user_scope_session_idempotent.sh  # 회귀
bash tests/docs_sync.sh                   # README/CLAUDE 동기 검증

python3 -m json.tool .claude/settings.json > /dev/null && echo "JSON OK"
bash -n install.sh && echo "install.sh syntax OK"
```

모두 PASS 후 `✅ install-hook-filename-dedup`. 실패 시 `❌ <원인>`.

## DOC_IMPACT

`updated` — README.md 갱신 포함.

## 완료 조건
1. install.sh line 219-220 jq 식 교체
2. tests/install_merge_hooks.sh T7 + T8 추가, 8 케이스 모두 PASS
3. README.md hook merge 정책 1줄 갱신
4. 회귀 4종 PASS, JSON 유효, bash syntax OK
