#!/usr/bin/env bash
# PreToolUse hook — production 파일 Write/Edit 전에 대응 테스트 파일 존재 확인.
#
# 동작 모드:
#   CLAUDE_TDD_STRICT=1  → 위반 시 차단(exit 2)
#   그 외                → 경고만 출력하고 통과(exit 0)
#
# 활성화 (plan-dev Phase 2 시작 시):
#   export CLAUDE_TDD_STRICT=1
# 비활성화:
#   unset CLAUDE_TDD_STRICT

set -u

payload=$(cat)
tool=$(printf '%s' "$payload" | jq -r '.tool_name // empty' 2>/dev/null || echo "")
file=$(printf '%s' "$payload" | jq -r '.tool_input.file_path // empty' 2>/dev/null || echo "")

# Write/Edit 외 도구는 통과
case "$tool" in
  Write|Edit) ;;
  *) exit 0 ;;
esac

# 경로 추정 실패 시 통과
[ -z "$file" ] && exit 0

# production 패턴 아니면 통과 (백엔드 일반 디렉토리들)
case "$file" in
  */src/main/*|*/lib/*|*/app/*|*/internal/*|*/pkg/*) ;;
  *) exit 0 ;;
esac

# 자기 자신이 테스트 파일이면 통과
case "$file" in
  *test*|*Test*|*spec*|*Spec*) exit 0 ;;
esac

# 대응 테스트 파일 검색
basename=$(basename "$file")
name="${basename%.*}"

found=$(find . -type f \
  \( -name "${name}Test.*" \
  -o -name "${name}Tests.*" \
  -o -name "test_${name}.*" \
  -o -name "${name}.test.*" \
  -o -name "${name}.spec.*" \
  -o -name "${name}_test.*" \) 2>/dev/null | head -1)

if [ -z "$found" ]; then
  msg="⛔ TDD 가드: '$file' 대응 테스트 파일 없음. Red 단계 먼저 작성 권장."
  if [ "${CLAUDE_TDD_STRICT:-0}" = "1" ]; then
    printf '%s\n' "$msg (STRICT 모드 — 차단)" >&2
    exit 2
  else
    printf '%s\n' "$msg (warning only — CLAUDE_TDD_STRICT=1 로 차단 활성화)" >&2
    exit 0
  fi
fi

exit 0
