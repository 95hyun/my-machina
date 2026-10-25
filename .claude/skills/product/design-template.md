---
slug: <slug>
project: <project>
intent: <intent.md 경로>
kind: screen | no-screen   # 화면 있는 제품 / CLI·API·라이브러리
devices: desktop | mobile | both   # 렌더 폭 기준
created: <YYYY-MM-DD>
---

# design — <제품명>

## 도구
- 모드: 로컬 | Artifact(<링크>)
- 렌더: `design/render/` (<N>장) | 없음 — <사유>
- 프로토타입: `design/prototype/index.html` | 없음
- 참고한 Figma(PO 제공, 읽기만): <링크> | 없음

## 핵심 흐름
<대상 사용자가 시작해서 목적을 달성하기까지. S1 → S2 → …>
- 연결된 성공 기준: <intent Proposed outcome 항목>

## 디자인 토큰
<!-- tokens.css와 같은 값. 특정 회사·서비스의 디자인 시스템을 가져오지 않는다 -->
| 분류 | 토큰 | 값 | 비고 |
|---|---|---|---|
| 색 | `--color-bg` / `--color-text` / `--color-accent` / `--color-border` / `--color-danger` | | `조정 가능` |
| 글꼴 | `--font-body`, 크기 단계 `--fs-1…` | | |
| 간격 | `--space-1…` | | |
| 모서리·그림자 | `--radius-*`, `--shadow-*` | | |

## 구성
<!-- screen: 화면 목록 / no-screen: 명령·호출 목록. ID는 지적·판정·spec의 공용어 -->
### S1 <화면 또는 명령 이름>
- 파일: `design/screens/S1-<이름>.html` (no-screen: `S1-<명령>.txt`)
- 목적: <어느 흐름 단계·성공 기준에 쓰이나>
- 요소·형식: <screen: 요소(`S1/요소이름`)와 동작 / no-screen: 호출 형식, 인자>
- 상태: <screen: 빈·로딩·오류·성공(파일 분리 시 경로) / no-screen: 정상 출력·오류 메시지·종료 코드>
- 문구·예시: <screen: 핵심 문구 / no-screen: 복사해 실행 가능한 입출력 예시>
- 확인 방법: <어떤 화면·출력에서 무엇이 보여야 하는가 — PE의 [run] 포인트와 PD 판정의 기준>

## 기존 관례
- <따른 디자인 관례·CLI 스타일> (`파일:라인`) | 없음(새 프로젝트)

## 조정 가능한 기본값
- <나중에 바꿔도 되는 값> — `조정 가능`

## PO 결정 필요
- <취향·브랜드 등 제품 결정> — 선택지 A(`screens/…-a.html`) / B(`…-b.html`) | 없음
