#!/bin/bash
# role-guard (my-machina) — PreToolUse hook (matcher: Write|Edit|MultiEdit|NotebookEdit|Artifact|ArtifactComments|ArtifactData)
# 역할 에이전트의 파일 쓰기를 소유 경로로 제한한다. 에이전트 정의의 "Write는 ~에만"을 글이 아니라 판정으로 강제.
# Artifact 도구: pm·pd는 env MACHINA_PD_ARTIFACT=1(개인 계정에서만 settings.local.json)일 때만 허용, 그 외 에이전트·메인은 무개입.
#   qabot → */.specs/qa/reports/ 아래
#   pm    → */.specs/<slug>/intent.md, */.specs/<slug>/research.md
#   pd    → */.specs/<slug>/design.md, */.specs/<slug>/design/ 아래(design/render/ 제외 — 조율자 렌더 결과)
# <slug> = .specs 바로 아래 한 세그먼트, qa·_archive 제외(pm·pd가 QA 자산·보관본을 덮지 못하게).
# 서브에이전트 호출에만 agent_type이 실린다(메인 세션 호출엔 없음 — 2026-10-25 실측). 위 셋이 아니면 무개입.
# Bash 리다이렉트 쓰기는 여기서 보지 않는다(에이전트 정의 금지 규칙 + git-guard 범위 밖).
# 항상 exit 0, 판단 불가 시 무개입.

INPUT=$(cat 2>/dev/null) || exit 0
[ -z "$INPUT" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

# jq 1회로 세 값을 뽑는다(호출마다 붙는 hook이라 지연 최소화). 구분자는 US(0x1f) — 탭은 IFS 공백류라 빈 칸이 접혀 필드가 밀린다
IFS=$'\x1f' read -r AGENT TOOL FILE < <(printf '%s' "$INPUT" | jq -r '[.agent_type // "", .tool_name // "", .tool_input.file_path // .tool_input.notebook_path // ""] | join("\u001f")' 2>/dev/null)
case "$AGENT" in qabot|pm|pd) ;; *) exit 0 ;; esac

case "$TOOL" in
  Artifact|ArtifactComments|ArtifactData)
    # Artifact의 file_path는 발행할 로컬 원본이라 쓰기 경로 판정 대상이 아니다 — 모드 판정만 한다
    if [ "$AGENT" = qabot ] || [ "${MACHINA_PD_ARTIFACT:-}" = 1 ]; then exit 0; fi
    jq -cn --arg r "Artifact 모드가 꺼져 있습니다(개인 Claude 계정에서만 settings.local.json env MACHINA_PD_ARTIFACT=1). 로컬 HTML·SVG(design/)로 작업하세요." \
      '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
    exit 0 ;;
esac

[ -z "$FILE" ] && exit 0

case "$AGENT" in
  qabot) ALLOW="<project>/.specs/qa/reports/" ;;
  pm) ALLOW="<project>/.specs/<slug>/intent.md·research.md" ;;
  pd) ALLOW="<project>/.specs/<slug>/design.md·design/(render/ 제외)" ;;
esac

# bash case의 *는 /도 매칭하므로 정규식으로 세그먼트 단위 판정. 상대경로·./.. 세그먼트는 우회 방지로 deny
SLUG='/\.specs/([^/]+)/'
OK=0
# // 는 / 와 같은 경로라 제외 규칙(render/)을 비켜 갈 수 있어 함께 deny
if [[ "$FILE" == /* ]] && [[ "$FILE" != *//* ]] && ! [[ "$FILE" =~ (^|/)\.\.?(/|$) ]]; then
  case "$AGENT" in
    qabot) [[ "$FILE" =~ /\.specs/qa/reports/.+ ]] && OK=1 ;;
    pm) [[ "$FILE" =~ ${SLUG}(intent|research)\.md$ ]] && OK=1 ;;
    # render/는 조율자가 렌더한 판정 근거 — pd는 읽기만
    # APFS는 대소문자를 구분하지 않아 Render/도 같은 디렉토리 — 소문자로 비교(bash 3.2엔 ${,,}가 없다)
    pd) LOW=$(printf '%s' "$FILE" | tr '[:upper:]' '[:lower:]')
        [[ "$FILE" =~ ${SLUG}(design\.md$|design/.+) ]] && ! [[ "$LOW" =~ ${SLUG}design/render/ ]] && OK=1 ;;
  esac
  if [ "$OK" = 1 ] && [ "$AGENT" != qabot ]; then
    case "${BASH_REMATCH[1]}" in qa|_archive) OK=0 ;; esac
  fi
fi
[ "$OK" = 1 ] && exit 0

jq -cn --arg r "$AGENT 은(는) 소유 경로($ALLOW)에만 쓸 수 있습니다: $FILE — 그 밖의 변경은 반환 리포트로 조율자에게 요청하세요." \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
exit 0
