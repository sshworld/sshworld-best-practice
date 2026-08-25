#!/usr/bin/env bash
# open-doc.sh 계약 테스트.
#
# ⚠️ 실제 orca 호출 금지 — 가짜 orca 를 임시 디렉토리에 만들고 ORCA_BIN 으로 주입.
# ⚠️ 실제로 창을 띄우지 말 것 — OPEN_DOC_DRY_RUN=1 사용 (OS 기본 오프너 경로만 대상;
#    orca file open 은 가짜 바이너리라 애초에 실창이 없다).
# ⚠️ 개발 머신 자체가 실제 Orca 세션이고 PATH 에 진짜 orca 가 있을 수 있다 — 매 케이스
#    주변 ORCA_*/TERM_PROGRAM/TMUX/CMUX_* 를 scrub 하지 않으면 케이스가 틀린 이유로
#    통과·실패한다 (CLAUDE.md 안티패턴 참조).

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OPEN_DOC="$REPO/scripts/open-doc.sh"

step() { echo ""; echo "[$1] $2"; }
fail() { echo "❌ FAIL: $1" >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# detect-pane-env.sh 가 읽는 8개 변수 전부 scrub.
SCRUB=(-u ORCA_TERMINAL_HANDLE -u ORCA_WORKSPACE_ID -u TERM_PROGRAM -u TMUX
       -u CMUX_WORKSPACE_ID -u CMUX_SURFACE_ID -u CMUX_SOCKET -u CMUX_SOCKET_PASSWORD)

MISSING_BIN="$TMP/does-not-exist"

FAKE_ORCA="$TMP/fake-orca"
cat > "$FAKE_ORCA" <<'EOS'
#!/usr/bin/env bash
set -u
case "${1:-}" in
  status) exit 0 ;;
  file)
    sub="${2:-}"; path="${3:-}"
    if [ "$sub" != "open" ]; then echo '{"ok":false}'; exit 0; fi
    case "${FAKE_ORCA_MODE:-true}" in
      true)  echo '{"ok":true,"result":{}}' ;;
      false) echo '{"ok":false,"error":{"code":"invalid_relative_path"}}' ;;
      conditional)
        case "$path" in
          "$FAKE_ORCA_LINK_PATH"/*|"$FAKE_ORCA_LINK_PATH") echo '{"ok":true,"result":{}}' ;;
          *) echo '{"ok":false,"error":{"code":"invalid_relative_path"}}' ;;
        esac
        ;;
      *) echo '{"ok":false}' ;;
    esac
    exit 0
    ;;
  *) echo '{"ok":false}'; exit 0 ;;
esac
EOS
chmod +x "$FAKE_ORCA"

# ─────────────────────────────────────────────────────────
step 1 "kind != orca (전부 scrub, 두 BIN 존재하지 않음) — OS 기본 열기, orca 미호출"
TARGET1="$TMP/doc1.md"; echo hi > "$TARGET1"
OUT1=$(cd "$TMP" && env "${SCRUB[@]}" ORCA_BIN="$MISSING_BIN" CMUX_BIN="$MISSING_BIN" \
  OPEN_DOC_DRY_RUN=1 "$OPEN_DOC" "$TARGET1" 2>"$TMP/err1")
RC1=$?
[ "$RC1" -eq 0 ] || fail "kind!=orca 인데 rc!=0 ($RC1): $(cat "$TMP/err1")"
printf '%s\n' "$OUT1" | grep -qE '^(open|xdg-open) ' || fail "OS 기본 열기 dry-run 출력 아님: $OUT1"
printf '%s\n' "$OUT1" | grep -qi 'orca' && fail "orca 호출 흔적 있음: $OUT1"

# ─────────────────────────────────────────────────────────
step 2 "kind=orca + file open ok:true — 그것으로 끝, 폴백 없음"
TARGET2="$TMP/doc2.md"; echo hi > "$TARGET2"
OUT2=$(cd "$TMP" && env "${SCRUB[@]}" ORCA_BIN="$FAKE_ORCA" FAKE_ORCA_MODE=true \
  "$OPEN_DOC" "$TARGET2" 2>"$TMP/err2")
RC2=$?
[ "$RC2" -eq 0 ] || fail "orca ok:true 인데 rc!=0 ($RC2): $(cat "$TMP/err2")"
[ -s "$TMP/err2" ] && fail "폴백 흔적(stderr) 있음: $(cat "$TMP/err2")"

# ─────────────────────────────────────────────────────────
step 3 "kind=orca + file open ok:false + 심링크 없음 — OS 기본 폴백 + stderr 안내 + 심링크 힌트"
TARGET3="$TMP/doc3.md"; echo hi > "$TARGET3"
WORKDIR3="$TMP/ws3"; mkdir -p "$WORKDIR3"
OUT3=$(cd "$WORKDIR3" && env "${SCRUB[@]}" ORCA_BIN="$FAKE_ORCA" FAKE_ORCA_MODE=false \
  OPEN_DOC_DRY_RUN=1 "$OPEN_DOC" "$TARGET3" 2>"$TMP/err3")
RC3=$?
[ "$RC3" -eq 0 ] || fail "폴백 rc!=0 ($RC3): $(cat "$TMP/err3")"
printf '%s\n' "$OUT3" | grep -qE '^(open|xdg-open) ' || fail "폴백 시 OS 기본 dry-run 출력 없음: $OUT3"
ERR3=$(cat "$TMP/err3")
printf '%s' "$ERR3" | grep -q '폴백' || fail "폴백 안내 stderr 없음: $ERR3"
printf '%s' "$ERR3" | grep -qE '심(볼릭)?링크' || fail "심링크 힌트 없음: $ERR3"

# ─────────────────────────────────────────────────────────
step 4 "kind=orca + 워크스페이스 밖 실패 + 심링크 경유 성공 — 재시도 성공"
WORKDIR4="$TMP/ws4"; mkdir -p "$WORKDIR4"
OUTSIDE4="$TMP/outside4"; mkdir -p "$OUTSIDE4"
TARGET4="$OUTSIDE4/design-doc.md"; echo hi > "$TARGET4"
ln -s "$OUTSIDE4" "$WORKDIR4/.claude-design-link"
LINK_ABS4="$WORKDIR4/.claude-design-link"
OUT4=$(cd "$WORKDIR4" && env "${SCRUB[@]}" ORCA_BIN="$FAKE_ORCA" FAKE_ORCA_MODE=conditional \
  FAKE_ORCA_LINK_PATH="$LINK_ABS4" CBP_DESIGN_LINK=".claude-design-link" \
  "$OPEN_DOC" "$TARGET4" 2>"$TMP/err4")
RC4=$?
[ "$RC4" -eq 0 ] || fail "심링크 경유 재시도 실패 (rc=$RC4): $(cat "$TMP/err4")"
[ -s "$TMP/err4" ] && fail "성공했는데 폴백 stderr 있음: $(cat "$TMP/err4")"

# ─────────────────────────────────────────────────────────
step 5 "인자 없음 — usage + exit 2 / 존재하지 않는 파일 — die"
set +e
OUT5=$(env "${SCRUB[@]}" ORCA_BIN="$MISSING_BIN" "$OPEN_DOC" 2>"$TMP/err5")
RC5=$?
set -e
[ "$RC5" -eq 2 ] || fail "인자 없음인데 exit 2 아님 (rc=$RC5)"
grep -qi 'usage' "$TMP/err5" || fail "usage 안내 없음: $(cat "$TMP/err5")"

set +e
OUT5B=$(env "${SCRUB[@]}" ORCA_BIN="$MISSING_BIN" "$OPEN_DOC" "$TMP/nope-$RANDOM.md" 2>"$TMP/err5b")
RC5B=$?
set -e
[ "$RC5B" -ne 0 ] || fail "없는 파일인데 rc=0"
[ -s "$TMP/err5b" ] || fail "없는 파일 die 메시지 없음"

# ─────────────────────────────────────────────────────────
step 6 "심링크가 없을 때 자동 생성하지 않는다"
WORKDIR6="$TMP/ws6"; mkdir -p "$WORKDIR6"
TARGET6="$TMP/doc6.md"; echo hi > "$TARGET6"
LINK6="$WORKDIR6/.claude/design"
[ -e "$LINK6" ] || true
OUT6=$(cd "$WORKDIR6" && env "${SCRUB[@]}" ORCA_BIN="$FAKE_ORCA" FAKE_ORCA_MODE=false \
  OPEN_DOC_DRY_RUN=1 "$OPEN_DOC" "$TARGET6" 2>"$TMP/err6")
RC6=$?
[ "$RC6" -eq 0 ] || fail "case6 실행 실패 (rc=$RC6): $(cat "$TMP/err6")"
[ -e "$LINK6" ] && fail "open-doc.sh 가 심링크를 자동 생성함: $LINK6"

echo ""
echo "OK"
