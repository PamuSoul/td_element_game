#!/usr/bin/env bash
# 匯出網頁版並啟動本機伺服器。
# 用法：./run_web.sh [port]        （預設 11081）
#       ./run_web.sh --serve-only  （不重新匯出，直接啟動）
set -euo pipefail

cd "$(dirname "$0")"
GODOT="${GODOT:-../block-puzzle-game/.tools/godot/Godot_v4.7.2-stable_linux.x86_64}"
PORT=11082
SERVE_ONLY=0
for arg in "$@"; do
	case "$arg" in
		--serve-only) SERVE_ONLY=1 ;;
		*) PORT="$arg" ;;
	esac
done

if [[ $SERVE_ONLY -eq 0 ]]; then
	mkdir -p build/web
	touch build/.gdignore
	"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
	"$GODOT" --headless --path . --export-release "Web" build/web/index.html
fi

echo
echo "遊戲網址：http://localhost:${PORT}"
for ip in $(hostname -I); do
	[[ $ip == 192.168.* || $ip == 10.* ]] && echo "          http://${ip}:${PORT}"
done
echo "按 Ctrl+C 停止"
exec python3 tools/serve.py "$PORT" build/web
