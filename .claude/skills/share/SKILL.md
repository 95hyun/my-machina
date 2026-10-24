---
name: share
description: 현재 run의 산출물로 팀 정본 기획서(final.md)를 쓰고 Claude Docs → Artifact → md 순서로 발행한다. 원본 묶음(share.md)은 부록으로 Discord 첨부용.
argument-hint: "[md — 발행 없이 파일만]"
disable-model-invocation: true
model: opus
---

# /share — 정본 기획서 + 팀 공유

먼저 `hackathon/RULES.md`를 Read한다(해커톤 공통 규칙 — 이 세션에서 이미 읽었으면 생략).

언제든 다시 실행할 수 있다(단계가 진행될 때마다 정본이 갱신된다).

## 1. 정본 `final.md` (메인이 정리)
- `hackathon/runs/CURRENT`를 Read → `$RUN`. `hackathon/templates/final.md` 구조 그대로 `$RUN/final.md`를 Write한다.
- 읽는 것(있는 것만, 이 순서): `03-final.md` → 확정 원페이저 → `03-redteam.md`의 해당 후보 → `04-mvp.md` → `04-review.md` → `05-pitch.md` → 의사결정 기록용으로 `01-topics.md` 첫 줄·`02-problems.md` 첫 줄.
- 규칙:
  - 산출물에 있는 내용만 옮긴다. 새 사실·수치를 만들지 않는다. 출처 링크와 `가정` 표기를 그대로 유지한다.
  - 파일끼리 값이 다르면(예: 기한 규칙, 가격) 최신 단계 파일을 따르고 그 칸에 `⚠️불일치: <파일>`을 단다.
  - 아직 없는 단계의 섹션은 "미정 — `/<스킬>` 후 갱신"으로 둔다.
  - 길이: 화면 2~3장. 원페이저·MVP 전문을 복사하지 말고 요약한다.

## 2. 원본 묶음 `share.md` (부록)
- `./hackathon/bin/share` 실행 — 단계 산출물을 재작성 없이 이어 붙인다(메인은 내용을 읽지 않는다).

## 3. 발행 (인자가 `md`면 생략)
가능한 첫 번째 방법 하나만 쓴다:
1. **Claude Docs**: 세션에 Claude Docs 도구(`mcp__claude_ai_Claude_Docs__*`)가 있으면 그 도구 지침대로 final.md 내용을 문서 1개로 만든다. 문서 링크를 `$RUN/docs-url.txt`에 저장하고, 다음 실행부터는 새로 만들지 말고 그 문서를 갱신한다.
2. **Artifact**: Docs가 없고 Artifact 도구가 있으면 그 도구 지침대로 final.md 내용을 페이지 1개로 발행한다. 링크를 `$RUN/artifact-url.txt`에 저장하고 다음 실행부터는 같은 파일 경로로 재발행해 링크를 유지한다.
3. 둘 다 없으면 발행하지 않는다(Notion은 쓰지 않는다).

## 4. 보고
- 정본: `final.md` 절대 경로 + 발행 링크(있으면)
- 부록: `share.md` 절대 경로
- "Discord에는 final.md(또는 링크)를 올리고 share.md는 필요할 때 첨부. 메시지 본문은 2000자 제한."
