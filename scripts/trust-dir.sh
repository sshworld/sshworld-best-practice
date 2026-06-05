#!/usr/bin/env bash
# trust-dir.sh — 자식 worktree 경로를 ~/.claude.json 의 hasTrustDialogAccepted 에 시딩.
# cross-machine bypass 자동화 — dispatch-slice-pane.sh 가 worktree launch 직전 호출.
#
# 사용: trust-dir.sh <abs-dir>
#
# 동작:
#   ~/.claude.json (또는 CBP_CLAUDE_CONFIG) 에:
#     .hasCompletedOnboarding = true
#     .projects[<abs-dir>].hasTrustDialogAccepted = true
#   기존 키(다른 프로젝트, 기타 top-level 키) 는 모두 보존(merge).
#   config 없으면 '{}' 로 신규 생성. 기존 있으면 .bak 1회 백업.
#   tmp 파일 → mv 원자적 write.
#
# 환경변수:
#   CBP_CLAUDE_CONFIG   config 경로 override (기본: ~/.claude.json). 테스트 mock 에 사용.
#   _TRUST_DIR_NO_JQ=1  jq 미설치 흉내 (테스트 훅) — exit 0 + stderr 경고.
#
# 우회: dispatch-slice-pane.sh 의 SKIP_DISPATCH_TRUST=1 (이 스크립트 자체 호출 안 됨).
# jq 부재: conservative exit 0 — dispatch 흐름 안 깨뜨림.

set -uo pipefail

die() { echo "trust-dir: $*" >&2; exit 2; }

TARGET="${1:-}"
[ -z "$TARGET" ] && die "abs-dir 인자 필요 (usage: trust-dir.sh <abs-dir>)"

CONFIG="${CBP_CLAUDE_CONFIG:-$HOME/.claude.json}"

# jq 미설치(또는 테스트 훅) 시 conservative exit 0
if [ "${_TRUST_DIR_NO_JQ:-0}" = "1" ] || ! command -v jq > /dev/null 2>&1; then
  echo "trust-dir: jq 미설치 — trust 시딩 생략 (cross-machine 에서 trust 다이얼로그 수동 확인 필요)" >&2
  exit 0
fi

# config 없으면 빈 객체로 시작, 있으면 .bak 백업
if [ ! -f "$CONFIG" ]; then
  BASE='{}'
else
  BASE=$(cat "$CONFIG")
  cp "$CONFIG" "${CONFIG}.bak" 2>/dev/null || true
fi

# tmp → mv 원자적 write
TMP=$(mktemp "${CONFIG}.tmp.XXXXXX")
trap 'rm -f "$TMP"' EXIT

printf '%s' "$BASE" | jq \
  --arg dir "$TARGET" \
  '.hasCompletedOnboarding = true | .projects[$dir].hasTrustDialogAccepted = true' \
  > "$TMP" || die "jq 처리 실패"

mkdir -p "$(dirname "$CONFIG")"
mv "$TMP" "$CONFIG"

echo "trusted $TARGET"
