#!/usr/bin/env bash
# release.sh — sshworld 플러그인 릴리즈 자동화 (버전 bump / git tag / gh release).
# 노트 body 는 호출자(Claude)가 파일로 넘긴다.
#
# 사용:
#   release.sh draft [<from-ref>]
#   release.sh publish <version> <notes-file>
#   release.sh backfill <version> <commit-ish> <notes-file>
#   release.sh --help | -h
#
# 환경변수:
#   RELEASE_DRY_RUN=1          git commit/tag/push + gh release 를 실행하지 않고 [dry-run] echo
#   GH_CMD                     gh 바이너리 override (default: gh)
#   GIT_PUSH_CMD               push 명령 override (default: "git push")
#   RELEASE_PLUGIN_JSON        .claude-plugin/plugin.json 경로 override
#   RELEASE_MARKETPLACE_JSON   .claude-plugin/marketplace.json 경로 override

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

GH_CMD="${GH_CMD:-gh}"
GIT_PUSH_CMD="${GIT_PUSH_CMD:-git push}"
RELEASE_PLUGIN_JSON="${RELEASE_PLUGIN_JSON:-$REPO_ROOT/.claude-plugin/plugin.json}"
RELEASE_MARKETPLACE_JSON="${RELEASE_MARKETPLACE_JSON:-$REPO_ROOT/.claude-plugin/marketplace.json}"
RELEASE_DRY_RUN="${RELEASE_DRY_RUN:-0}"

usage() {
  cat <<'USAGE'
release.sh draft [<from-ref>]
release.sh publish <version> <notes-file>
release.sh backfill <version> <commit-ish> <notes-file>
release.sh --help | -h

Env:
  RELEASE_DRY_RUN=1          git commit/tag/push + gh release 대신 [dry-run] echo
  GH_CMD                     gh 바이너리 override (default: gh)
  GIT_PUSH_CMD               push 명령 override (default: "git push")
  RELEASE_PLUGIN_JSON        .claude-plugin/plugin.json 경로 override
  RELEASE_MARKETPLACE_JSON   .claude-plugin/marketplace.json 경로 override
USAGE
}

# ── 순수 함수 ────────────────────────────────────────────────────────

# bump_version_json <file> <newver> — 파일 안 "version": "..." 를 newver 로 치환.
bump_version_json() {
  local file="$1" newver="$2"
  if [ "$RELEASE_DRY_RUN" = "1" ]; then
    echo "[dry-run] bump_version_json $file -> $newver" >&2
    return 0
  fi
  local tmp
  tmp="$(mktemp)"
  sed -E 's/"version": *"[0-9]+\.[0-9]+\.[0-9]+"/"version": "'"$newver"'"/' "$file" > "$tmp"
  mv "$tmp" "$file"
}

# group_commits_by_type [<log-text>] — "<sha> <subject>" 라인(인자 또는 stdin)을
# conventional-commit type 별로 그룹핑해 release note skeleton 출력.
group_commits_by_type() {
  local log_text="${1:-}"
  if [ -z "$log_text" ] && [ ! -t 0 ]; then
    log_text="$(cat)"
  fi

  local feat="" fix="" refactor="" docs=""
  local line subject type rest
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    subject="${line#* }"
    if printf '%s' "$subject" | grep -qE '^[a-zA-Z]+(\([^)]*\))?: '; then
      type="$(printf '%s' "$subject" | sed -E 's/^([a-zA-Z]+)(\([^)]*\))?: .*/\1/')"
      rest="$(printf '%s' "$subject" | sed -E 's/^[a-zA-Z]+(\([^)]*\))?: //')"
    else
      type=""
      rest="$subject"
    fi
    case "$type" in
      feat)           feat="${feat}- ${rest}"$'\n' ;;
      fix)            fix="${fix}- ${rest}"$'\n' ;;
      refactor|chore) refactor="${refactor}- ${rest}"$'\n' ;;
      docs)           docs="${docs}- ${rest}"$'\n' ;;
      *) ;;
    esac
  done <<< "$log_text"

  echo "## v<NEXT?> — <요약>"
  echo
  if [ -n "$feat" ]; then
    echo "### ✨ Feature"
    printf '%s' "$feat"
  fi
  if [ -n "$fix" ]; then
    echo "### 🐛 Fix"
    printf '%s' "$fix"
  fi
  if [ -n "$refactor" ]; then
    echo "### ♻️ Refactor / Chore"
    printf '%s' "$refactor"
  fi
  if [ -n "$docs" ]; then
    echo "### 📝 Docs"
    printf '%s' "$docs"
  fi
  echo
  echo '**업데이트**: `/plugin update sshworld`'
}

# notes-file 첫 "## " 헤딩의 "— " 뒤 텍스트 추출. 없으면 "release v<version>".
_notes_summary() {
  local notes_file="$1" version="$2" summary
  summary="$(grep -m1 '^## ' "$notes_file" 2>/dev/null | sed -E 's/^## +[^—]*— *//')"
  if [ -z "$summary" ]; then
    summary="release v${version}"
  fi
  printf '%s' "$summary"
}

# ── 서브커맨드 ──────────────────────────────────────────────────────

cmd_draft() {
  local from_ref="${1:-}"
  if [ -z "$from_ref" ]; then
    from_ref="$(git -C "$REPO_ROOT" describe --tags --match 'sshworld--v*' --abbrev=0 2>/dev/null)" || from_ref=""
    if [ -z "$from_ref" ]; then
      from_ref="$(git -C "$REPO_ROOT" rev-list --max-parents=0 HEAD 2>/dev/null | tail -1)"
    fi
  fi
  local log_text
  log_text="$(git -C "$REPO_ROOT" log --format='%h %s' "${from_ref}..HEAD" 2>/dev/null)" || log_text=""
  group_commits_by_type "$log_text"
}

cmd_publish() {
  local version="${1:-}" notes_file="${2:-}"
  if [ -z "$version" ] || [ -z "$notes_file" ]; then
    echo "release.sh publish: <version> <notes-file> 필요" >&2
    return 2
  fi
  if [ ! -f "$notes_file" ] && [ "$RELEASE_DRY_RUN" != "1" ]; then
    echo "release.sh publish: notes-file 없음: $notes_file" >&2
    return 2
  fi

  local summary tag
  summary="$(_notes_summary "$notes_file" "$version")"
  tag="sshworld--v${version}"

  bump_version_json "$RELEASE_PLUGIN_JSON" "$version"
  bump_version_json "$RELEASE_MARKETPLACE_JSON" "$version"

  if [ "$RELEASE_DRY_RUN" = "1" ]; then
    echo "[dry-run] git add $RELEASE_PLUGIN_JSON $RELEASE_MARKETPLACE_JSON"
    echo "[dry-run] git commit -m \"chore(release): v${version} — ${summary}\""
    echo "[dry-run] git tag ${tag}"
    echo "[dry-run] ${GIT_PUSH_CMD} origin HEAD"
    echo "[dry-run] ${GIT_PUSH_CMD} origin ${tag}"
    echo "[dry-run] ${GH_CMD} release create ${tag} --title \"v ${version} — ${summary}\" --notes-file ${notes_file}"
    return 0
  fi

  git -C "$REPO_ROOT" add "$RELEASE_PLUGIN_JSON" "$RELEASE_MARKETPLACE_JSON" || return $?
  git -C "$REPO_ROOT" commit -m "chore(release): v${version} — ${summary}" || return $?
  git -C "$REPO_ROOT" tag "$tag" || return $?
  ${GIT_PUSH_CMD} origin HEAD || return $?
  ${GIT_PUSH_CMD} origin "$tag" || return $?
  ${GH_CMD} release create "$tag" --title "v ${version} — ${summary}" --notes-file "$notes_file"
}

cmd_backfill() {
  local version="${1:-}" commit_ish="${2:-}" notes_file="${3:-}"
  if [ -z "$version" ] || [ -z "$commit_ish" ] || [ -z "$notes_file" ]; then
    echo "release.sh backfill: <version> <commit-ish> <notes-file> 필요" >&2
    return 2
  fi

  local summary tag
  summary="$(_notes_summary "$notes_file" "$version")"
  tag="sshworld--v${version}"

  if git -C "$REPO_ROOT" rev-parse "$tag" >/dev/null 2>&1; then
    echo "release.sh backfill: tag ${tag} 이미 존재 — skip" >&2
  else
    if [ "$RELEASE_DRY_RUN" = "1" ]; then
      echo "[dry-run] git tag ${tag} ${commit_ish}"
      echo "[dry-run] ${GIT_PUSH_CMD} origin ${tag}"
    else
      git -C "$REPO_ROOT" tag "$tag" "$commit_ish" || return $?
      ${GIT_PUSH_CMD} origin "$tag" || return $?
    fi
  fi

  # 태그는 이 지점에서 항상 존재(기존 or 방금 생성). 존재하는 태그에 --target 를
  # 넘기면 GitHub 이 422(target_commitish invalid) 를 반환하므로 태그명만 사용.
  if [ "$RELEASE_DRY_RUN" = "1" ]; then
    echo "[dry-run] ${GH_CMD} release create ${tag} --title \"v ${version} — ${summary}\" --notes-file ${notes_file}"
    return 0
  fi

  ${GH_CMD} release create "$tag" --title "v ${version} — ${summary}" --notes-file "$notes_file"
}

# ── main ────────────────────────────────────────────────────────────

main() {
  local sub="${1:-}"
  case "$sub" in
    draft)
      shift
      cmd_draft "$@"
      ;;
    publish)
      shift
      cmd_publish "$@"
      ;;
    backfill)
      shift
      cmd_backfill "$@"
      ;;
    -h|--help|"")
      usage
      exit 0
      ;;
    *)
      echo "release.sh: 알 수 없는 서브커맨드: $sub" >&2
      usage >&2
      exit 2
      ;;
  esac
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  main "$@"
fi
