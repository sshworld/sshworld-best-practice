#!/usr/bin/env bash
# install.sh — claude-best-practice 워크플로 설치 스크립트
#
# 사용:
#   ./install.sh                            # 인자 없이 실행 → 인터랙티브 메뉴
#   ./install.sh user                       # ~/.claude/ 에 설치 (글로벌)
#   ./install.sh project [TARGET_DIR]       # TARGET_DIR/.claude/ 에 설치 (기본: $PWD)
#   ./install.sh uninstall user
#   ./install.sh uninstall project [TARGET_DIR]
#
# 동작:
#   - commands/agents/skills/hooks 디렉토리의 파일을 복사. 기존 파일 있으면 .bak.<ts> 로 백업.
#   - settings.json 은 자동 병합하지 않고 settings.example.json 으로 복사.
#     기존 settings.json 이 있으면 사용자가 수동 병합 필요.
#   - hook 스크립트는 실행 권한(chmod +x) 유지.
#
# uninstall 동작:
#   - 본 repo 가 설치한 파일들만 삭제. .bak.* 파일은 그대로 둠.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$SCRIPT_DIR/.claude"
TS="$(date +%Y%m%d-%H%M%S)"

# 설치 대상 파일 목록 (SRC 기준 상대경로)
FILES=(
  "commands/plan-dev.md"
  "agents/implementor.md"
  "agents/verifier.md"
  "agents/reviewer.md"
  "agents/commit-advisor.md"
  "skills/fork/SKILL.md"
  "hooks/enforce-test-first.sh"
  "hooks/enforce-doc-sync.sh"
  "hooks/token-stats.sh"
)

usage() {
  cat <<USAGE
Usage:
  $0 user                       # ~/.claude/ 에 설치 (글로벌)
  $0 project [TARGET_DIR]       # TARGET_DIR/.claude/ 에 설치 (기본: \$PWD)
  $0 uninstall user
  $0 uninstall project [TARGET_DIR]
USAGE
  exit 1
}

resolve_dest() {
  local scope="$1"
  local target="${2:-$PWD}"
  case "$scope" in
    user)    echo "$HOME/.claude" ;;
    project) echo "$target/.claude" ;;
    *)       usage ;;
  esac
}

do_install() {
  local dest="$1"
  local scope="project"
  [ "$dest" = "$HOME/.claude" ] && scope="user"
  echo "📦 설치 대상: $dest (scope: $scope)"
  mkdir -p "$dest"

  for rel in "${FILES[@]}"; do
    local src_file="$SRC/$rel"
    local dest_file="$dest/$rel"

    if [ ! -f "$src_file" ]; then
      echo "  ⚠️  스킵 (소스 없음): $rel"
      continue
    fi

    mkdir -p "$(dirname "$dest_file")"

    if [ -f "$dest_file" ]; then
      local backup="$dest_file.bak.$TS"
      cp "$dest_file" "$backup"
      echo "  💾 백업: $backup"
    fi

    cp "$src_file" "$dest_file"

    # hook 스크립트는 실행 권한 부여
    case "$rel" in
      hooks/*.sh) chmod +x "$dest_file" ;;
    esac

    echo "  ✓ $rel"
  done

  # settings.json 별도 처리
  local settings_src="$SRC/settings.json"
  local settings_dest="$dest/settings.json"
  local settings_example="$dest/settings.example.json"

  if [ -f "$settings_src" ]; then
    # user scope 일 때 hook 경로 $CLAUDE_PROJECT_DIR → $HOME 변환
    local settings_processed="$settings_src"
    local tmp_created=""
    if [ "$scope" = "user" ]; then
      if ! command -v jq > /dev/null 2>&1; then
        echo "  ⚠️  jq 미설치 — settings.json hook 경로 변환 생략 (원본 복사)" >&2
      else
        tmp_created="$(mktemp)"
        jq '
          if has("hooks") then
            .hooks |= walk(
              if type == "object" and (.command? | type) == "string" then
                .command |= gsub("\\$CLAUDE_PROJECT_DIR"; "$HOME")
              else . end
            )
          else . end
        ' "$settings_src" > "$tmp_created"
        settings_processed="$tmp_created"
        echo "  🔧 user scope: hook 경로를 \$HOME/.claude/hooks/... 로 변환"
      fi
    fi

    if [ -f "$settings_dest" ]; then
      cp "$settings_processed" "$settings_example"
      echo "  📋 settings.example.json 복사 — 기존 settings.json 과 수동 병합 필요"
    else
      cp "$settings_processed" "$settings_dest"
      echo "  ✓ settings.json"
    fi

    [ -n "$tmp_created" ] && rm -f "$tmp_created"
  fi

  echo ""
  echo "✅ 설치 완료."
  if [ -f "$settings_example" ]; then
    echo ""
    echo "⚠️  settings.example.json 이 만들어졌습니다. 다음 키를 기존 settings.json 에 병합하세요:"
    echo "    - permissions.allow / permissions.deny"
    echo "    - hooks.PreToolUse / hooks.Stop / hooks.SessionStart"
  fi
}

do_uninstall() {
  local dest="$1"
  echo "🗑️  제거 대상: $dest"

  for rel in "${FILES[@]}"; do
    local f="$dest/$rel"
    if [ -f "$f" ]; then
      rm "$f"
      echo "  ✓ 삭제: $rel"
    fi
  done

  # 빈 디렉토리 정리 (실패해도 무시)
  for d in skills/fork hooks commands agents skills; do
    rmdir "$dest/$d" 2>/dev/null || true
  done

  echo ""
  echo "✅ 제거 완료."
  echo "ℹ️  settings.json / .bak.* 파일은 그대로 두었습니다 — 필요 시 수동 삭제."
}

interactive_menu() {
  cat <<'BANNER'
╔══════════════════════════════════════════════╗
║   claude-best-practice 설치 메뉴             ║
╚══════════════════════════════════════════════╝
BANNER
  echo ""
  echo "어디에 설치할까요?"
  echo ""
  local PS3=$'\n번호 선택: '
  local options=(
    "user 설치 (~/.claude/) — 모든 프로젝트에서 사용"
    "project 설치 (현재 디렉토리: $PWD)"
    "project 설치 (다른 디렉토리 지정)"
    "uninstall — user (~/.claude/)"
    "uninstall — project (현재 디렉토리: $PWD)"
    "취소"
  )
  local opt
  select opt in "${options[@]}"; do
    case "$REPLY" in
      1)
        do_install "$(resolve_dest user)"
        return 0 ;;
      2)
        do_install "$(resolve_dest project "$PWD")"
        return 0 ;;
      3)
        local target
        read -rp "설치할 디렉토리 경로: " target
        if [ -z "$target" ]; then
          echo "❌ 경로 미입력 — 취소"; return 1
        fi
        if [ ! -d "$target" ]; then
          echo "❌ 디렉토리 없음: $target"; return 1
        fi
        do_install "$(resolve_dest project "$target")"
        return 0 ;;
      4)
        do_uninstall "$(resolve_dest user)"
        return 0 ;;
      5)
        do_uninstall "$(resolve_dest project "$PWD")"
        return 0 ;;
      6)
        echo "취소됨."; return 0 ;;
      *)
        echo "잘못된 번호 — 1~6 중 선택." ;;
    esac
  done
}

# 메인
if [ $# -eq 0 ]; then
  interactive_menu
  exit $?
fi

case "$1" in
  user)
    dest=$(resolve_dest user)
    do_install "$dest"
    ;;
  project)
    dest=$(resolve_dest project "${2:-$PWD}")
    do_install "$dest"
    ;;
  uninstall)
    case "${2:-}" in
      user)
        dest=$(resolve_dest user)
        do_uninstall "$dest"
        ;;
      project)
        dest=$(resolve_dest project "${3:-$PWD}")
        do_uninstall "$dest"
        ;;
      *) usage ;;
    esac
    ;;
  *) usage ;;
esac
