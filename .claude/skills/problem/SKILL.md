---
name: problem
description: 해커톤 2단계 — 확정 주제에서 문제·서비스 후보를 렌즈 3개로 병렬 발산하고 중복 제거·하드 필터·채점 후, scout가 근거·경쟁·이기는 틈을 정찰한 shortlist를 점수 없이 사람이 고르게 한다.
argument-hint: "[렌즈당 개수, 기본 14]"
disable-model-invocation: true
model: opus
---

# /problem — 문제 정의

먼저 `hackathon/RULES.md`를 Read한다(해커톤 공통 규칙 — 이 세션에서 이미 읽었으면 생략).

## 0. 준비
- `hackathon/runs/CURRENT`를 Read → `$RUN`. `$RUN/01-topics.md`에서 `확정 주제`를 읽는다. 없으면 `/topic`부터 하라고 하고 멈춘다.
- **재진입**: `$RUN/02-problems.md`가 있으면 그 내용을 보여주고 "다음: `/deepen`". `$RUN/02-candidates.md`가 있으면 3.5단계부터 — `02-scout-1.md`·`02-scout-2.md` 중 **없는 번호만** 스폰하고, 둘 다 있으면 바로 게이트 1. 사람이 "다시"라고 하지 않는 한 ideator·scout를 다시 스폰하지 않는다.
- `./hackathon/bin/mark problem start`. `$RUN/input-card.md` Read.

## 1. 금지 목록 (메인, 짧게)
이 주제에 대해 아무 팀이나 떠올릴 **가장 흔한 답 10개**를 `$RUN/banned.md`에 한 줄씩 쓴다. 유명 서비스(ChatGPT 사진 번역 등)로 이미 되는 것을 포함한다. 화면에는 보여주지 않는다.

## 2. 발산 — ideator 3개 병렬 (한 메시지에서 동시 스폰)
`subagent_type: "hk-ideator"`, 각각 N=인자(기본 14), 출력 `$RUN/ideas-<렌즈>.jsonl`, id 접두사 A/B/C:
- **A 문제 우선**: 이 주제의 대상이 실제로 돈·시간을 잃는 순간에서 출발(국가 × 상황 × 고통).
- **B 기술 우선**: 최근 1~2년 사이 AI·API로 *이제야* 싸게 가능해진 것에서 출발. 단 금지 목록의 챗봇·번역·튜터 류 제외.
- **C 팀·차익 우선**: 입력 카드의 팀 강점·직접 겪은 고통·손 시드, 그리고 한국에서 검증된 방식을 다른 국가로 옮기는 차익에서 출발.
프롬프트에 VC 주제 원문, 입력 카드 경로, 금지 목록 경로를 넣는다. 반환은 "파일 N줄"만 받는다.

## 3. 정리 (메인)
`./hackathon/bin/ideas`(후보당 한 줄 압축)로 읽는다. **jsonl 원본을 Read·cat하지 않는다**(토큰). 원문이 필요한 후보만 `./hackathon/bin/ideas <id> <id>`.
`$RUN/02-candidates.md`에 쓴다:
1. **중복 제거**: 페르소나·해법이 사실상 같은 것은 대표 1개로 묶는다(묶인 id 기록).
2. **하드 필터**: `hackathon/templates/rubric.md` 하드 필터로 탈락 + 사유 한 줄.
3. **채점**: 남은 후보를 루브릭 기준 1~5 + 가중합. 점수는 **파일에만** 쓴다.
4. 상위 8개를 shortlist로 고르되, 렌즈 A/B/C가 최소 1개씩 들어가게 한다.
- 파일 순서: ① shortlist(무작위 순서, 점수 없음) ② 탈락·묶음 기록 ③ **점수표는 맨 아래** — Write 미리보기에 점수가 먼저 보이지 않게.

## 3.5 정찰 — scout 2개 병렬 (한 메시지에서 동시 스폰)
shortlist 8개를 4개씩 나눠 `subagent_type: "hk-scout"` 2개. 프롬프트: 해당 후보의 `hackathon/bin/ideas` 한 줄들, VC 주제 원문, 출력 `$RUN/02-scout-1.md`·`02-scout-2.md`. 반환은 "파일 N줄"만.
scout 결과는 점수를 바꾸지 않는다(사람이 보는 근거 정보).

## 4. 게이트 1 — 점수 없이 고르기
두 scout 파일을 Read하고, shortlist 8개를 **무작위 순서, 점수·순위 없이** 보여준다. 맨 위에 한 줄:
> 후보는 모델 지식으로 만든 **가설**이다. 근거·경쟁은 후보당 검색 1~2회 정찰 결과이고, 깊은 검증은 `/deepen`에서 한다.
```
[A3] 제목 — 국가·페르소나 / 문제 한 줄 / 데모 장면 한 줄
     근거: … / 경쟁: … / 틈: … (⚠️겹침)
```
안내: "회의로 2~3개 골라 id로 알려 주세요(점수는 고른 뒤 공개)." 그리고 멈춘다.

## 5. 대조·문제 정의
- 선택을 받으면 그제야 shortlist 점수표와 탈락 사유 요약(3줄)을 공개하고, 사람 선택과 점수 상위가 다르면 차이를 한 줄로 짚는다. 결정은 바꾸지 않는다.
- 선택된 후보마다 문제 정의 문장(`hackathon/RULES.md` 형식)을 채워 `$RUN/02-problems.md`에 쓴다. 각 후보 아래에 scout 줄(근거·경쟁·틈)을 그대로 붙인다. 측정 가능한 결과는 숫자로, 근거 없는 수치는 `가정`.
- `./hackathon/bin/mark problem end` 경과 시간 표시, "다음: `/deepen <id들>`".
