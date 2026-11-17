# 《首塔 TD》建置指令
#   make web     匯出網頁版到 build/web/
#   make serve   匯出並啟動本機伺服器（make serve PORT=9000 可換 port）
#   make run     直接開桌面版（需要圖形桌面；遠端主機請用 make serve）
#   make test    headless 自動測試：25 種融合 × 3 種塔全部觸發一遍
#   make bot     headless 平衡機器人跑一局
#   make art     重新產生美術素材（gen_art.py → svg、gen_bg.gd → 地圖底圖 png、gen_bgm.py → BGM ogg）
#   make clean   刪除 build/web
#
# Godot 與網頁匯出範本沿用 ../block-puzzle-game/.tools/godot；可用 GODOT=... 覆寫。

GODOT ?= ../block-puzzle-game/.tools/godot/Godot_v4.7.2-stable_linux.x86_64
PORT  ?= 11081
OUT   := build/web
SRC   := project.godot main.tscn export_presets.cfg $(wildcard scripts/*.gd) $(wildcard assets/fonts/*) $(wildcard assets/art/*.svg) $(wildcard assets/art/*.png) $(wildcard assets/audio/*)

.PHONY: all web serve serve-only run test bot clean art import

all: web

web: $(OUT)/index.html

$(OUT)/index.html: $(SRC)
	@mkdir -p $(OUT)
	@touch build/.gdignore
	-$(GODOT) --headless --path . --import >/dev/null 2>&1
	$(GODOT) --headless --path . --export-release "Web" $(OUT)/index.html

serve: web serve-only

serve-only:
	@echo
	@echo "遊戲網址：http://localhost:$(PORT)"
	@for ip in $$(hostname -I); do case $$ip in 192.168.*|10.*) echo "          http://$$ip:$(PORT)";; esac; done
	@echo "按 Ctrl+C 停止"
	@python3 tools/serve.py $(PORT) $(OUT)

# 讓 Godot 匯入新增 / 變更的素材
import:
	-$(GODOT) --headless --path . --import >/dev/null 2>&1

art:
	python3 tools/gen_art.py
	python3 tools/gen_bgm.py
	$(MAKE) import
	$(GODOT) --headless --path . --script tools/gen_bg.gd
	$(MAKE) import

run: import
	@if [ -z "$$DISPLAY" ] && [ -z "$$WAYLAND_DISPLAY" ]; then \
		echo "這台機器沒有圖形桌面（DISPLAY / WAYLAND_DISPLAY 未設定），無法開啟桌面視窗。"; \
		echo "請改用：make serve   然後在瀏覽器開 http://localhost:$(PORT)"; \
		exit 1; \
	fi
	$(GODOT) --path .

test: import
	$(GODOT) --headless --path . --fixed-fps 20 -- --autotest

bot: import
	$(GODOT) --headless --path . --fixed-fps 20 -- --bot

clean:
	rm -rf $(OUT)
