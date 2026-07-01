#!/usr/bin/env bash
# release.sh 단위 테스트.
# 순수 함수(bump_version_json / group_commits_by_type) + dry-run 부작용 0 검증.
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RELEASE="$REPO/scripts/release.sh"
PASS=0; FAIL=0; FAILED=()
run() { local name="$1"; shift; if "$@" >/dev/null 2>&1; then echo "✔ $name"; PASS=$((PASS+1)); else echo "✘ $name"; FAIL=$((FAIL+1)); FAILED+=("$name"); fi; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

# 함수만 source (sourcing guard 로 main 실행 안 됨).
source "$RELEASE"

t_bump_version_json() {
  local f="$TMP/plugin.json"
  printf '{"version":"1.0.0"}' > "$f"
  bump_version_json "$f" "2.0.0"
  grep -q '"version": "2.0.0"' "$f"
}

t_group_commits_by_type() {
  local log out
  log=$'aaa feat: 새기능\nbbb fix: 버그\nccc docs: 문서'
  out="$(group_commits_by_type "$log")"
  echo "$out" | grep -q '### ✨ Feature' \
    && echo "$out" | grep -q '새기능' \
    && echo "$out" | grep -q '### 🐛 Fix' \
    && echo "$out" | grep -q '버그' \
    && echo "$out" | grep -q '### 📝 Docs' \
    && ! echo "$out" | grep -q 'feat:'
}

t_publish_dry_run() {
  local notes="$TMP/notes.md"
  printf '## v9.9.9 — 테스트\n\n내용\n' > "$notes"

  local plugin_json="$TMP/plugin.json" mkt_json="$TMP/marketplace.json"
  printf '{"version":"1.0.0"}' > "$plugin_json"
  printf '{"plugins":[{"name":"sshworld","version":"1.0.0"}]}' > "$mkt_json"

  local gh_mock="$TMP/mock_gh.sh" push_mock="$TMP/mock_push.sh"
  local gh_calls="$TMP/gh_calls" push_calls="$TMP/push_calls"
  rm -f "$gh_calls" "$push_calls"
  printf '#!/usr/bin/env bash\necho called >> "%s"\n' "$gh_calls" > "$gh_mock"; chmod +x "$gh_mock"
  printf '#!/usr/bin/env bash\necho called >> "%s"\n' "$push_calls" > "$push_mock"; chmod +x "$push_mock"

  local out
  out="$(RELEASE_DRY_RUN=1 GH_CMD="$gh_mock" GIT_PUSH_CMD="$push_mock" \
        RELEASE_PLUGIN_JSON="$plugin_json" RELEASE_MARKETPLACE_JSON="$mkt_json" \
        bash "$RELEASE" publish 9.9.9 "$notes" 2>&1)"

  echo "$out" | grep -q '\[dry-run\]' \
    && echo "$out" | grep -q 'sshworld--v9.9.9' \
    && [ ! -f "$gh_calls" ] \
    && [ ! -f "$push_calls" ] \
    && grep -q '"version":"1.0.0"' "$plugin_json"
}

t_backfill_dry_run() {
  # 9.9.9 사용 — 1.0.0 은 이 repo 의 실제 릴리즈 태그와 충돌해 skip 분기를 탐.
  local notes="$TMP/notes2.md"
  printf '## v9.9.9 — 백필\n' > "$notes"

  local gh_mock="$TMP/mock_gh2.sh" push_mock="$TMP/mock_push2.sh"
  local gh_calls="$TMP/gh_calls2" push_calls="$TMP/push_calls2"
  rm -f "$gh_calls" "$push_calls"
  printf '#!/usr/bin/env bash\necho called >> "%s"\n' "$gh_calls" > "$gh_mock"; chmod +x "$gh_mock"
  printf '#!/usr/bin/env bash\necho called >> "%s"\n' "$push_calls" > "$push_mock"; chmod +x "$push_mock"

  local out
  out="$(RELEASE_DRY_RUN=1 GH_CMD="$gh_mock" GIT_PUSH_CMD="$push_mock" \
        bash "$RELEASE" backfill 9.9.9 9b896ac "$notes" 2>&1)"

  echo "$out" | grep -q 'git tag sshworld--v9.9.9 9b896ac' \
    && echo "$out" | grep -q 'release create sshworld--v9.9.9' \
    && [ ! -f "$gh_calls" ] \
    && [ ! -f "$push_calls" ]
}

t_help() {
  bash "$RELEASE" --help >/dev/null 2>&1
}

run "bump_version_json (임시 json 치환)"        t_bump_version_json
run "group_commits_by_type (그룹핑+prefix 제거)" t_group_commits_by_type
run "publish dry-run (실제실행0, 버전파일불변)"   t_publish_dry_run
run "backfill dry-run (실제실행0)"               t_backfill_dry_run
run "--help exit0"                              t_help

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && echo "✅ all pass" || { echo "❌ FAILED: ${FAILED[*]}"; exit 1; }
