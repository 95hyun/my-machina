---
name: product
description: '제품·서비스 하나를 PM·PD·PE 역할 체계로 기획→설계·spec→구현·검증까지 진행. 역할끼리 교차 검증·재작업하고 PO(사용자)는 게이트 3회에서만 결정한다.'
argument-hint: '[project|새 이름] <만들고 싶은 것>'
disable-model-invocation: true
---

# Product — PM·PD·PE 역할 협업 (PO = 사용자)

메인 세션 = **조율자 + PE**. 조율자는 역할을 띄우고, 교차 검증을 돌리고, 게이트 질문과 충돌 목록을 만든다. 제품 결정은 내리지 않는다.
작은 수정·단건 기능은 이 스킬이 아니라 `/ready` → `/go`다.

| 역할 | 누가 | 소유 산출물 (`<project>/.specs/<slug>/`) |
|---|---|---|
| PO | 사용자 | 게이트 승인·제품 결정 |
| PM | `@pm` (이름 붙여 세션 내내 유지) | `intent.md`, `research.md` |
| PD | `@pd` (이름 붙여 세션 내내 유지) | `design.md`, `design/` |
| PE | 메인 — 기존 ready·go·qa 절차 그대로, 구현 위임은 `@coder` | `spec.md`, 코드 |
| 판정자 | 매번 새 `Explore`(`model: "opus"`) + `verify-pm.md`·`verify-pd.md` | 없음(읽기 전용) |
| 조사 | `@researcher`(sonnet, 웹 검색만) — 조율자가 주제별로 띄움 | 없음(텍스트 반환 → pm이 `research.md`) |

쓰기 범위는 `role-guard.sh` hook이 강제한다(pm·pd·qabot은 소유 경로 밖 쓰기 deny).

## 공통 규칙
- **게이트 밖에서는 PO에게 묻지 않는다.** 예외는 CLAUDE.md 즉시 멈춤 사유 중 breaking change·사용자 데이터 삭제·이동·배포물 공개·남의 repo push(요구 모호는 게이트가 흡수)와, 아래 표에서 "유지"로 배정한 지점뿐이다.
- **따르는 절차 안의 질문·정지 지점 배정** — ready·go·qa를 Read해 따를 때 그 안의 질문·정지는 이 표대로 처리한다(절차 재서술이 아니라 배정).

  | 지점 | /product 안에서 |
  |---|---|
  | ready 3.5 스코프 이탈 | 게이트①로 되돌린다(intent 재작업) |
  | ready 6 질문, ready 7 정지, ready DO NOT "질문 남았는데 spec 박제" | 묻지 않고 spec에 `미결 — 게이트②`로 표시한 채 쓰고, 정지하지 않고 B4로 간다 |
  | go 1 남의 변경·worktree REBIND | **유지**(즉시 멈추고 묻는다 — git 사고 방지) |
  | go 2 spec에 없는 결정 갈림길 | 기술 = PE가 정하고 review-log에 근거 기록. 제품 = 그 작업만 보류하고 나머지를 진행, 게이트③ 충돌 목록. breaking change = 즉시 멈춤 |
  | qa 2 recipe 초안 | B3에서 PE가 작성해 게이트②에 함께 제시. 게이트② 뒤에 새로 필요해지면 qa 4 질문 **유지** |
  | qa 3 실행 영향 | 게이트②에서 승인하지 않은 실데이터 변경·띄워 둔 인스턴스 종료가 C에서 드러나면 qa 4 질문 **유지** |
  | qa 6·DO NOT "❌ 자동 수정 금지" | 게이트② 승인 범위 안의 기술·형식 ❌는 C4에서 수정한다. 제품 판단이 필요한 ❌는 게이트③ |
  | qa 7 학습 회수 승인 | 게이트③ 문항으로 합친다 |
- **게이트 문항이 4개를 넘으면** AskUserQuestion을 4문항 단위로 연속해서 묻는다(한 게이트 = 연속 묶음). 제품 문항을 먼저, 기술 문항은 뒤에, "이대로 승인" 문항은 마지막 묶음에 둔다. 항목을 조용히 빼지 않는다.
- **이견 분류** — 판정·검토에서 나온 지적을 둘로 나눈다.
  - 기술·형식(실현성, 누락, 표기 불일치, 증거 부족): 소유 역할이 고친다.
  - 제품(대상·범위·우선순위·성공 기준·외형 취향): 고치지 않고 다음 게이트의 **충돌 목록**에 올린다.
- **재작업 루프**: 지적 → 소유 역할 수정(PM·PD = 같은 인스턴스에 SendMessage, PE = 메인) → 같은 종류의 판정을 **새 인스턴스로** 다시 돌린다. 게이트마다 합계 최대 2회(B는 design·spec 루프가 2회를 나눠 쓴다). 2회 뒤에도 남은 지적은 충돌 목록(기술 = 선택지 + 추천)으로 올린다.
- **판정은 근거로만.** 근거(좌표·스크린샷·출력·exit code) 없는 ✅는 ⛔로 격하한다. 산출물 작성자는 자기 산출물을 판정하지 않는다.
- **review-log.md**(조율자 소유): 단계·회차·판정자·지적·조치·남은 것을 한 줄씩 append한다. 재개 기준이다.
  `YYYY-MM-DD HH:MM | <A|B|C>-<회차> | <판정자> | ✅N ❌N ⛔N | <지적 요약> → <조치 | 충돌 목록>`
- 날짜는 `date +%F`, 시각은 `date +%H:%M` 실출력을 쓴다.

## 0. 준비
1. 대상: 인자의 첫 단어가 워크스페이스의 기존 프로젝트면 그 repo. 아니면 새 제품 — 인자에서 짧은 영문 kebab 이름을 만들어 `<workspace>/<name>/`을 만들고 `git init`, `.specs/`를 `.git/info/exclude`에 등록한다(remote는 만들지 않는다. 이름은 게이트①에서 바꿀 수 있다). slug = 제품 이름.
2. `<project>/.specs/<slug>/review-log.md`가 있으면 **재개**: 마지막 줄의 단계부터 이어간다. 이름 붙인 pm·pd가 이미 없으면 다시 띄우고 해당 산출물을 Read하게 한다.
3. PO 발화 원문 목록을 만든다(이번 요청과 이전 대화의 관련 발화, 요약 금지). 모든 역할 프롬프트에 그대로 넣는다.
4. **디자인 도구 모드**: `echo "${MACHINA_PD_ARTIFACT:-0}"`가 `1`이면 Artifact 모드(개인 Claude 계정에서 사용자가 켠 경우), 아니면 로컬 모드. pd·pm 프롬프트에 모드를 적는다. 꺼져 있을 때 pd·pm의 Artifact 호출은 role-guard가 막는다.

## A. 기획 → 게이트①
0. 조사(선택): PO 발화에서 조사가 필요한 주제(경쟁 서비스·대상 사용자 관례·기술 제약)를 최대 3개 뽑아 `Agent(subagent_type: "researcher")`를 주제마다 **병렬로** 띄운다. 프롬프트 = 주제 1개 + 제품 한 줄 설명. 주제가 없거나 단순한 제품이면 건너뛴다(구독 사용량). 결과는 1단계 pm 프롬프트에 원문으로 넣는다. 하위 에이전트가 하위 에이전트를 띄울 수 없어 조사는 조율자가 띄운다.
1. `Agent(subagent_type: "pm", name: "pm-<slug>")`: PO 발화 원문, intent 양식 경로(`.claude/skills/ready/intent-template.md`), 출력 경로, 기존 프로젝트면 README·CLAUDE.md·`docs/decisions.md` 경로.
2. 검토(병렬):
   - PE(메인): 실현성·비용 — 성공 기준이 증거로 판정 가능한가, 스택·플랫폼 제약, 큰 비용 항목.
   - `Agent(subagent_type: "pd", name: "pd-<slug>")`: intent를 읽고 사용자 관점 검토만(이 단계에선 쓰지 않음) — 대상 사용자·핵심 장면이 설계 가능한 수준으로 구체적인가.
3. 기술·형식 지적은 pm에 SendMessage로 재작업(≤2회).
4. **게이트①** (AskUserQuestion — 4문항 초과 시 공통 규칙의 연속 묶음): 첫 문항 = intent 요약 3~5줄(대상·핵심 장면·성공 기준·Non-goals) + "이대로 승인 (Recommended)" / "수정 요청". 나머지 문항 = 충돌 목록과 pm이 올린 "PO 결정 필요"(제품 = 열린 질문, 기술 = 선택지 + 추천 첫 옵션). 새 제품이면 이름을 확인하는 문항을 한 줄 넣는다.
   - 승인 → intent `status: confirmed`, `updated:` 갱신. 수정 요청 → pm 재작업 후 게이트① 다시(PO 요청은 재작업 상한에 세지 않는다).

## B. 설계 + spec → 게이트②
1. pd에 SendMessage: confirmed intent 경로, `.claude/skills/product/design-template.md` 경로, 출력 경로(`design.md`·`design/`), 도구 모드, 기존 프로젝트의 디자인 관례 위치. PO가 Figma 링크를 줬으면 조율자가 먼저 읽어(Figma MCP 안내문의 사전 절차를 따른다) `design/ref/`에 넣고 그 경로를 넘긴다 — 디자인 정보·메타데이터는 텍스트 그대로, 스크린샷은 조율자가 보고 요점을 `ref/notes.md`에 텍스트로(이미지를 파일로 저장할 수 있으면 함께). Figma는 읽기만.
   - pd 반환에 `렌더 필요: 예`면 조율자가 `bash .claude/skills/product/render.sh <project>/.specs/<slug>/design`을, 이어서 `node .claude/skills/product/a11y-check.mjs <같은 경로>`(대비·터치 영역·폭별 넘침 → `render/a11y.json`)를 실행한다. exit 2(브라우저 없음)·실패는 review-log에 `폴백: render — <사유>`로 남기고 다음 게이트 문항에 1줄 고지한다. **B단계 첫 렌더 직후 한 번만** pd에 SendMessage로 "`render/` 확인 후 어긋난 곳 수정 + `render/a11y.json` 위반 수정(`판정불가`는 렌더 이미지로 직접 확인)"을 보내고(자기 점검 — 재작업 상한에 세지 않는다, review-log에 `자기점검`), 수정이 있었으면 다시 렌더·a11y 점검한 뒤 2번으로 간다.
2. 설계 판정(병렬): `verify-pm.md`(design 모드, 렌더 경로 포함) + PE(메인) 실현성 — 화면 HTML·프로토타입의 상호작용이 스택으로 구현 가능한가, 비용이 큰 요소. 지적은 `[S2/요소] 지적 — 근거` 형식으로 pd에 SendMessage(≤2회), 재작업 뒤엔 다시 렌더·a11y 점검한다. 남은 a11y 위반은 PE가 기술·형식 지적으로 함께 넘긴다.
3. PE spec: `.claude/skills/ready/SKILL.md`를 Read해 그 절차대로 spec.md를 쓴다(intent·design.md가 입력, 5.5 독립 추측 탐지 포함). 질문·정지 지점은 공통 규칙의 배정 표대로. design의 각 "확인 방법"을 `[run]` 확인 포인트로 옮긴다. UI 작업마다 대응하는 `design/screens/<ID>-*.html`·`tokens.css`를 좌표로 적어 PE·@coder의 구현 기준으로 삼는다.
   - 검증 명령: `CLAUDE.local.md` 프로젝트 맵에 없는 프로젝트(새 제품 등)면 spec에 `제안:`으로 적어 게이트②에서 승인받는다(개인 맵은 직접 쓰지 않고 종료 보고에서 등록을 제안).
   - `[run]` 포인트가 있으면 `<project>/.specs/qa/recipe.md`를 확인한다. 없으면 qa 2단계 기준으로 초안(빌드·실행·종료 명령, 관찰 수단, 실데이터 보호, 추측 명령은 `미확인`)을 쓰고, 있으면 Read해 이번 `[run]`에 필요한 변경분만 만든다(덮어쓰지 않는다). 초안·변경분 모두 게이트②에 제시한다.
4. spec 판정: `verify-pd.md`(spec 모드, 화면 ID 기준). 기술·형식 지적 → 메인이 spec 수정(2번 설계 루프와 합계 ≤2회).
5. **게이트②** (AskUserQuestion — 4문항 초과 시 연속 묶음): 승인 문항 = 설계 요약(핵심 흐름 + 화면 ID 목록 + 렌더 이미지·프로토타입 경로, Artifact 모드면 링크) + spec 요약(작업 수·RISKY 수·확인 포인트 수·검증 명령) + recipe 요약(실행·종료 명령, 실데이터 영향) + 경로 + "이대로 승인 (Recommended)" / "수정 요청". 나머지 = 충돌 목록, spec의 `미결 — 게이트②`, pd의 "PO 결정 필요"(디자인 토큰 취향은 비교 화면 경로와 함께 선택지로), 폴백 고지.
   - 이 승인은 **C단계의 구현과 QA 실행(빌드·실행·관찰)까지 허가**한다고 문항에 명시한다. 실데이터를 바꾸는 QA가 필요하면 그 항목을 별도 문항으로 묻는다.
   - 승인 → 답을 spec·design에 반영하고 `미결 —` 표시를 모두 없앤다(남아 있으면 go 0단계가 구현을 막는다). 수정 요청 → 해당 소유 역할 재작업 후 게이트② 다시.

## C. 구현·검증 → 게이트③
1. `.claude/skills/go/SKILL.md`를 Read해 그 절차대로 구현·검증·리뷰한다(0단계 intent 게이트는 이미 confirmed).
2. `[run]` 포인트가 있으면 `.claude/skills/qa/SKILL.md`를 Read해 그 절차대로 진행한다. 단 4단계 허가 질문은 게이트② 승인으로 대신하고, 위임 스펙 첫 줄은 `허가: /product 게이트② 승인 <YYYY-MM-DD>`로 쓴다.
3. 결과 판정(병렬): `verify-pd.md`(result 모드 — QA 스크린샷 ↔ `design/render/<ID>-*.png` 나란히) + `verify-pm.md`(result 모드). 지적은 화면 ID로.
4. 기술·형식 지적 → 메인이 go 절차로 수정 → `[static]` 전체와 영향받는 `[run]` 재실측 → 같은 판정을 새 인스턴스로(≤2회).
5. **게이트③ 수락** (AskUserQuestion — 4문항 초과 시 연속 묶음): 성공 기준별 ✅/❌/⛔ 표(근거 경로 포함) + 남은 충돌 목록(보류한 제품 결정 포함) + qa 7 학습 회수 반영안 + "수락 (Recommended)" / "수정 요청" / "보류".
   - 수락 → spec 결과에 기록하고 "확인 후 `/ship`"으로 종료. 이 스킬은 커밋하지 않는다.
   - 수정 요청 → 요청 범위에 따라 A·B·C 중 해당 단계로 돌아간다(제품 결정이 바뀌면 A부터).

## 종료 보고
- 게이트별 결정 요약, 재작업 횟수(단계별), 미검증 항목, 산출물 경로(intent·design·spec·review-log), 다음 단계 1줄.

## DO NOT
❌ 게이트 밖 PO 질문(공통 규칙의 예외 제외) ❌ 조율자가 제품 결정을 내림 ❌ 작성자가 자기 산출물 판정 ❌ 재작업 상한 초과 반복 ❌ 커밋·push(`/ship` 담당) ❌ ready·go·qa 절차를 이 파일에서 다시 쓰기(파일을 Read해 따른다)
