# Perl Infinity dev loop. `make help` lists targets.
#   make gen test lint            regenerate API data, run the harness, run the linters
#   make test MODE=field T=boot   one spec pattern in one secrecy mode
#   make lint STRICT=1            fail on lint errors (CI)

LUAJIT   ?= $(shell command -v luajit 2>/dev/null || echo /opt/homebrew/bin/luajit)
LUACHECK ?= $(shell command -v luacheck 2>/dev/null || echo $(HOME)/.luarocks/bin/luacheck)
MODE     ?= strict
FUZZ     ?= 0
T        ?=
STRICT   ?= 0

WOW_DIR  ?= /Applications/World of Warcraft/_forever_
ADDON_DST = $(WOW_DIR)/Interface/AddOns/PerlInfinity/
SV_FILE  ?= $(shell ls "$(WOW_DIR)"/WTF/Account/*/SavedVariables/PerlInfinity.lua 2>/dev/null | head -1)
VERSION  ?= $(shell git describe --tags --always --dirty 2>/dev/null || echo dev)
RELEASE   = .release

.PHONY: help gen test test-all lint preview deploy readsv package clean

help:
	@echo "make gen       regenerate tests/harness/api_tags.lua, blizzard_templates.lua, tools/out/wow_globals.lua"
	@echo "make test      run the offline harness (MODE=strict|field|open, T=pattern, FUZZ=N)"
	@echo "make test-all  run the harness in all three modes"
	@echo "make lint      tools/lint.lua + luacheck on PerlInfinity/ (STRICT=1 fails on findings)"
	@echo "make preview   dump frame layouts (tools/layout.lua) and render PNGs (tools/preview.py, needs Pillow)"
	@echo "make deploy    copy PerlInfinity/ into the WoW: Forever AddOns folder"
	@echo "make readsv    report on PerlInfinityLog from the account SavedVariables"
	@echo "make package   zip PerlInfinity/ to $(RELEASE)/PerlInfinity-<version>.zip"

gen:
	$(LUAJIT) tools/gen_api_tags.lua
	$(LUAJIT) tools/gen_globals.lua

test:
	$(LUAJIT) tests/run.lua $(T) --mode=$(MODE) --fuzz=$(FUZZ)

test-all:
	$(LUAJIT) tests/run.lua $(T) --mode=strict --fuzz=$(FUZZ)
	$(LUAJIT) tests/run.lua $(T) --mode=field --fuzz=$(FUZZ)
	$(LUAJIT) tests/run.lua $(T) --mode=open --fuzz=$(FUZZ)

lint:
	$(LUAJIT) tools/lint.lua $(if $(filter 1,$(STRICT)),--strict,) --manifest=tools/out/manifest.lua PerlInfinity
	@if [ -x "$(LUACHECK)" ]; then \
		$(LUACHECK) --config .luacheckrc PerlInfinity || [ "$(STRICT)" != "1" ]; \
	else \
		echo "luacheck not found ($(LUACHECK)); skipped"; \
	fi

preview:
	rm -rf tools/out/layout
	$(LUAJIT) tools/layout.lua PerlInfinity/PerlInfinity.toc tools/out/layout
	@for f in tools/out/layout/*.txt; do [ -e "$$f" ] && python3 tools/preview.py "$$f"; done; true

# Copies the addon into the Forever client. A full client restart is needed when the
# TOC or the file list changes; Lua-only changes need /reload.
deploy:
	@test -d "$(WOW_DIR)/Interface/AddOns" || { echo "WoW AddOns folder not found: $(WOW_DIR)"; exit 1; }
	rsync -a --delete PerlInfinity/ "$(ADDON_DST)"
	@echo "deployed to $(ADDON_DST)"

readsv:
	$(LUAJIT) tools/readsv.lua "$(SV_FILE)"

# Stages PerlInfinity/ with @project-version@ substituted in the TOC, then zips it.
package:
	rm -rf $(RELEASE)/PerlInfinity
	mkdir -p $(RELEASE)
	cp -R PerlInfinity $(RELEASE)/PerlInfinity
	for toc in $(RELEASE)/PerlInfinity/*.toc; do sed -i.bak 's/@project-version@/$(VERSION)/' "$$toc" && rm -f "$$toc.bak"; done
	rm -f $(RELEASE)/PerlInfinity-$(VERSION).zip
	cd $(RELEASE) && zip -rqX PerlInfinity-$(VERSION).zip PerlInfinity
	rm -rf $(RELEASE)/PerlInfinity
	@echo "$(RELEASE)/PerlInfinity-$(VERSION).zip"

clean:
	rm -rf $(RELEASE) tools/out/manifest.lua
