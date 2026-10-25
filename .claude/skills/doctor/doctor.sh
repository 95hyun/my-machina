#!/bin/bash
# doctor (my-machina) — 클론한 워크스페이스에서 하네스를 쓸 수 있는지 진단만 한다(파일 쓰기 없음).
# 사용: bash .claude/skills/doctor/doctor.sh   출력: 항목별 ✅/⚠️/❌ + 해결 명령, 마지막 줄 요약. ❌가 있으면 exit 1.
# 의존: bash·표준 유틸. jq·git·python3는 있으면 쓰고, 없으면 그 항목을 ❌로 보고하고 계속한다.

ROOT=$(cd "$(dirname "$0")/../../.." 2>/dev/null && pwd -P) || { echo "❌ 실행 위치 — 워크스페이스 루트를 찾지 못함"; exit 1; }
NF=0; NW=0
have() { command -v "$1" >/dev/null 2>&1; }
# line <✅|⚠️|❌> <이름> <상세> [해결]
line() {
  case "$1" in ❌) NF=$((NF+1)) ;; ⚠️) NW=$((NW+1)) ;; esac
  printf '%s %s — %s\n' "$1" "$2" "$3"
  [ -n "$4" ] && printf '   해결: %s\n' "$4"
  return 0
}
# JSON 유효성 / .env.K 읽기 — jq 우선, 없으면 python3
json_ok() {
  if have jq; then jq -e . "$1" >/dev/null 2>&1
  elif have python3; then python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$1" >/dev/null 2>&1
  else return 2; fi
}
json_env() {
  if have jq; then jq -r --arg k "$2" '.env[$k] // empty' "$1" 2>/dev/null
  elif have python3; then python3 -c 'import json,sys; print((json.load(open(sys.argv[1])).get("env") or {}).get(sys.argv[2]) or "")' "$1" "$2" 2>/dev/null
  fi
}
gh_user() { awk '/^github\.com:/{f=1;next} /^[^[:space:]]/{f=0} f && /^    user:/{print $2; exit}' "$1/hosts.yml" 2>/dev/null; }

LOCAL="$ROOT/.claude/settings.local.json"

# ① 실행 위치
if [ ! -f "$ROOT/.claude/hooks/git-guard.sh" ]; then
  line ❌ "실행 위치" "$ROOT/.claude/hooks/git-guard.sh 없음 — 워크스페이스 루트가 아님" "이 repo를 clone한 디렉토리에서 bash .claude/skills/doctor/doctor.sh"
else
  line ✅ "실행 위치" "$ROOT"
fi

# ② 도구
MISS=; for t in bash git jq python3; do have "$t" || MISS="$MISS $t"; done
if [ -n "$MISS" ]; then
  line ❌ "도구" "없음:$MISS" "brew install$(printf '%s' "$MISS" | sed 's/ bash//')"
else
  line ✅ "도구" "bash·git·jq·python3"
fi
have gh || line ⚠️ "도구(gh)" "gh 없음 — gh 계정 검사·PR 작업 불가" "brew install gh"

# ③ 하네스 무결성
PROB=
json_ok "$ROOT/.claude/settings.json"; rc=$?
[ $rc -eq 1 ] && PROB="$PROB settings.json JSON 오류;"
[ $rc -eq 2 ] && PROB="$PROB settings.json 검사 불가(jq·python3 없음);"
for h in git-guard review-suggest; do
  f="$ROOT/.claude/hooks/$h.sh"
  if [ ! -f "$f" ]; then PROB="$PROB $h.sh 없음;"; continue; fi
  bash -n "$f" 2>/dev/null || { PROB="$PROB $h.sh 문법 오류;"; continue; }
  case $h in
    git-guard) IN='{"tool_input":{"command":"ls"},"session_id":"doctor"}' ;;
    *) IN='{"tool_input":{"file_path":"/nonexistent/doctor-noop"},"session_id":"doctor"}' ;;
  esac
  OUT=$(printf '%s' "$IN" | CLAUDE_PROJECT_DIR="$ROOT" bash "$f" 2>&1); rc=$?
  [ $rc -ne 0 ] && PROB="$PROB $h.sh noop exit $rc;"
  [ $rc -eq 0 ] && [ -n "$OUT" ] && PROB="$PROB $h.sh noop 출력 있음;"
done
if [ -n "$PROB" ]; then
  line ❌ "하네스 무결성" "${PROB# }" "git -C \"$ROOT\" status .claude 로 변경 확인, 필요하면 git -C \"$ROOT\" diff .claude"
else
  line ✅ "하네스 무결성" "settings.json·hook 2개 정상"
fi

# ④ settings.local.json
LOCAL_OK=
if [ ! -f "$LOCAL" ]; then
  line ⚠️ "settings.local.json" "없음 — 계정 검사(MACHINA_EMAIL·MACHINA_GH)가 꺼진 상태(선택 사항)" "README '개인 설정' 예시대로 .claude/settings.local.json 작성: {\"env\":{\"MACHINA_EMAIL\":\"you@example.com\",\"MACHINA_GH\":\"your-github-id\",\"GH_CONFIG_DIR\":\"<HOME>/.config/gh-personal\"}}"
else
  json_ok "$LOCAL"; rc=$?
  if [ $rc -eq 1 ]; then
    line ❌ "settings.local.json" "JSON 오류" "jq . .claude/settings.local.json 로 오류 위치 확인 후 수정"
  elif [ $rc -eq 2 ]; then
    line ❌ "settings.local.json" "검사 불가(jq·python3 없음)" "brew install jq"
  else
    LOCAL_OK=1
    D=$(json_env "$LOCAL" GH_CONFIG_DIR)
    case "$D" in
      "") line ✅ "settings.local.json" "JSON 정상 (GH_CONFIG_DIR 미설정)" ;;
      /*) if [ -d "$D" ]; then line ✅ "settings.local.json" "JSON 정상, GH_CONFIG_DIR 존재"
          else line ❌ "settings.local.json" "GH_CONFIG_DIR($D) 디렉토리 없음" "GH_CONFIG_DIR=$D gh auth login"; fi ;;
      *) line ❌ "settings.local.json" "GH_CONFIG_DIR($D)가 절대경로 아님 — env 값은 셸이 해석하지 않음(~ 불가)" "GH_CONFIG_DIR를 절대경로로 수정" ;;
    esac
  fi
fi

# ⑤ CLAUDE.local.md
if [ ! -f "$ROOT/CLAUDE.local.md" ]; then
  line ⚠️ "CLAUDE.local.md" "없음 — /ready·/go가 프로젝트 검증 명령을 찾지 못함" "README의 CLAUDE.local.md 예시(## 프로젝트 맵 표)로 $ROOT/CLAUDE.local.md 작성"
elif grep -q '^## 프로젝트 맵' "$ROOT/CLAUDE.local.md" && grep -qE '^\|.*\|' "$ROOT/CLAUDE.local.md"; then
  line ✅ "CLAUDE.local.md" "프로젝트 맵 표 있음"
else
  line ⚠️ "CLAUDE.local.md" "'## 프로젝트 맵' 표 없음" "README 예시의 '## 프로젝트 맵 (검증 명령 = /go 완료 증거)' 표 추가"
fi

# ⑥ 계정 — 값은 프로세스 env 우선, 없으면 settings.local.json(터미널 실행 대비)
FILEONLY=; ME_EMAIL=; ME_GH=; GHD=
for k in MACHINA_EMAIL MACHINA_GH GH_CONFIG_DIR; do
  v="${!k}"
  if [ -z "$v" ] && [ -n "$LOCAL_OK" ]; then
    v=$(json_env "$LOCAL" "$k"); [ -n "$v" ] && FILEONLY="$FILEONLY $k"
  fi
  case $k in MACHINA_EMAIL) ME_EMAIL="$v" ;; MACHINA_GH) ME_GH="$v" ;; *) GHD="$v" ;; esac
done
if [ -z "$ME_EMAIL$ME_GH" ]; then
  line ⚠️ "계정" "MACHINA_EMAIL·MACHINA_GH 미설정 — git-guard 신원·gh 계정 검사 꺼짐(선택 사항)" "강제하려면 .claude/settings.local.json env에 MACHINA_EMAIL·MACHINA_GH 추가(README '개인 설정')"
else
  if [ -n "$ME_EMAIL" ]; then
    if ! have git; then
      line ❌ "계정(커밋 신원)" "git 없음 — 검사 불가" "brew install git"
    else
      BAD=; N=0
      for g in "$ROOT"/*/.git; do
        [ -e "$g" ] || continue
        r=$(dirname "$g"); N=$((N+1))
        e=$(git -C "$r" config user.email 2>/dev/null)
        [ "$e" != "$ME_EMAIL" ] && BAD="$BAD $(basename "$r")(${e:-없음})"
      done
      if [ -n "$BAD" ]; then
        line ❌ "계정(커밋 신원)" "user.email ≠ MACHINA_EMAIL($ME_EMAIL):$BAD" "~/.gitconfig에 [includeIf \"gitdir:$ROOT/\"] path = <user.email=$ME_EMAIL 을 담은 파일> 추가, repo 로컬 user.email 덮어쓰기는 git -C <repo> config --unset user.email"
      else
        line ✅ "계정(커밋 신원)" "하위 repo ${N}개 모두 $ME_EMAIL"
      fi
    fi
  fi
  if [ -n "$ME_GH" ]; then
    D="${GHD:-$HOME/.config/gh}"
    U=$(gh_user "$D")
    if [ "$U" = "$ME_GH" ]; then
      line ✅ "계정(gh)" "$D 활성 계정 $ME_GH"
    else
      line ❌ "계정(gh)" "$D 활성 계정 '${U:-없음}' ≠ MACHINA_GH($ME_GH)" "GH_CONFIG_DIR=$D gh auth login  ($ME_GH 로 로그인)"
    fi
  fi
fi
[ -n "$FILEONLY" ] && line ⚠️ "계정 값 출처" "env에 없고 settings.local.json에만 있음:$FILEONLY — hook은 env만 보므로 터미널 결과와 세션이 다를 수 있음" "워크스페이스 루트 Claude 세션에서 /doctor 로 다시 확인"

# ⑦ 공유자용 누수 — 개인값·$HOME이 추적 파일에 들어갔는지
if ! have git || ! git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  line ⚠️ "누수" "git 없음 또는 git repo 아님 — 검사 생략" "git clone 으로 받은 워크스페이스에서 다시 실행"
else
  PATS=(); LABELS=()
  if [ -n "$LOCAL_OK" ]; then
    if have jq; then
      while IFS=$'\t' read -r k v; do case $k in MACHINA_EMAIL|MACHINA_GH|GH_CONFIG_DIR) [ -n "$v" ] && { PATS+=("$v"); LABELS+=("$k"); } ;; esac; done \
        < <(jq -r '(.env // {}) | to_entries[] | [.key, (.value|tostring)] | @tsv' "$LOCAL" 2>/dev/null)
    elif have python3; then
      while IFS=$'\t' read -r k v; do case $k in MACHINA_EMAIL|MACHINA_GH|GH_CONFIG_DIR) [ -n "$v" ] && { PATS+=("$v"); LABELS+=("$k"); } ;; esac; done \
        < <(python3 -c 'import json,sys
for k,v in (json.load(open(sys.argv[1])).get("env") or {}).items(): print(f"{k}\t{v}")' "$LOCAL" 2>/dev/null)
    fi
  fi
  [ -n "$HOME" ] && { PATS+=("$HOME"); LABELS+=('$HOME'); }
  if [ ${#PATS[@]} -eq 0 ]; then
    line ✅ "누수" "검사할 개인값 없음"
  else
    ARGS=(); for p in "${PATS[@]}"; do ARGS+=(-e "$p"); done
    HITS=$(cd "$ROOT" && git ls-files -z | xargs -0 grep -noIF "${ARGS[@]}" -- 2>/dev/null)
    if [ -z "$HITS" ]; then
      line ✅ "누수" "추적 파일에 settings.local.json 값·\$HOME 없음"
    else
      CNT=$(printf '%s\n' "$HITS" | wc -l | tr -d ' ')
      line ⚠️ "누수" "추적 파일에 개인값 ${CNT}건 — 공유 전 제거(<HOME>·you@example.com 같은 자리표시자로)" "아래 파일:라인을 수정"
      printf '%s\n' "$HITS" | head -15 | while IFS= read -r h; do
        m="${h#*:}"; m="${m#*:}"; loc="${h%":$m"}"; lab="?"
        for i in "${!PATS[@]}"; do [ "${PATS[$i]}" = "$m" ] && { lab="${LABELS[$i]}"; break; }; done
        printf '   - %s (%s)\n' "$loc" "$lab"
      done
      [ "$CNT" -gt 15 ] && printf '   - … 외 %s건\n' $((CNT-15))
    fi
  fi
fi

echo "❌ $NF · ⚠️ $NW"
[ "$NF" -gt 0 ] && exit 1
exit 0
