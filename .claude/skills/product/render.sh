#!/bin/bash
# render.sh — /product PD 로컬 디자인(screens/*.html)을 헤드리스 브라우저로 PNG 렌더링
# 사용: bash render.sh <design 디렉토리> [desktop|mobile|both]   (기본 both)
# 출력: <design>/render/<파일명>-desktop.png(1280×800) · -mobile.png(390×844)
# exit: 0 = 전부 렌더 / 1 = 입력 오류·일부 실패 / 2 = 브라우저 없음(시각 대조 불가 — 호출 측이 폴백 기록)
# 조율자(메인)가 실행한다 — pd 에이전트는 Bash가 없다(role-guard가 Bash 쓰기를 판정하지 못하므로 의도적으로 주지 않음).
# 네트워크 차단: 렌더가 pd가 쓴 HTML의 원격 요청을 대신 보내는 송신 경로가 되지 않게 모든 요청을 죽은 프록시로 보낸다(loopback 포함).
# 외부 리소스를 쓴 화면은 깨져 보인다 — "오프라인에서 열리는가" 검증도 겸한다.

DIR="${1:-}"
MODE="${2:-both}"
[ -n "$DIR" ] && [ -d "$DIR/screens" ] || { echo "render: '$DIR/screens' 디렉토리가 없습니다" >&2; exit 1; }
case "$MODE" in desktop|mobile|both) ;; *) echo "render: 모드는 desktop|mobile|both" >&2; exit 1 ;; esac

BROWSER="${MACHINA_RENDER_BROWSER:-}"
if [ -z "$BROWSER" ]; then
  for c in "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
           "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge" \
           "/Applications/Chromium.app/Contents/MacOS/Chromium" \
           "$(command -v google-chrome 2>/dev/null)" "$(command -v chromium 2>/dev/null)"; do
    [ -n "$c" ] && [ -x "$c" ] && { BROWSER="$c"; break; }
  done
fi
[ -n "$BROWSER" ] && [ -x "$BROWSER" ] || { echo "render: 헤드리스 브라우저 없음 — 시각 대조 불가(텍스트 대조로 진행)" >&2; exit 2; }

OUT="$DIR/render"
mkdir -p "$OUT" || exit 1
PROF=$(mktemp -d "${TMPDIR:-/tmp}/machina-render.XXXXXX") || exit 1
trap 'rm -rf "$PROF"' EXIT

shot() {  # $1 file URL, $2 png, $3 w, $4 h
  rm -f "$2"  # 이전 회차 PNG가 남아 실패를 성공으로 세지 않게
  "$BROWSER" --headless=new --disable-gpu --hide-scrollbars --no-first-run --no-default-browser-check \
    --proxy-server=127.0.0.1:9 --proxy-bypass-list="<-loopback>" \
    --user-data-dir="$PROF" --window-size="$3,$4" --screenshot="$2" "$1" >/dev/null 2>&1 &
  local pid=$! t=0
  while kill -0 "$pid" 2>/dev/null; do  # 멈춘 페이지 대비 20초 제한(macOS엔 timeout 명령이 없다)
    [ "$t" -ge 40 ] && { kill "$pid" 2>/dev/null; echo "render 시간 초과: $(basename "$2")" >&2; return 1; }
    sleep 0.5; t=$((t+1))
  done
  wait "$pid" 2>/dev/null
  [ -s "$2" ]
}

rm -f "$OUT"/*.png  # 삭제·이름 바뀐 화면의 고아 PNG를 판정자가 읽지 않게(모드와 무관하게 전부 — 한쪽 폭만 렌더하면 다른 쪽은 사라진다)
n=0; bad=0
for f in "$DIR"/screens/*.html; do
  [ -e "$f" ] || continue
  # 경로의 #·?·공백 등을 file URL로 인코딩
  abs=$(python3 -c 'import pathlib,sys;print(pathlib.Path(sys.argv[1]).resolve().as_uri())' "$f" 2>/dev/null) \
    || { echo "render 실패: $f — 경로를 file URL로 바꿀 수 없음(python3 필요)" >&2; bad=$((bad+1)); continue; }
  base="$(basename "$f" .html)"
  if [ "$MODE" != mobile ]; then
    if shot "$abs" "$OUT/$base-desktop.png" 1280 800; then n=$((n+1)); else bad=$((bad+1)); echo "render 실패: $base desktop" >&2; fi
  fi
  if [ "$MODE" != desktop ]; then
    if shot "$abs" "$OUT/$base-mobile.png" 390 844; then n=$((n+1)); else bad=$((bad+1)); echo "render 실패: $base mobile" >&2; fi
  fi
done

[ $((n+bad)) -eq 0 ] && { echo "render: screens/*.html이 없습니다" >&2; exit 1; }
echo "render: ${n}장 → $OUT"
[ "$bad" -eq 0 ] || exit 1
exit 0
