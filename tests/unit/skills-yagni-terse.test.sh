#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
pass=0; fail=0

check() {
  local desc="$1"; shift
  if eval "$@" &>/dev/null; then
    echo "PASS: $desc"; pass=$((pass+1))
  else
    echo "FAIL: $desc"; fail=$((fail+1))
  fi
}

# skills/yagni/SKILL.md 존재
check "skills/yagni/SKILL.md exists" "test -f '$REPO_ROOT/skills/yagni/SKILL.md'"

# skills/terse-output/SKILL.md 존재
check "skills/terse-output/SKILL.md exists" "test -f '$REPO_ROOT/skills/terse-output/SKILL.md'"

# frontmatter name: yagni
check "yagni name matches dir" "grep -q '^name: yagni$' '$REPO_ROOT/skills/yagni/SKILL.md'"

# frontmatter name: terse-output
check "terse-output name matches dir" "grep -q '^name: terse-output$' '$REPO_ROOT/skills/terse-output/SKILL.md'"

# description 존재 (빈값 아님)
check "yagni description non-empty" \
  "grep -E '^description: .+' '$REPO_ROOT/skills/yagni/SKILL.md'"

check "terse-output description non-empty" \
  "grep -E '^description: .+' '$REPO_ROOT/skills/terse-output/SKILL.md'"

# agents/implementor.md YAGNI 참조
check "implementor.md references YAGNI" \
  "grep -qi 'yagni\|필요성' '$REPO_ROOT/agents/implementor.md'"

echo ""
echo "Results: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
