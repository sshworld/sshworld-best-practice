#!/usr/bin/env bash
# marker 경로 리졸버 + writer/reader 일치 + wait-idle 마스킹 계약 테스트.
#
# ⚠️ 실제 cmux 를 절대 호출하지 않는다 (CMUX_BIN mock). 이 스위트는
# plan-dev-session.sh / finish-plan-dev.sh 를 타지 않으므로 cleanup 계열
# 우회 선언은 불필요하다.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESOLVER="$REPO/scripts/cbp-marker-path.sh"
NOTIFY="$REPO/hooks/notify-slice-done.sh"
REAP_ON_STOP="$REPO/hooks/reap-on-stop.sh"
PANE="$REPO/scripts/cmux-pane.sh"

step() { echo ""; echo "[$1] $2"; }
fail() { echo "❌ FAIL: $1" >&2; exit 1; }

[ -f "$RESOLVER" ] || fail "리졸버 없음: $RESOLVER"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"

# shellcheck source=/dev/null
source "$RESOLVER"

# ─────────────────────────────────────────────────────────
step 1 "비-git 디렉토리 → ~/.cache/cbp/marker-<sanitized WS>"
NONGIT="$TMP/nongit"; mkdir -p "$NONGIT"
OUT=$(cd "$NONGIT" && CMUX_WORKSPACE_ID="AB:CD/EF" bash -c "source '$RESOLVER'; cbp_marker_dir")
case "$OUT" in
  "$HOME/.cache/cbp/marker-AB_CD_EF") ;;
  *) fail "비-git 폴백 경로가 예상과 다름: $OUT" ;;
esac
[ -d "$OUT" ] || fail "폴백 디렉토리가 생성되지 않음: $OUT"

step 2 "git 일반 체크아웃 → git-common-dir (worktree 여부로 갈리지 않음)"
GITREPO="$TMP/plain"; mkdir -p "$GITREPO"
git -C "$GITREPO" init -q
OUT=$(cd "$GITREPO" && bash -c "source '$RESOLVER'; cbp_marker_dir")
[ -d "$OUT" ] || fail "git 경로가 디렉토리가 아님: $OUT"
case "$OUT" in */.git) ;; *) fail "git-common-dir 가 아님: $OUT" ;; esac

step 3 "linked worktree → 같은 공용 git-common-dir"
git -C "$GITREPO" -c user.email=t@e -c user.name=t commit -q --allow-empty -m init
git -C "$GITREPO" worktree add -q "$TMP/wt" -b wt-branch
OUT_WT=$(cd "$TMP/wt" && bash -c "source '$RESOLVER'; cbp_marker_dir")
[ "$OUT_WT" = "$OUT" ] || fail "worktree 와 본체가 다른 marker dir 를 본다: $OUT_WT vs $OUT"

step 4 "CBP_MARKER_DIR override 최우선"
OVR="$TMP/override"
OUT=$(cd "$GITREPO" && CBP_MARKER_DIR="$OVR" bash -c "source '$RESOLVER'; cbp_marker_dir")
[ "$OUT" = "$OVR" ] || fail "override 무시됨: $OUT"
[ -d "$OVR" ] || fail "override 디렉토리 미생성"

step 5 "marker key — git 이면 branch, 비-git 이면 surface ref 폴백"
K1=$(cd "$GITREPO" && bash -c "source '$RESOLVER'; cbp_marker_key")
[ -n "$K1" ] || fail "git 에서 key 가 비었음"
K2=$(cd "$NONGIT" && CBP_SELF_PANE="surface:42" bash -c "source '$RESOLVER'; cbp_marker_key")
[ "$K2" = "surface:42" ] || fail "비-git key 폴백 실패: $K2"

# ─────────────────────────────────────────────────────────
# writer(hook) 계약 — mock payload 로 실제 기록되는지
mk_payload() {
  local transcript="$1"
  printf '{"transcript_path":"%s"}' "$transcript"
}
mk_transcript() {
  local f="$TMP/transcript-$RANDOM.jsonl"
  # hook 은 "마지막 비-tool_result user 줄 **이후**" 의 assistant 텍스트만 판정한다.
  # user 줄이 없으면 기본값 1 → tail -n +2 로 첫 줄이 잘리므로 user 줄을 먼저 둔다.
  {
    printf '{"type":"user","message":{"content":"go"}}\n'
    printf '{"type":"assistant","message":{"content":[{"type":"text","text":"✅ %s: done"}]}}\n' "${1:-slice}"
  } > "$f"
  printf '%s' "$f"
}

step 6 "비-git 에서 notify-slice-done 이 marker 를 실제로 기록"
MDIR="$TMP/md6"
T=$(mk_transcript repro)
(cd "$NONGIT" && mk_payload "$T" | CBP_MARKER_DIR="$MDIR" CMUX_WORKSPACE_ID="ws1" CBP_SELF_PANE="surface:9" \
  CMUX_BIN=/usr/bin/true bash "$NOTIFY" >/dev/null 2>&1)
ls "$MDIR"/cbp-slice-done-* >/dev/null 2>&1 || fail "비-git 에서 marker 미기록 (dir=$MDIR: $(ls -A "$MDIR" 2>/dev/null))"

step 7 "일반 체크아웃(비-worktree)에서도 marker 기록 — 게이트 3·4 완화 회귀"
MDIR7="$TMP/md7"
T=$(mk_transcript plain)
(cd "$GITREPO" && mk_payload "$T" | CBP_MARKER_DIR="$MDIR7" CMUX_WORKSPACE_ID="ws1" \
  CMUX_BIN=/usr/bin/true bash "$NOTIFY" >/dev/null 2>&1)
ls "$MDIR7"/cbp-slice-done-* >/dev/null 2>&1 || fail "일반 체크아웃에서 marker 미기록"

step 8 "비-cmux 에서는 기록하지 않는다 — 게이트 1 유지"
MDIR8="$TMP/md8"; mkdir -p "$MDIR8"
T=$(mk_transcript nocmux)
# ⚠️ 테스트가 cmux 안에서 돌면 CMUX_WORKSPACE_ID 가 상속된다 — 명시적으로 지운다.
(cd "$GITREPO" && mk_payload "$T" | env -u CMUX_WORKSPACE_ID CBP_MARKER_DIR="$MDIR8" \
  CMUX_BIN=/usr/bin/true bash "$NOTIFY" >/dev/null 2>&1)
ls "$MDIR8"/cbp-slice-done-* >/dev/null 2>&1 && fail "비-cmux 인데 marker 가 생김"

step 9 "writer 가 쓴 marker 를 reap-on-stop 이 같은 경로에서 찾는다"
grep -q 'cbp_marker_dir' "$REAP_ON_STOP" || fail "reap-on-stop 이 리졸버를 쓰지 않음"
grep -q 'cbp_marker_dir' "$PANE" || fail "cmux-pane.sh 가 리졸버를 쓰지 않음"

# ─────────────────────────────────────────────────────────
step 10 "wait-idle 마스킹 — 경과시간·비용만 다른 화면은 같은 해시"
SCR_A="$TMP/a.txt"; SCR_B="$TMP/b.txt"
cat > "$SCR_A" <<'EOF'
✻ Cogitated for 10m 5s
✢ Misting… (9m 35s · thought for 1s)
💰 3.00 (17.53/h)
작업 내용 동일
EOF
cat > "$SCR_B" <<'EOF'
✻ Cogitated for 11m 40s
✢ Misting… (10m 02s · thought for 2s)
💰 3.42 (18.01/h)
작업 내용 동일
EOF
HA=$(bash -c "source '$RESOLVER'; cbp_mask_volatile < '$SCR_A'" 2>/dev/null)
HB=$(bash -c "source '$RESOLVER'; cbp_mask_volatile < '$SCR_B'" 2>/dev/null)
[ -n "$HA" ] || fail "_cbp_mask_volatile 가 없거나 출력이 비었음"
[ "$HA" = "$HB" ] || fail "변동 라인 마스킹 실패:\n--- A ---\n$HA\n--- B ---\n$HB"

step 11 "본문이 다르면 다른 결과 — 과잉 마스킹 방지"
SCR_C="$TMP/c.txt"
sed 's/작업 내용 동일/작업 내용 변경됨/' "$SCR_A" > "$SCR_C"
HC=$(bash -c "source '$RESOLVER'; cbp_mask_volatile < '$SCR_C'" 2>/dev/null)
[ "$HA" = "$HC" ] && fail "본문 변화를 마스킹이 삼켰다 (과잉 마스킹)"

step 12 "회수 순서 — marker 폴링이 1차임이 코드에 드러난다"
grep -q 'cbp_marker_dir' "$PANE" || fail "reader 리졸버 미적용"
grep -qE 'marker.*(1차|우선|먼저)|fast-path' "$PANE" || fail "marker 우선 회수 근거 문구 없음"

echo ""
echo "OK"
