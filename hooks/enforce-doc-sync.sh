#!/usr/bin/env bash
# PreToolUse hook (matcher: Bash) — `git commit` 직전 검사:
# 모든 commit 에 DOC 영향 평가를 강제한다. 차단하는 게 아니라,
# 사용자/AI 가 매번 "이 변경이 README.md / CLAUDE.md 에 영향이 있는가?"
# 를 한 번 의식적으로 판단하도록 만든다.
#
# 사용 (커밋 명령 prefix 로 DOC_IMPACT 환경변수 명시):
#
#   DOC_IMPACT=none git commit -m "..."
#       → "이 변경은 사용법/인터페이스/아키텍처에 영향 없음" 판단. 통과.
#
#   DOC_IMPACT=updated git commit -m "..."
#       → README.md 또는 CLAUDE.md 를 함께 업데이트해 staged 했음.
#         hook 이 staged 여부를 검증한 뒤 통과. 미반영이면 차단.
#
#   (DOC_IMPACT 미지정)
#       → 차단. stderr 에 git diff 요약 + 판단 요청 메시지 출력.
#         AI/사용자가 보고 둘 중 하나로 결정 후 재커밋.
#
# 1회 우회 (command 문자열에 포함):
#   SKIP_DOC_SYNC=1 git commit -m "..."
#
# 가드 자체 비활성화:
#   export DISABLE_DOC_SYNC_HOOK=1

set -u

[ "${DISABLE_DOC_SYNC_HOOK:-0}" = "1" ] && exit 0

payload=$(cat)
tool=$(printf '%s' "$payload" | jq -r '.tool_name // empty' 2>/dev/null || echo "")
[ "$tool" = "Bash" ] || exit 0

command=$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null || echo "")
if ! printf '%s' "$command" | grep -qE '(^|[[:space:];|&])git[[:space:]]+commit([[:space:]]|$)'; then
  exit 0
fi

git rev-parse --git-dir > /dev/null 2>&1 || exit 0

# R6: command 문자열에 SKIP_DOC_SYNC=1 포함 시 1회 통과 (README 광고 우회 구현)
if printf '%s' "$command" | grep -qE '(^|[[:space:]])SKIP_DOC_SYNC=1([[:space:]]|$)'; then
  exit 0
fi

# command 문자열에서 DOC_IMPACT 추출 (prefix 형태 권장)
doc_impact=$(printf '%s' "$command" | grep -oE 'DOC_IMPACT=[a-zA-Z_-]+' | head -1 | cut -d= -f2)

case "$doc_impact" in
  none)
    exit 0
    ;;
  updated)
    staged=$(git diff --cached --name-only 2>/dev/null)
    if printf '%s\n' "$staged" | grep -qE '(^|/)(README\.md|CLAUDE\.md)$'; then
      exit 0
    fi
    cat >&2 <<'MSG'
⛔ DOC_IMPACT=updated 선언했지만 README.md / CLAUDE.md 가 staged 되어 있지 않음.

다음 중 하나로 재시도:
  • 실제로 문서를 업데이트했으면: git add README.md (또는 CLAUDE.md) 후 재커밋
  • 사실 문서 변경 불필요하면: DOC_IMPACT=none git commit ...
MSG
    exit 2
    ;;
  "")
    # 미지정 → 판단 강제
    staged=$(git diff --cached --name-only 2>/dev/null)
    [ -z "$staged" ] && exit 0  # staged 없으면 어차피 commit 자체가 실패하니 통과

    # 변경 요약 만들기
    summary=$(git diff --cached --stat 2>/dev/null | tail -n +1)

    cat >&2 <<MSG
⛔ DOC 영향 평가 필요 — commit 차단됨.

변경 요약:
$summary

이번 변경이 사용법 / 인터페이스 / 아키텍처에 영향이 있는지 판단 후 다음 중 하나로 재시도:

  • 영향 없음 (내부 fix·refactor·테스트 등):
        DOC_IMPACT=none git commit -m "..."

  • 영향 있음 (먼저 README.md / CLAUDE.md 업데이트 → staged):
        git add README.md CLAUDE.md
        DOC_IMPACT=updated git commit -m "..."

가드 자체를 끄려면: export DISABLE_DOC_SYNC_HOOK=1
MSG
    exit 2
    ;;
  *)
    printf '%s\n' "⛔ DOC_IMPACT='$doc_impact' 은 허용되지 않음. 'none' 또는 'updated' 만 가능." >&2
    exit 2
    ;;
esac
