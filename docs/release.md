# 릴리즈 & 버저닝 규칙

> 상위 문서: [CLAUDE.md](../CLAUDE.md)

- **버전 소스**: `.claude-plugin/plugin.json` + `.claude-plugin/marketplace.json` 두 곳 동시. `release.sh` 가 동기화.
- **semver bump 기준**: breaking(하위호환 깨짐)=major / 새 기능(feat)=minor / fix·docs·refactor·chore=patch. plan-dev Phase 4 의 commit-advisor 가 산정한 최대 type 을 참고.
- **태그 컨벤션**: `sshworld--vX.Y.Z` (double-dash prefix 유지).
- **발행 위치**: **GitHub Release native 로만**. CHANGELOG.md 파일은 두지 않는다(중복). 사용자 판단.
- **릴리즈 노트 형식**: 섹션 헤더는 **conventional 영문 라벨**(Feature/Fix/Refactor/Chore/Docs/Breaking), 항목 설명은 **한글**.
```
## v1.3.6 — <한줄 요약>

### ✨ Feature          (feat)
### 🐛 Fix              (fix)
### ♻️ Refactor / Chore (refactor·chore)
### 📝 Docs             (docs)
### ⚠️ Breaking         (있을 때만)

**업데이트**: `/plugin update sshworld`
```
  - 빈 섹션 생략. 항목은 사용자 관점 한 줄. **슬라이스 라벨(S1/S2)·머지 잡음 금지** (commit-advisor 원칙과 동일).
- **릴리즈 흐름 (매 배포마다 Claude 가 수행)**:
  1. `scripts/release.sh draft` 로 skeleton 뽑고 → Claude 가 사용자 관점으로 살 붙임 → notes 파일 저장.
  2. `RELEASE_DRY_RUN=1 scripts/release.sh publish <ver> <notes>` 로 검증.
  3. `scripts/release.sh publish <ver> <notes>` 로 실발행 (bump+commit+tag+push+gh release).
- plan-dev Phase 5(Branch & Push) 와의 관계: feature 머지와 릴리즈(버전 bump)는 별개 행위. 버전 올릴 때만 release.sh.
