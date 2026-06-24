# Slice S4 — install 시점 @@SCRIPTS_DIR@@ 절대경로 bake (type=feat)

## 배경/문제
`/plan-dev`+cmux dispatch 가 헬퍼를 PWD-상대 `scripts/X.sh` 로 참조. 스크립트 실제 위치는 scope별:
user=`$HOME/scripts/`, project=`$TARGET/scripts/`. `scripts/` 없는 프로젝트서 user-scope 설치본 쓰면
상대경로 해석 실패 → 모델이 dispatch 조용히 포기. 런타임 `$CLAUDE_PROJECT_DIR` 빈값 → install 시점 bake 가 유일 해법.
기존 동일 패턴: install.sh 가 settings.json hook command 의 `$CLAUDE_PROJECT_DIR`→`$HOME` 를 jq rewrite.

## 알려진 스크립트명 (이것만 정밀 변환)
cmux-pane, tmux-pane, dispatch-slice-pane, detect-pane-env, plan-dev-session,
plan-dev-progress, finish-plan-dev, cmux-title-chpwd, merge-settings → 각 `.sh`.

## A. 소스 텍스트 파일 변환: `scripts/X.sh` → `@@SCRIPTS_DIR@@/X.sh`
대상 8파일:
`.claude/commands/plan-dev.md`, `.claude/commands/parallel-consult.md`,
`.claude/hooks/{cmux-dispatch-hint,track-cmux-edit-burst,limit-child-panes,enforce-cmux-context}.sh`,
`.claude/agents/implementor.md`, `.claude/skills/tmux-orchestrate/SKILL.md`.

**오염 방지**: 이미 `~/`, `.claude/`, `/`(절대), `@@` 접두가 붙은 `scripts/` 는 변환 금지.
bare `scripts/X.sh` (또는 `./scripts/X.sh` 의 `scripts/` 부분 아님 — `./scripts/` 는 보존? 아래 참조)만.
권장 perl (negative lookbehind):
```bash
KNOWN='cmux-pane|tmux-pane|dispatch-slice-pane|detect-pane-env|plan-dev-session|plan-dev-progress|finish-plan-dev|cmux-title-chpwd|merge-settings'
perl -0pi -e "s{(?<![\w/~.\@-])scripts/($KNOWN)\.sh}{\@\@SCRIPTS_DIR\@\@/\$1.sh}g" <file>
```
→ `~/scripts/dispatch-slice-pane.sh`(plan-dev.md 회복력 룰), `.claude/scripts/`, `/x/scripts/` 보존됨.

### 🚨 절대 변환 금지 — enforce-cmux-context.sh:63 matcher 라인
```
    tmux|tmux-cli|tmux-pane.sh|./scripts/tmux-pane.sh|scripts/tmux-pane.sh)
```
이 `case` matcher 는 부모가 입력하는 **명령 문자열 탐지용** 이라 절대경로 bake 금지 → `scripts/tmux-pane.sh)` 원형 유지.
위 lookbehind regex 는 `|scripts/` (앞이 `|`) 와 `./scripts/`(앞이 `.`) 를 매치하나? `|` 는 `[\w/~.@-]` 에 없으니 매치됨 → **오변환 위험**.
→ enforce-cmux-context.sh 는 **수동 처리**: 광고/메시지성 `scripts/X.sh` 참조만 변환하고, 63행 case matcher 패턴(`tmux-pane.sh|./scripts/tmux-pane.sh|scripts/tmux-pane.sh)`)은 그대로 둘 것. 변환 후 반드시 `grep -n 'scripts/tmux-pane.sh)' enforce-cmux-context.sh` 로 보존 확인.

## B. install.sh — @@SCRIPTS_DIR@@ → 절대경로 sed rewrite
do_install 의 FILES 복사 루프(현재 `cp "$src_file" "$dest_file"` 직후, hook chmod 부근).
- `proj_root` 가 현재 루프 **뒤**(`local proj_root="$(dirname "$dest")"`)에 선언됨 → **루프 전으로 끌어올리거나** 루프용으로 미리 계산.
  (SCRIPTS 루프의 기존 `proj_root` 와 중복 `local` 선언 충돌 주의 — 하나로 통합.)
- 복사 직후 치환:
  ```bash
  # @@SCRIPTS_DIR@@ → 설치 scope 의 scripts 절대경로 (settings.json $CLAUDE_PROJECT_DIR→$HOME rewrite 와 동일 취지)
  if grep -q '@@SCRIPTS_DIR@@' "$dest_file" 2>/dev/null; then
    sed -i.bak2 "s|@@SCRIPTS_DIR@@|$proj_root/scripts|g" "$dest_file" && rm -f "$dest_file.bak2"
  fi
  ```
  (macOS/BSD sed → `-i.bak2` + rm 패턴. `$proj_root/scripts` = user 면 `$HOME/scripts`, project 면 `$TARGET/scripts`.)
- 치환 대상은 위 8파일이 dest 로 복사된 것. 다른 파일에 `@@SCRIPTS_DIR@@` 없으면 grep 가드로 skip.

## C. 신규 테스트 tests/install_scripts_dir_rewrite.sh (chmod +x)
기존 `tests/install_*.sh` 컨벤션(`HOME=$TMP ... ./install.sh user`) 따름:
- `TMP=$(mktemp -d); HOME="$TMP" bash install.sh user` (또는 기존 테스트가 쓰는 호출형).
- 검증:
  1. dest(`$TMP/.claude/...`) 8파일에 `@@SCRIPTS_DIR@@` 잔재 **0**: `! grep -rq '@@SCRIPTS_DIR@@' "$TMP/.claude"`.
  2. dest `cmux-dispatch-hint.sh`(또는 plan-dev.md)에 `$TMP/scripts/` 절대경로 존재.
  3. dest `enforce-cmux-context.sh` 의 matcher `scripts/tmux-pane.sh)` **보존**.
- PASS 시 `OK`.

## 검증
```bash
bash tests/install_scripts_dir_rewrite.sh
for t in tests/install_*.sh; do bash "$t" || echo "REGRESS $t"; done   # 기존 install 테스트 회귀 없음
grep -q '@@SCRIPTS_DIR@@' install.sh                                    # token rewrite 로직 존재
grep -q 'scripts/tmux-pane.sh)' .claude/hooks/enforce-cmux-context.sh   # matcher 보존
! grep -rEq '(~|\.claude|@@SCRIPTS_DIR@@)/@@SCRIPTS_DIR@@' .claude      # 이중오염 없음
```

## 주의
- plan-dev.md 는 S3 가 sonnet 1줄 추가한 베이스 위에서 작업(rebase 후 dispatch). script 경로만 변환, S3 의 sonnet 문구 보존.
- 변환은 **known 스크립트명만**. `scripts/foo.sh`(미지명)·코드블록 안 일반 예시는 신중히(대상 8파일 외 건드리지 말 것).

## 완료 시
검증 전부 PASS → `✅ S4 done`. 실패 → `❌`+원인.
