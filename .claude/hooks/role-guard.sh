#!/bin/bash
# role-guard (my-machina) — PreToolUse hook (matcher: Write|Edit|MultiEdit|NotebookEdit|Artifact|ArtifactComments|ArtifactData|mcp__playwright__.*)
# 역할 에이전트의 파일 쓰기를 소유 경로로 제한한다. 에이전트 정의의 "Write는 ~에만"을 글이 아니라 판정으로 강제.
# Artifact 도구: pm·pd는 env MACHINA_PD_ARTIFACT=1(개인 계정에서만 settings.local.json)일 때만 허용, 그 외 에이전트·메인은 무개입.
#   qabot → */.specs/qa/reports/ 아래
#   pm    → */.specs/<slug>/intent.md, */.specs/<slug>/research.md
#   pd    → */.specs/<slug>/design.md, */.specs/<slug>/design/ 아래(design/render/ 제외 — 조율자 렌더 결과)
# QA 브라우저(mcp__playwright__*): qabot만(메인·다른 에이전트 deny — 앱 실행은 /qa 허가제).
#   qabot도 허용 목록 21종 밖 deny, filename 인자 deny(워크스페이스 아무 곳에나 씀), localhost·MACHINA_QA_HOSTS 밖 최상위 이동(navigate·tabs url) deny.
# <slug> = .specs 바로 아래 한 세그먼트, qa·_archive 제외(pm·pd가 QA 자산·보관본을 덮지 못하게).
# 서브에이전트 호출에만 agent_type이 실린다(메인 세션 호출엔 없음 — 2026-10-25 실측). 브라우저 판정 외엔 위 셋이 아니면 무개입.
# Bash 리다이렉트 쓰기는 여기서 보지 않는다(에이전트 정의 금지 규칙 + git-guard 범위 밖).
# 항상 exit 0, 판단 불가 시 무개입.

INPUT=$(cat 2>/dev/null) || exit 0
[ -z "$INPUT" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

# jq 1회로 값을 뽑는다(호출마다 붙는 hook이라 지연 최소화). 구분자는 US(0x1f) — 탭은 IFS 공백류라 빈 칸이 접혀 필드가 밀린다.
# 제어문자(줄바꿈·0x1f 등)가 든 값은 표식으로 바꾼다 — read가 첫 줄바꿈에서 끊겨 뒤를 못 보는 우회를 막는다(실측: filename "\n/../.claude/hooks/x.sh").
# 문자열이 아닌 값(배열·객체)도 tostring으로 판정 대상에 남긴다(jq 실패 → 빈 값 → 무개입을 막기 위해).
IFS=$'\x1f' read -r AGENT TOOL FILE FNAME URL < <(printf '%s' "$INPUT" | jq -r '[.agent_type, .tool_name, (.tool_input.file_path // .tool_input.notebook_path), .tool_input.filename, .tool_input.url] | map(if . == null then "" else (tostring | if (explode | any(. < 32 or . == 127)) then "\u0002CTRL" else . end) end) | join("\u001f")' 2>/dev/null)

# 브라우저 판정은 agent 필터보다 앞 — 메인(agent_type 없음)·다른 에이전트도 deny해야 한다
# 허용 목록(qabot.md tools와 같은 21종 — CI가 일치 검사). 버전업·WebMCP로 새 도구가 생겨도 기본 deny
QA_BROWSER_TOOLS=" browser_navigate browser_navigate_back browser_snapshot browser_take_screenshot browser_click browser_type browser_fill_form browser_press_key browser_select_option browser_hover browser_drag browser_wait_for browser_find browser_handle_dialog browser_resize browser_emulate_media browser_tabs browser_console_messages browser_network_requests browser_network_request browser_close "
case "$TOOL" in
  mcp__playwright__*)
    T="${TOOL#mcp__playwright__}"; D=deny
    if [ "$AGENT" != qabot ]; then
      R="QA 브라우저는 /qa 허가를 거친 @qabot만 씁니다."
    elif [[ "$QA_BROWSER_TOOLS" != *" $T "* ]]; then
      R="QA 브라우저에서 $T는 쓰지 않습니다(허용 목록 밖 — 페이지 내 임의 JS·로컬 파일 전달 등). 조작·관찰 도구로 진행하세요."
    elif [ -n "$FNAME" ]; then
      # filename 인자는 워크스페이스 아무 곳에나 쓸 수 있다(실측: hook 파일 덮어쓰기) — 저장은 --output-dir 자동 저장만
      R="QA 브라우저 도구의 filename 인자는 쓰지 않습니다 — 결과는 .claude/tmp/qa-browser/에 자동 저장됩니다."
    elif [ -n "$URL" ] && ! [[ "$URL" =~ ^(https?://(localhost|127\.0\.0\.1|\[::1\])(:[0-9]+)?([/?#]|$)|about:blank$) ]]; then
      # 로컬 밖 최상위 이동은 기본 deny, MACHINA_QA_HOSTS(settings.local env, 공백·쉼표 구분 호스트)만 허용.
      # ask는 서브에이전트·auto mode에서 사람에게 안 오고 자동 승인됐다(2026-10-25 실측) — 그래서 deny로 판정한다.
      # 앱의 외부 API 요청·페이지 스스로의 리다이렉트는 도구 호출이 아니라 여기서 보지 않는다(사용자 결정: 허용)
      H=""; [[ "$URL" =~ ^https?://([^/?#:@]+)(:[0-9]+)?([/?#]|$) ]] && H="${BASH_REMATCH[1]}"
      OKH=0
      if [ -n "$H" ]; then
        IFS=', ' read -ra QH <<< "${MACHINA_QA_HOSTS:-}"  # 따옴표 없는 전개는 * 등이 glob으로 펼쳐진다
        for h in "${QH[@]}"; do [ "$h" = "$H" ] && { OKH=1; break; }; done
      fi
      [ "$OKH" = 1 ] && exit 0
      R="QA 브라우저는 localhost와 허용 호스트(settings.local.json env MACHINA_QA_HOSTS)로만 이동합니다: $URL — 배포 사이트를 QA하려면 사용자가 그 호스트를 MACHINA_QA_HOSTS에 추가해야 합니다."
    else
      exit 0
    fi
    jq -cn --arg d "$D" --arg r "$R" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:$d,permissionDecisionReason:$r}}'
    exit 0 ;;
esac
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
