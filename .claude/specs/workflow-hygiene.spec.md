# Slice S3 — workflow-hygiene (type: docs)

## 목표
두 가지 콘텐츠 결함 교정:
1. **슬라이스 라벨 누출**: 협업자는 `S1`/`S2` 가 뭔지 모름. commit-advisor 가 내부 라벨·`merge:` 잡음을 squash·위생 추천하게 + plan-dev 문서가 rebase-ff(merge 금지) 강조.
2. **오도성 가이드**: cmux-dispatch.md 의 "정책/하네스 파일 자체 편집 = direct-edit escape" 문구가 모델을 반사적 direct-edit 로 유도함(실제 사고 유발). 자기수정도 cmux 에선 **dispatch 기본**이 되도록 교정.

## 절대 규칙
- 문서/프롬프트 슬라이스. 코드 동작 변경 없음.
- 커밋 메시지에 `S3`/`슬라이스` 라벨 금지. `docs: …` 한글 한 문장.
- **S1 이 이미 `agents/commit-advisor.md` 에 commit-advised marker touch 지시를 추가**했음 — 그 내용 보존하고 위에 "히스토리 위생" 섹션만 추가.
- 완료 시 `✅` / 실패 `❌`.

## 변경 대상
1. `agents/commit-advisor.md` — 히스토리 위생/squash 섹션
2. `commands/plan-dev.md` — Phase 3/4 보강
3. `commands/plan-dev/cmux-dispatch.md` — merge 금지 경고 + direct-edit escape 문구 교정
4. `commands/plan-dev/antipatterns.md` — 안티패턴 2건 추가
5. `hooks/cmux-dispatch-hint.sh` — self-modification 뉘앙스 제거
6. `README.md`, `CLAUDE.md` — 동기화

---

## 1. `agents/commit-advisor.md` — "1-c 세션 히스토리 위생" 추가
- `git log <start_ref>..HEAD --oneline` 에 내부 슬라이스 라벨(`S1`/`S2`/`슬라이스 N`)·`merge:` 잡음·과도한 소커밋이 보이면 → **squash 추천**: `git reset --soft <start_ref>` 후 단일(또는 소수 의미단위) 깨끗한 conventional 커밋으로 재작성.
- **명문화**: `S1`/`S2` 등 내부 계획 라벨은 plan-dev 내부 artifact — **최종 커밋 메시지·브랜치명에 절대 노출 금지**. 협업자는 슬라이스 번호를 모른다. 메시지는 "무엇을 왜 바꿨는가"로만.
- 실제 reset/commit 은 사용자 승인 후 메인이 실행 (commit-advisor 는 추천만 — 기존 "안 하는 것" 유지).

## 2. `commands/plan-dev.md`
- **Phase 3 (Verify)**: rebase 설명에 "fast-forward only, `git merge` 금지(merge 커밋이 S라벨·잡음 누출)" 한 줄.
- **Phase 4 (Git 추천)**: bullet 추가 — "세션에 내부 라벨/머지 잡음 커밋이 쌓였으면 commit-advisor 가 squash 추천 → 깨끗한 단일/소수 커밋. S1/S2 라벨은 최종 히스토리에 남기지 않는다."

## 3. `commands/plan-dev/cmux-dispatch.md`
- **Phase 3 머지 섹션** (L95~103 근처): rebase-ff 블록에 "❌ `git merge <type>/<slug>` — merge 커밋이 `S1`/`merge:` 잡음을 협업 히스토리에 누출. 항상 rebase fast-forward." 경고 추가.
- **L32 및 환경별 Mode 룰의 "(정책/문서/하네스 파일 자체 편집 등)" 예시 삭제/약화**: cmux 에서 direct-edit 는 **반사적으로 쓰지 말 것** — 자기수정(plan-dev 자신의 hook/문서 편집)도 **dispatch(cmux) 기본**. `CMUX_DIRECT_EDIT_OK=1` escape 는 "정책/하네스 파일이라서"가 아니라 진짜 예외적 사유(예: dispatch 자체가 불가한 환경)일 때만. "정책/하네스 파일 = direct-edit" 라는 일반화 문구 제거.

## 4. `commands/plan-dev/antipatterns.md`
두 항목 추가:
- ❌ `S1`/`S2` 등 슬라이스 라벨 또는 `merge:` 를 최종 커밋·브랜치명에 노출 — 협업자가 의미 모름. commit-advisor 가 squash·위생 추천, rebase-ff 로 merge 커밋 자체 제거.
- ❌ cmux 환경에서 "정책/하네스/문서 파일이니 direct-edit 가 맞다"며 반사적 direct-edit — 자기수정도 dispatch(cmux) 기본. `CMUX_DIRECT_EDIT_OK=1` 는 진짜 예외 한정.

## 5. `hooks/cmux-dispatch-hint.sh`
- SessionStart advisory 텍스트에서 "정책/문서/하네스 파일 자체 편집 등" 을 direct-edit 정당화 예시로 드는 부분이 있으면 제거/완화. dispatch 기본 메시지는 유지. (없으면 변경 불필요 — 확인만.)

## 6. 문서 동기화
- `README.md`: commit-advisor 설명에 "다중 커밋 squash·라벨 위생" 반영. plan-dev 흐름 설명에 rebase-ff(merge 금지) 유지 확인.
- `CLAUDE.md`: commit-advisor.md 책임 행에 "히스토리 위생/squash 추천" 추가. 안티패턴 섹션에 S라벨 누출 한 줄 (이미 있으면 skip).

## 검증 (완료 전 필수)
```bash
grep -qi "squash" agents/commit-advisor.md
grep -q "슬라이스 라벨\|S1" commands/plan-dev/antipatterns.md
grep -q "merge" commands/plan-dev/cmux-dispatch.md
# 링크 유효 (상대경로 파일 존재)
ls commands/plan-dev/*.md >/dev/null
```
plan-dev.md 200줄 이하 유지 확인: `[ "$(wc -l < commands/plan-dev.md)" -le 200 ]`.

## 커밋
`DOC_IMPACT=updated git commit -m "docs: 슬라이스 라벨 위생·squash 추천 + 반사적 direct-edit 가이드 교정"`
