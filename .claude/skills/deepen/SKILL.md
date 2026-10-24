---
name: deepen
description: 해커톤 3단계 — 고른 후보 2~3개를 researcher가 병렬 리서치해 원페이저(페르소나·경쟁·시장·BM)를 만들고, redteam이 한 번에 공격한 뒤 한 화면 비교로 최종 1개를 고르게 한다.
argument-hint: "<후보 id 2~3개, 예: A3 C1>"
disable-model-invocation: true
model: opus
---

# /deepen — 타깃·리서치·검증

먼저 `hackathon/RULES.md`를 Read한다(해커톤 공통 규칙 — 이 세션에서 이미 읽었으면 생략).

## 0. 준비
- `hackathon/runs/CURRENT`를 Read → `$RUN`. `$RUN/02-problems.md`(문제 정의 문장 + scout 줄)를 Read하고, 인자 id의 원본 JSON은 `./hackathon/bin/ideas <id들>`로 얻는다. id가 없으면 02-problems.md에 있는 것 전부(최대 3개).
- 4개 이상이면 3개로 줄여 달라고 하고 멈춘다(비용·시간).
- **재진입**: 이미 있는 `03-onepager-<id>.md`는 researcher를 다시 돌리지 않는다. `03-redteam.md`가 있으면 레드팀도 건너뛴다. `03-final.md`가 있으면 보여주고 "다음: `/mvp`". 사람이 "다시"라고 하면 예외.
- `./hackathon/bin/mark deepen start`.

## 1. 리서치 — researcher 병렬 (한 메시지에서 동시 스폰, 최대 3)
`subagent_type: "hk-researcher"`, 후보당 1개. 프롬프트: 후보 JSON + 문제 정의 문장 + scout 줄, VC 주제 원문, `$RUN/input-card.md`, `hackathon/templates/onepager.md`, 출력 `$RUN/03-onepager-<id>.md`.
반환 4줄만 받고, 받는 즉시 `$RUN/03-returns.md`에 후보별로 그대로 추가한다(재진입 때 비교표 원천). **원페이저 본문을 메인에서 다시 요약·재작성하지 않는다.**

## 2. 레드팀 — redteam 1회 (모든 원페이저 일괄)
`subagent_type: "hk-redteam"`, 프롬프트: 원페이저 경로 전부, VC 주제 원문(+ `01-topics.md`의 "VC가 볼 것" 한 줄), 출력 `$RUN/03-redteam.md`. 반환 표만 받는다.

## 3. 게이트 2 — 한 화면 비교
`$RUN/03-returns.md`(researcher 반환의 `요약:`·`판정:` 줄. 없는 후보만 원페이저 앞 3줄과 `## 리스크` 2줄을 Read)와 redteam 반환 표만으로 `$RUN/03-compare.md`를 쓰고 보여준다. 원페이저 본문을 다시 읽지 않는다:

| 후보 | 페르소나·국가 | 와우 장면 | 누가 얼마 내나 | 최대 경쟁자 | 이기는 틈 (레드팀 판정) | 레드팀 판정 | 가장 약한 고리 |
|---|---|---|---|---|---|---|---|

- 표 아래: 각 원페이저 파일 경로(사람이 직접 열어 보게).
- 안내: "최종 1개를 골라 주세요. 레드팀 '수정 후 진행'이면 그 수정을 반영할지도 함께." 그리고 멈춘다.

## 4. 확정
선택을 받으면 `$RUN/03-final.md`에 `확정: <id> <이름>` + 반영할 레드팀 수정 + 해당 원페이저 경로를 쓴다. `./hackathon/bin/mark deepen end`가 출력하는 **기획 시작부터 경과 시간**을 보고한다(45분 하드캡 대비). "다음: `/mvp`".
