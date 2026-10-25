---
name: ready
description: '바로 구현하지 않고 검토→요구사항 재진술→영향 범위 좌표→결정 지점 정리→spec.md 박제 후 멈춘다. 새 프로젝트·제품 재량 큰 기능은 intent.md(왜·무엇이 달라지나) draft 먼저. 질문이 남으면 spec 없이 질문만. Keywords: ready, /ready, 검토부터, 바로 시작하지 말고, 작업 준비, 설계 먼저, 스펙 잡아줘, 기획부터, 새 프로젝트, intent'
argument-hint: '[project] <요청 요약>'
---

# Ready — 검토 후 spec 박제, 착수 전 정지

작업 루프 1단계(ready → go → qa → ship). 산출물은 `<project>/.specs/<slug>/spec.md`(+ 프로젝트급이면 `intent.md`)이며 go·ship이 읽는다. 양식은 같은 폴더의 `spec-template.md`·`intent-template.md`.

## 워크플로우

1. **대상 확정**: 프로젝트 = 인자 > 대화 맥락 > cwd. 모호하면 AskUserQuestion 1회. slug = 짧은 영문 kebab.
   - 처음이면 `.specs/`를 repo 로컬 제외에 등록: `grep -qx '.specs/' <repo>/.git/info/exclude || echo '.specs/' >> <repo>/.git/info/exclude`
2. **영향 범위 탐색**: 직접 grep/Read. 폭이 크면 `Explore`(`model: "sonnet"`). 결과는 `파일:라인`. 프로젝트 CLAUDE.md·`docs/decisions.md`(있으면)·같은 slug의 `design.md`(있으면 — 확인 포인트의 `[run]`은 그 "확인 방법"에서 끌어온다)·README·auto-memory의 해당 프로젝트 항목을 먼저 본다.
3. **요청안 평가**: 요청한 to-be를 먼저 평가(가능/리스크/비용). 더 나은 안이 있으면 **추가로** 3줄 제안(무엇이 다른가·왜 낫나·비용 차이). 기본 진행안은 항상 요청안이다.
3.5. **intent 판정**: "무엇을 만들지"가 아직 굳지 않은 작업이면 spec보다 intent.md를 먼저 쓴다.
   - 대상 = 새 프로젝트 시작, 또는 여러 세션에 걸치고 제품 재량이 큰 기능. 면제 = 버그 수정·동작이 명확한 단건 변경.
   - 위치 = 기능 단위는 `.specs/<slug>/intent.md`, 프로젝트 전체 방향은 `.specs/intent.md`(여러 spec이 공유). 이미 있으면 읽고 이번 요청이 Proposed outcome·Non-goals 안인지 확인 — 벗어나면 스코프 이탈로 사용자에게 알린다.
   - 없으면 `intent-template.md`대로 `status: draft` 작성. Problem·Proposed outcome·Non-goals는 사용자의 말에서 가져오고, 추측으로 채울 칸은 Open questions로 돌린다. Open questions는 6단계 질문 묶음에 함께 넣는다.
   - confirmed 전이는 go 0단계가 사용자 확인을 받아 수행한다(ready는 draft까지).
4. **결정 지점 전수**: 구조(어디에·어떤 단위로) / 동작(입력·상태·엣지·실패) / 기술(라이브러리·동시성·성능) / 계약(파일 포맷·IPC·외부 API·설정 스키마) 네 관점으로 결정 지점을 나열하고 각각 분류한다.
   - (a) 코드·관례로 이미 정해짐 → 근거 좌표와 함께 spec에 기록
   - (b) 사용자 결정 필요 → 질문 후보
   - (c) 해당 없음 → spec에 `N/A — 이유`로 기록 (조용히 버리지 않는다)
5. **질문 필터 (grounds-gate)**: 질문 후보는 ① 정확한 위치 ② 이미 다뤄지지 않았다는 적극적 근거(“아마 빠졌을 것” 불충분) ③ 방치 시 구체적 결과 — 셋을 모두 댈 수 있을 때만 묻는다. 못 대면 질문하지 말고 (a) 또는 (c)로 기록.
   - 제품·도메인 결정은 사용자의 답을 끌어낸다. 기술 결정은 선택지+추천을 제시한다.
5.5. **독립 추측 탐지**: 먼저 작업 표와 risk 초안을 정한다(6단계 spec에 그대로 쓴다). intent.md가 있거나 RISKY 작업이 하나라도 있으면, 질문을 확정하기 전에 `guess-hunt.md` 프롬프트로 `Agent(subagent_type: "Explore", model: "sonnet")`를 1회 스폰한다(읽기 전용을 도구 구성으로 강제). 작성자는 자기 추측을 "합리적 이해"로 보기 때문에 직접 점검하지 않는다.
   - 결과의 각 항목은 5단계 필터를 다시 거쳐 질문 묶음에 넣거나 (a)·(c)로 재분류한다. 반박할 때는 근거(사용자 발화 인용·`파일:라인`)를 spec에 남긴다.
6. **분기**
   - 질문이 남으면 **spec을 쓰지 않는다**. 선택형은 AskUserQuestion(최대 4문항, 추천은 첫 옵션 "(Recommended)", description에 장단점 1줄) → 답을 받으면 같은 턴에 spec 작성. 자유서술형만 번호 목록으로 반환하고 종료.
   - 모두 해소되면 `spec-template.md`대로 spec.md를 `status: ready`로 쓴다. 각 작업에 `risk`와 검증 명령(`CLAUDE.local.md` 프로젝트 맵 기준)을 달고, 확인 포인트마다 `[static]`/`[run]` 태그를 붙이고, intent가 있으면 frontmatter `intent:`에 경로를 적고 확인 포인트를 Proposed outcome에서 끌어온다. 해소된 Open questions는 intent에도 ~~취소선~~+결론으로 반영.
   - 쓴 뒤 추적 점검: 요구사항마다 작업 1개 이상, 작업마다 근거가 되는 요구사항, 작업마다 확인 포인트 1개 이상. 연결 안 되는 항목이 있으면 고친다.
7. **종료 보고** (6줄 이내): 요구사항 1줄 · 요청안 평가 · 대안(있을 때만) · 리스크 · spec 경로(+intent 경로·draft) · "intent·spec 확인 후 `/go`".
   - 이 정지는 허락 요청이 아니라 턴의 산출물 경계다. 구현은 이 요청의 범위 밖이다.

## DO NOT
❌ 구현·코드 수정·브랜치 생성 ❌ 대안을 기본 진행안으로 바꿔치기 ❌ "좋아요/그 방향 맞음" 같은 승인성 말을 착수 지시로 해석 ❌ 질문이 남았는데 spec 박제 ❌ 코드로 확인한 사실과 가정을 섞어 쓰기(가정은 `가정:`으로 표기)
