#!/bin/bash
# git-guard (my-machina) — PreToolUse hook (matcher: Bash)
# 1인 개발 + 가끔 병렬 세션 전제. 이전 팀 하네스의 git-guard에서 보호 브랜치 규칙을 빼고 계정 검사를 더한 축소판.
#   deny(면제 불가): 커밋 신원≠워크스페이스 계정(-c/env 위조 포함) · 개인 계정 아닌 gh 쓰기
#     계정 값(MACHINA_EMAIL·MACHINA_GH)은 프로세스 env에서만 읽는다(settings*.json env가 주입한 값). 미설정 시 해당 신원·gh 검사 생략
#   deny(사용자 승인 시 면제): 세션↔작업장 바인딩 위반(REBIND) · 다른 브랜치 push · 남의 repo push(OK)
#   ask : force/mirror/삭제 push · 다른 세션이 쓰는 작업장에서 checkout/reset/clean/restore/stash/add -A
# 탈출 토큰은 명령 맨 앞 env 접두로만 인정한다(메시지·인자 안의 토큰은 무시). 붙이는 건 사용자가 그 명령을 명시 승인한 뒤에만.
#   GIT_GUARD_REBIND=1 → 현 위치로 재바인딩 / GIT_GUARD_OK=1 → 브랜치 불일치·남의 repo push만 1회 면제
# 항상 exit 0, 판단 불가 시 무개입 — 무관한 Bash 호출을 깨뜨리지 않는다.

INPUT=$(cat 2>/dev/null) || exit 0
[ -z "$INPUT" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$CMD" ] && exit 0
case "$CMD" in *git*|*gh*) ;; *) exit 0 ;; esac

# 판정용 사본: 따옴표 구간을 지워 echo·grep·커밋 메시지 속 문자열을 명령으로 오인하지 않는다.
# (경로·env 값 추출은 원문 CMD를 쓴다)
SCMD=$(printf '%s' "$CMD" | sed -E "s/\"[^\"]*\"//g; s/'[^']*'//g")
has() { printf '%s' "$SCMD" | grep -qE "$1"; }
# 명령 맨 앞의 env 할당 묶음 안에 토큰이 있는지
prefix_has() { printf '%s' "$CMD" | grep -qE "^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*$1=1[[:space:]]"; }
OK=; prefix_has GIT_GUARD_OK && OK=1
REBIND=; prefix_has GIT_GUARD_REBIND && REBIND=1

deny() { jq -cn --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'; exit 0; }
ask()  { jq -cn --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"ask",permissionDecisionReason:$r}}'; exit 0; }
APPROVAL="사용자가 이 명령을 명시 승인한 경우에만"

# 설정값 K: 프로세스 env만. gh도 env만 보므로 파일을 읽으면 판정과 실제 계정이 어긋난다.
cfg() { printf '%s' "${!1}"; }
# gh 설정 디렉토리: [명령 접두 GH_CONFIG_DIR(인자 cmd일 때)] > env > ~/.config/gh
gh_dir() {
  local d=
  [ "$1" = cmd ] && d=$(printf '%s' "$CMD" | grep -oE 'GH_CONFIG_DIR=[^[:space:]]+' | tail -1 | cut -d= -f2- | tr -d "\"'")
  [ -z "$d" ] && d=$(cfg GH_CONFIG_DIR)
  [ -z "$d" ] && d="$HOME/.config/gh"
  printf '%s' "${d/#\~/$HOME}"
}
# hosts.yml의 github.com 블록 최상위 user: = 활성 계정
gh_user() { awk '/^github\.com:/{f=1;next} /^[^[:space:]]/{f=0} f && /^    user:/{print $2; exit}' "$1/hosts.yml" 2>/dev/null; }

# ── gh: 다른 계정으로 PR·repo·release가 나가는 사고 방지 (면제 불가, MACHINA_GH 설정 시) ──
# 전역 gh가 다른 계정일 수 있어, 워크스페이스 세션은 env GH_CONFIG_DIR(개인 설정)로 분리한다.
if has '(^|[;&|(][[:space:]]*|[[:space:]])gh[[:space:]]+(pr|repo|release|issue|gist|api|workflow|secret)([[:space:]]|$)'; then
  ME_GH=$(cfg MACHINA_GH)
  if [ -n "$ME_GH" ]; then
    GH_DIR=$(gh_dir cmd)
    GH_USER=$(gh_user "$GH_DIR")
    if [ "$GH_USER" != "$ME_GH" ]; then
      deny "[git-guard] gh 활성 계정이 '${GH_USER:-없음}'(설정: $GH_DIR) — 이 워크스페이스는 MACHINA_GH 설정값($ME_GH) 전용(면제 불가). 사용자가 직접 '! GH_CONFIG_DIR=$GH_DIR gh auth login'으로 $ME_GH 로그인 후 재시도."
    fi
  fi
fi

# ── git 쓰기 명령 분류 ──────────────────────────────────────────────────────
# git 전역 옵션(-C path, -c k=v, --git-dir=…, --work-tree=…)을 건너뛰고 서브커맨드를 본다
G='git([[:space:]]+(-[cC][[:space:]]+[^[:space:]]+|--[a-z-]+(=[^[:space:]]+)?))*[[:space:]]+'
HAS_PUSH=;     has "${G}push([[:space:]]|$)" && HAS_PUSH=1
HAS_COMMIT=;   has "${G}commit([[:space:]]|$)" && HAS_COMMIT=1
HAS_SWITCH=;   has "${G}(checkout|switch|rebase)([[:space:]]|$)" && HAS_SWITCH=1
HAS_DESTROY=;  has "${G}(reset[[:space:]]+--hard|clean[[:space:]]+-[a-zA-Z]*f|restore[[:space:]]|branch[[:space:]]+-D|stash([[:space:]]+(push|save|-u|--include-untracked)|[[:space:]]*($|[;&|])))" && HAS_DESTROY=1
HAS_ADD=;      has "${G}add([[:space:]]|$)" && HAS_ADD=1
HAS_ADD_ALL=;  has "${G}add[[:space:]]+(-A|--all|\.)([[:space:]]|$)" && HAS_ADD_ALL=1
has "${G}commit[[:space:]]+-[a-zA-Z]*a" && HAS_ADD_ALL=1
[ -z "$HAS_PUSH$HAS_COMMIT$HAS_SWITCH$HAS_DESTROY$HAS_ADD" ] && exit 0

# 실행 디렉토리 추정: git -C / --git-dir > 마지막 cd(서브셸 포함) > 세션 cwd
DIR=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
C_PATH=$(printf '%s' "$CMD" | grep -oE 'git[[:space:]]+-C[[:space:]]+[^[:space:]]+' | tail -1 | awk '{print $3}')
GD_PATH=$(printf '%s' "$CMD" | grep -oE -- '--git-dir=[^[:space:];&|)]+' | tail -1 | cut -d= -f2-)
CD_PATH=$(printf '%s' "$CMD" | grep -oE '(^|&&|;|\()[[:space:]]*cd[[:space:]]+[^[:space:];&|)]+' | tail -1 | sed -E 's/^(&&|;|\()?[[:space:]]*cd[[:space:]]+//')
[ -n "$CD_PATH" ] && DIR="$CD_PATH"
if [ -n "$GD_PATH" ]; then
  GD_PATH="${GD_PATH/#\~/$HOME}"
  case "$GD_PATH" in */.git|*/.git/) DIR="${GD_PATH%/}"; DIR="${DIR%/.git}" ;; *) DIR="$GD_PATH" ;; esac
fi
[ -n "$C_PATH" ] && DIR="$C_PATH"
DIR="${DIR/#\~/$HOME}"
[ -d "$DIR" ] || exit 0

TOP=$(git -C "$DIR" rev-parse --show-toplevel 2>/dev/null) || exit 0
[ -z "$TOP" ] && exit 0
COMMON=$(git -C "$DIR" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
[ -z "$COMMON" ] && COMMON="$TOP/.git"
BRANCH=$(git -C "$DIR" branch --show-current 2>/dev/null)

# ── 커밋 신원 (면제 불가, MACHINA_EMAIL 설정 시) ──────────────────────────
ME_EMAIL=; [ -n "$HAS_COMMIT" ] && ME_EMAIL=$(cfg MACHINA_EMAIL)
if [ -n "$ME_EMAIL" ]; then
  EMAIL=$(git -C "$DIR" config user.email 2>/dev/null)
  # 명령에서 신원을 덮어쓰는 경로(-c user.email=, GIT_AUTHOR/COMMITTER_EMAIL=)도 같은 기준으로 본다
  for O in $(printf '%s' "$CMD" | grep -oE '(user\.email|GIT_(AUTHOR|COMMITTER)_EMAIL)=[^[:space:]]+' | cut -d= -f2- | tr -d "\"'"); do
    [ "$O" != "$ME_EMAIL" ] && EMAIL="$O"
  done
  if [ "$EMAIL" != "$ME_EMAIL" ]; then
    deny "[git-guard] 커밋 신원이 '$EMAIL' — 이 워크스페이스는 MACHINA_EMAIL 설정값($ME_EMAIL) 전용(면제 불가). ~/.gitconfig includeIf(gitdir:<workspace>/)와 repo 로컬 user.email·명령 내 신원 덮어쓰기를 확인(로컬 config로 땜질 금지)."
  fi
fi

# ── 세션↔작업장 바인딩 (병렬 세션 커밋 섞임 방지) ─────────────────────────
SESSION=$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null)
STATE_DIR="$HOME/.claude/git-guard"
mkdir -p "$STATE_DIR" 2>/dev/null
# 12시간 미사용 바인딩은 끝난 세션으로 보고 정리(활성 세션은 아래 touch로 갱신)
find "$STATE_DIR" -name '*.tsv' -mmin +720 -delete 2>/dev/null
STATE="$STATE_DIR/$SESSION.tsv"   # 형식: <git-common-dir>\t<worktree-toplevel>
TAB=$(printf '\t')
touch "$STATE" 2>/dev/null

BOUND=$(grep -F "$COMMON$TAB" "$STATE" 2>/dev/null | head -1 | cut -f2)
if [ -n "$REBIND" ]; then
  grep -vF "$COMMON$TAB" "$STATE" > "$STATE.tmp" 2>/dev/null; mv -f "$STATE.tmp" "$STATE" 2>/dev/null
  printf '%s\t%s\n' "$COMMON" "$TOP" >> "$STATE" 2>/dev/null
else
  if [ -n "$BOUND" ] && [ "$BOUND" != "$TOP" ]; then
    deny "[git-guard] 세션 바인딩 위반: 이 세션은 $BOUND 에서 작업 중인데 같은 repo의 다른 worktree($TOP)에 git 쓰기 감지. 의도된 전환이면 $APPROVAL 명령 맨 앞에 GIT_GUARD_REBIND=1."
  fi
  [ -z "$BOUND" ] && printf '%s\t%s\n' "$COMMON" "$TOP" >> "$STATE" 2>/dev/null
fi

OTHER=$(grep -lF "$COMMON$TAB$TOP" "$STATE_DIR"/*.tsv 2>/dev/null | grep -vF "$STATE" | head -1)
if [ -n "$OTHER" ] && [ -n "$HAS_DESTROY$HAS_SWITCH$HAS_ADD_ALL" ]; then
  ask "[git-guard] 다른 Claude 세션($(basename "$OTHER" .tsv | cut -c1-8)…)이 같은 작업장($TOP)을 사용 중 — checkout/rebase/reset/clean/restore/stash/add -A는 그 세션의 변경을 깨거나 흡수할 수 있음. 파일 명시 add 권장."
fi

# ── push ───────────────────────────────────────────────────────────────────
if [ -n "$HAS_PUSH" ]; then
  PUSH_SEG=$(printf '%s' "$SCMD" | grep -oE "${G}push[^;&|]*" | head -1)
  ARGS=$(printf '%s' "$PUSH_SEG" | sed -E 's/(-[cC])[[:space:]]+[^[:space:]]+//g' | tr '[:space:]' '\n' | grep -v '^$' | grep -vE '^(git|push|-.*)$')
  REMOTE=$(printf '%s\n' "$ARGS" | head -1)
  if [ -n "$REMOTE" ] && git -C "$DIR" remote | grep -qx "$REMOTE"; then
    REFSPEC=$(printf '%s\n' "$ARGS" | sed -n 2p)
  else
    REFSPEC="$REMOTE"; REMOTE=origin
  fi

  URL=$(git -C "$DIR" remote get-url "$REMOTE" 2>/dev/null)
  OWNER=$(printf '%s' "$URL" | sed -nE 's#.*github\.com[:/]([^/]+)/.*#\1#p')
  if [ -z "$OK" ]; then
    # 내 계정 = MACHINA_GH, 없으면 gh 활성 계정. 둘 다 없으면 owner 검사만 생략(판단 불가 시 무개입)
    # 명령 접두 GH_CONFIG_DIR는 무시 — 남의 계정 설정을 접두로 붙여 owner 검사를 우회하지 못하게
    ME_GH=$(cfg MACHINA_GH); ME_SRC="MACHINA_GH"
    [ -z "$ME_GH" ] && { ME_GH=$(gh_user "$(gh_dir)"); ME_SRC="gh 활성 계정"; }
    if [ -n "$ME_GH" ] && [ "$OWNER" != "$ME_GH" ]; then
      deny "[git-guard] push 대상 '$REMOTE'($URL)가 $ME_GH($ME_SRC) 소유가 아님 — 남의 repo push 금지. 기여가 의도라면 $APPROVAL 명령 맨 앞에 GIT_GUARD_OK=1."
    fi
  fi

  # 원격 삭제(--delete/-d 또는 ':<branch>')는 로컬 브랜치를 올리는 게 아니라 브랜치 불일치 검사 대상이 아니다
  if printf '%s' "$PUSH_SEG" | grep -qE '(^|[[:space:]])(--delete|-d)([[:space:]]|$)' || [ "${REFSPEC#:}" != "$REFSPEC" ]; then
    ask "[git-guard] 원격 브랜치 삭제 push 감지 — 의도 확인."
  fi
  printf '%s' "$PUSH_SEG" | grep -qE '(^|[[:space:]])(-f|--force|--force-with-lease[^[:space:]]*|--mirror|--all)([[:space:]]|$)' && \
    ask "[git-guard] force/mirror/all push 감지 — 원격 이력·다수 ref를 덮어씀. 의도 확인."

  SRC="${REFSPEC%%:*}"; DST="${REFSPEC#*:}"; [ "$REFSPEC" = "$DST" ] && DST="$SRC"
  { [ -z "$REFSPEC" ] || [ "$SRC" = "HEAD" ]; } && SRC="$BRANCH"
  [ -n "$SRC" ] && git -C "$DIR" rev-parse -q --verify "refs/tags/$SRC" >/dev/null 2>&1 && SRC="$BRANCH"
  if [ -n "$SRC" ] && [ -n "$BRANCH" ] && [ "$SRC" != "$BRANCH" ] && [ -z "$OK" ]; then
    deny "[git-guard] 현재 브랜치($BRANCH)와 다른 브랜치($SRC) push — 병렬 세션 오push 방지. 'git push origin HEAD'를 쓰거나, 의도라면 $APPROVAL 명령 맨 앞에 GIT_GUARD_OK=1."
  fi
fi

exit 0
