# Spec: cmux Edit/Write burst hook strict default + 임계치 2 (S1, feat/cmux-edit-burst-strict-default)

## 목표

cmux 환경에서 직접 Edit/Write 누적 시 hook 이 advisory 만 내고 통과 → 모델이 무시. **본 repo settings.json 한정** 으로 hook 을 strict 모드 (exit 2 차단) 디폴트로 + 임계치 3→2 로 강화. 우회 가능 (SKIP/DISABLE env). hook 파일 자체 디폴트는 unset 유지 (다른 환경에 영향 없음).

선례: `enforce-cmux-context.sh` 가 `CMUX_CONTEXT_HOOK_STRICT=1` 을 settings.json hook command 에 inline prepend (README.md:303).

## 산출 파일

### 수정
1. `.claude/hooks/track-cmux-edit-burst.sh` — 디폴트 임계치 3→2, SKIP 메시지에 "의식적으로 검토" 권고 추가
2. `.claude/settings.json` — PreToolUse `Write|Edit` 매처의 track-cmux-edit-burst.sh command 라인에 `CMUX_EDIT_BURST_STRICT=1 ` inline prepend
3. `CLAUDE.md` — 파일별 책임 분리 표의 `track-cmux-edit-burst.sh` 줄 임계치 3→2 갱신, 환경변수 표의 `CMUX_EDIT_BURST_THRESHOLD` 디폴트 3→2 갱신
4. `README.md` — 하네스 가드 섹션의 track-cmux-edit-burst 설명 + env 표의 임계치 디폴트 갱신 + "본 repo settings.json 에 STRICT=1 inline" 1줄 추가

### 신규
5. `tests/track_cmux_edit_burst_strict_default.sh` — TDD Red 테스트 3 케이스

## TDD 순서

### Red: tests/track_cmux_edit_burst_strict_default.sh

```bash
#!/usr/bin/env bash
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0; FAILED=()
run() { local name="$1"; shift; if "$@" >/dev/null 2>&1; then echo "✔ $name"; PASS=$((PASS+1)); else echo "✘ $name"; FAIL=$((FAIL+1)); FAILED+=("$name"); fi; }

t_settings_inline_strict() {
  jq -e '
    .hooks.PreToolUse[]
    | select(.matcher == "Write|Edit")
    | .hooks[]
    | select(.command | contains("track-cmux-edit-burst.sh"))
    | .command
    | contains("CMUX_EDIT_BURST_STRICT=1")
  ' "$REPO/.claude/settings.json" >/dev/null
}

t_hook_threshold_default_2() {
  grep -F 'CMUX_EDIT_BURST_THRESHOLD:-2' "$REPO/.claude/hooks/track-cmux-edit-burst.sh" >/dev/null
}

t_skip_advisory_message() {
  grep -F "의식적으로 검토" "$REPO/.claude/hooks/track-cmux-edit-burst.sh" >/dev/null
}

run "settings.json hook command 라인에 CMUX_EDIT_BURST_STRICT=1 inline" t_settings_inline_strict
run "hook 파일 디폴트 임계치 2" t_hook_threshold_default_2
run "SKIP 메시지에 '의식적으로 검토' 권고" t_skip_advisory_message

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && echo "✅ all pass" || { echo "❌ FAILED: ${FAILED[*]}"; exit 1; }
```

`chmod +x` 적용.

### Green

#### (a) `.claude/hooks/track-cmux-edit-burst.sh`

**변경 1** — line 42 부근, 임계치 디폴트:
```bash
# Before
THRESHOLD="${CMUX_EDIT_BURST_THRESHOLD:-3}"
# After
THRESHOLD="${CMUX_EDIT_BURST_THRESHOLD:-2}"
```

**변경 2** — 우회 안내 메시지 (HEREDOC 끝부분, line 53-56 부근). 기존:
```
우회:
  SKIP_CMUX_EDIT_BURST=1         — 1회 우회
  DISABLE_CMUX_EDIT_BURST_HOOK=1 — 영구 비활성
  CMUX_EDIT_BURST_THRESHOLD=N    — 임계치 override
  CMUX_EDIT_BURST_STRICT=1       — 차단 모드 활성화
```

다음 한 줄을 우회 안내 위에 삽입 (HEREDOC 본문 안):
```
   ↳ 우회하기 전: dispatch 선택지 (cmux-pane.sh launch) 를 의식적으로 검토했는지 확인.

우회:
  ...
```

#### (b) `.claude/settings.json`

PreToolUse `Write|Edit` 매처의 `track-cmux-edit-burst.sh` 호출 라인:
```json
// Before
"command": "$CLAUDE_PROJECT_DIR/.claude/hooks/track-cmux-edit-burst.sh"
// After
"command": "CMUX_EDIT_BURST_STRICT=1 $CLAUDE_PROJECT_DIR/.claude/hooks/track-cmux-edit-burst.sh"
```

JSON 한 줄 형식 유지.

#### (c) `CLAUDE.md`

`.claude/hooks/track-cmux-edit-burst.sh` 줄 (line ~58):
- "기본 임계치 3" → "기본 임계치 2"

환경변수 표 `CMUX_EDIT_BURST_THRESHOLD` 행:
- 디폴트 컬럼 `3` → `2`

#### (d) `README.md`

env 표의 `CMUX_EDIT_BURST_THRESHOLD` 디폴트 갱신 (3→2). 하네스 가드 섹션의 `track-cmux-edit-burst` 설명에 다음 1줄 추가:
```
- **본 repo 의 settings.json**: `CMUX_EDIT_BURST_STRICT=1` 을 hook command 에 inline 으로 강제 → 본 repo 환경에서 임계치 도달 시 차단(exit 2). 우회는 `SKIP_CMUX_EDIT_BURST=1` / `DISABLE_CMUX_EDIT_BURST_HOOK=1`.
```

## Verification

```bash
# 신규
bash tests/track_cmux_edit_burst_strict_default.sh

# 회귀
bash tests/install_dry_run.sh
bash tests/install_merge_hooks.sh
python3 -m json.tool .claude/settings.json > /dev/null && echo "JSON OK"
bash -n .claude/hooks/track-cmux-edit-burst.sh

# DOC sync
bash tests/docs_sync.sh
```

모두 PASS 후 `✅ S1 complete — feat/cmux-edit-burst-strict-default`. 실패 시 `❌ <원인>`.

## DOC_IMPACT

`updated` — CLAUDE.md + README.md 변경 포함.

## 완료 조건
1. 위 5 파일 변경/신규
2. tests/track_cmux_edit_burst_strict_default.sh 3 케이스 PASS
3. install_dry_run + install_merge_hooks + docs_sync 회귀 PASS
4. settings.json JSON 유효
5. hook bash syntax 유효
