# Verification harness: install each port's PUBLISHED package from its
# registry and run a tiny smoke client that proves the artifact installs
# and works. The universal smoke test for every port:
#   getpath({ db: { host: "localhost" } }, "db.host") == "localhost"
#
# `make verify` runs the status-aware driver (verify.py): it asks
# tools/release_status.py for LIVE publish status, verifies ONLY the ports
# actually published, retries transient registry/network errors (reporting
# them as UNAVAILABLE, not FAIL), skips unpublished ports, and prints a full
# report. Each verify-<port> below SELF-CLEANS and forces a fresh ONLINE
# install, so we always exercise the live published artifact — never a stale
# local copy or cached resolution.

PORTS := go typescript javascript python ruby rust csharp perl java lua clojure php zig c cpp swift

# Ruby toolchain. The published gem requires Ruby >= 2.7; some systems ship an
# older /usr/bin/ruby (e.g. macOS 2.6). Prefer a Homebrew ruby when present
# (mirrors the zig fallback below); override with `make RUBY=... GEM=...`.
RUBY   ?= $(shell command -v /opt/homebrew/opt/ruby/bin/ruby 2>/dev/null || command -v ruby)
GEM    ?= $(shell command -v /opt/homebrew/opt/ruby/bin/gem 2>/dev/null || command -v gem)
PYTHON ?= python3
DOTNET ?= dotnet
PERL   ?= perl
MVN    ?= mvn
LUAROCKS ?= luarocks
LUA      ?= lua
CLOJURE  ?= clojure

# Toolchains for the tag-only ports (no package registry: the "published"
# artifact IS the git tag, so these targets download the tagged source
# tarball from GitHub and build the smoke against that vendored source).
PHP    ?= php
SWIFT  ?= swiftc
CC     ?= cc
CXX    ?= g++
# Zig is often not on PATH; fall back to the pinned local toolchain.
ZIG    ?= $(shell command -v zig 2>/dev/null || echo $(HOME)/.local/zig/0.13.0/zig)

# zig 0.13 cannot link against very new Xcode SDKs (macOS 26 / Xcode 26): every
# libc symbol comes back undefined. The Command Line Tools SDK still works, so
# point zig at it (mirrors zig/Makefile). macOS-only; no-op where CLT is absent
# (Linux CI, minimal runners).
ifneq ($(wildcard /Library/Developer/CommandLineTools/.),)
export DEVELOPER_DIR := /Library/Developer/CommandLineTools
endif

# GitHub source tarball for a slash-tag: tags/<lang>/v<ver>.tar.gz
TARBALL = https://github.com/voxgig/struct/archive/refs/tags

# Versions, read straight from the repo (relative to build/verify/).
PHP_VER   := $(shell cat ../../php/VERSION)
C_VER     := $(shell cat ../../c/VERSION)
CPP_VER   := $(shell cat ../../cpp/VERSION)
SWIFT_VER := $(shell cat ../../swift/VERSION)
ZIG_VER   := $(shell sed -n 's/.*\.version *= *"\([^"]*\)".*/\1/p' ../../zig/build.zig.zon)

.PHONY: verify verify-go verify-typescript verify-javascript \
        verify-python verify-ruby verify-rust verify-csharp verify-perl verify-java verify-lua \
        verify-clojure verify-php verify-zig verify-c verify-cpp verify-swift clean

# Each target removes its own artifacts first, then installs fresh from the
# registry with cache-revalidation flags (--prefer-online / --refresh /
# @latest / fresh --install-dir) so the smoke runs against the LIVE package.

verify-go:
	cd go && rm -f go.sum && go get github.com/voxgig/struct/go@latest && go mod tidy && go run .

verify-typescript:
	cd typescript && rm -rf node_modules package-lock.json && npm install --no-audit --no-fund --prefer-online && node smoke.cjs

verify-javascript:
	cd javascript && rm -rf node_modules package-lock.json && npm install --no-audit --no-fund --prefer-online && node smoke.cjs

verify-ruby:
	cd ruby && rm -rf .gems && $(GEM) install voxgig_struct --no-document --clear-sources --source https://rubygems.org --install-dir .gems >/dev/null && GEM_PATH=.gems $(RUBY) smoke.rb

verify-python:
	cd python && uv run --refresh --no-project --with voxgig-struct python smoke.py

# NuGet: float to the newest published Voxgig.Struct and force a fresh restore
# (--no-cache bypasses the HTTP cache so `Version="*"` re-resolves online).
verify-csharp:
	@command -v $(DOTNET) >/dev/null || { echo "FAIL csharp: dotnet toolchain not found"; exit 1; }
	cd csharp && rm -rf bin obj && $(DOTNET) restore --force --no-cache && $(DOTNET) run --no-restore -c Release

# CPAN: pure-Perl dist, so the published artifact is its tarball. Resolve the
# live download_url from MetaCPAN, fetch + extract into a fresh .build/, and
# smoke against the dist's own lib/ (equivalent to install for a no-XS module).
verify-perl:
	@command -v $(PERL) >/dev/null || { echo "FAIL perl: perl toolchain not found"; exit 1; }
	@d=perl/.build; rm -rf $$d && mkdir -p $$d; \
	url=$$($(PYTHON) -c "import urllib.request,json; print(json.load(urllib.request.urlopen('https://fastapi.metacpan.org/v1/download_url/Voxgig::Struct'))['download_url'])"); \
	echo "downloading $$url"; \
	curl -fsSL "$$url" -o $$d/src.tgz; \
	top=$$(tar tzf $$d/src.tgz | head -1 | cut -d/ -f1); \
	tar xzf $$d/src.tgz -C $$d; \
	$(PERL) -I "$$d/$$top/lib" perl/smoke.pl

# Maven Central: resolve the published artifact into a throwaway local repo
# (-Dmaven.repo.local=.build/m2 -U = fresh download from Central each run; the
# pom's [0.1.0,) range floats to the newest release) and run the smoke main.
verify-java:
	@command -v $(MVN) >/dev/null || { echo "FAIL java: maven toolchain not found"; exit 1; }
	cd java && rm -rf .build target && \
	  $(MVN) -q -Dmaven.repo.local=.build/m2 -U compile exec:java -Dexec.mainClass=Smoke

# LuaRocks: install the published rock fresh into a throwaway tree (--force +
# a clean tree each run = live install; luarocks fetches the git source at the
# pinned tag), set the module path, and smoke require("voxgig.struct").
verify-lua:
	@command -v $(LUAROCKS) >/dev/null || { echo "FAIL lua: luarocks toolchain not found"; exit 1; }
	cd lua && rm -rf .build && \
	  $(LUAROCKS) install voxgig-struct --tree=.build/tree --force >/dev/null && \
	  eval "$$($(LUAROCKS) path --tree=.build/tree)" && $(LUA) smoke.lua

# Clojars: resolve the published com.voxgig/struct-clojure fresh (drop the cached
# artifact + -Sforce = live re-download) at the repo's VERSION, then run the
# smoke via (require 'voxgig.struct).
verify-clojure:
	@command -v $(CLOJURE) >/dev/null || { echo "FAIL clojure: clojure CLI not found"; exit 1; }
	ver=$$(cat ../../clojure/VERSION); \
	rm -rf "$$HOME/.m2/repository/com/voxgig/struct-clojure"; \
	cd clojure && $(CLOJURE) -Sforce \
	  -Sdeps "{:deps {com.voxgig/struct-clojure {:mvn/version \"$$ver\"}} :mvn/repos {\"clojars\" {:url \"https://repo.clojars.org/\"}}}" \
	  -M -m smoke

# --- Tag-only ports -------------------------------------------------------
# These ports have NO package registry: the published artifact is the git
# tag <lang>/v<ver>. Each target reads the version from the repo, downloads
# the GitHub source tarball at that tag into a fresh, gitignored .build/
# temp dir, extracts it, locates the GitHub-named top-level dir robustly,
# and builds the smoke against the DOWNLOADED (vendored) source — never the
# working tree. Each starts by wiping its own .build/ so the run is live.

verify-php:
	@d=php/.build; url="$(TARBALL)/php/v$(PHP_VER).tar.gz"; \
	rm -rf $$d && mkdir -p $$d; \
	echo "downloading $$url"; \
	curl -fsSL "$$url" -o $$d/src.tgz; \
	top=$$(tar tzf $$d/src.tgz | head -1 | cut -d/ -f1); \
	tar xzf $$d/src.tgz -C $$d; \
	command -v $(PHP) >/dev/null || { echo "FAIL php: php toolchain not found"; exit 1; }; \
	$(PHP) php/smoke.php "$$d/$$top/php"

verify-c:
	@d=c/.build; url="$(TARBALL)/c/v$(C_VER).tar.gz"; \
	rm -rf $$d && mkdir -p $$d; \
	echo "downloading $$url"; \
	curl -fsSL "$$url" -o $$d/src.tgz; \
	top=$$(tar tzf $$d/src.tgz | head -1 | cut -d/ -f1); \
	tar xzf $$d/src.tgz -C $$d; \
	src="$$d/$$top/c"; \
	command -v $(CC) >/dev/null || { echo "FAIL c: cc toolchain not found"; exit 1; }; \
	$(CC) -std=c11 -I "$$src/src" c/smoke.c $$src/src/*.c -lm -o $$d/smoke && \
	$$d/smoke

verify-cpp:
	@d=cpp/.build; url="$(TARBALL)/cpp/v$(CPP_VER).tar.gz"; \
	rm -rf $$d && mkdir -p $$d; \
	echo "downloading $$url"; \
	curl -fsSL "$$url" -o $$d/src.tgz; \
	top=$$(tar tzf $$d/src.tgz | head -1 | cut -d/ -f1); \
	tar xzf $$d/src.tgz -C $$d; \
	src="$$d/$$top/cpp"; \
	command -v $(CXX) >/dev/null || { echo "FAIL cpp: g++ toolchain not found"; exit 1; }; \
	$(CXX) -std=c++17 -I "$$src/src" cpp/smoke.cpp -o $$d/smoke && \
	$$d/smoke

verify-swift:
	@d=swift/.build; url="$(TARBALL)/swift/v$(SWIFT_VER).tar.gz"; \
	rm -rf $$d && mkdir -p $$d; \
	echo "downloading $$url"; \
	curl -fsSL "$$url" -o $$d/src.tgz; \
	top=$$(tar tzf $$d/src.tgz | head -1 | cut -d/ -f1); \
	tar xzf $$d/src.tgz -C $$d; \
	src="$$d/$$top/swift"; \
	command -v $(SWIFT) >/dev/null || { echo "FAIL swift: swiftc toolchain not found"; exit 1; }; \
	$(SWIFT) -o $$d/smoke swift/smoke.swift $$src/Sources/VoxgigStruct/*.swift && \
	$$d/smoke

verify-zig:
	@d=zig/.build; url="$(TARBALL)/zig/v$(ZIG_VER).tar.gz"; \
	rm -rf $$d && mkdir -p $$d; \
	echo "downloading $$url"; \
	curl -fsSL "$$url" -o $$d/src.tgz; \
	top=$$(tar tzf $$d/src.tgz | head -1 | cut -d/ -f1); \
	tar xzf $$d/src.tgz -C $$d; \
	src="$$d/$$top/zig"; \
	[ -x "$(ZIG)" ] || command -v $(ZIG) >/dev/null || { echo "FAIL zig: zig toolchain not found"; exit 1; }; \
	$(ZIG) run -lc --dep voxgig-struct \
	  -Mroot=zig/smoke.zig -Mvoxgig-struct=$$src/src/struct.zig --cache-dir $$d/zig-cache

verify-rust:
	cd rust && rm -rf target && cargo update --quiet && cargo run --quiet

# Status-aware driver: determine live status, verify only published, handle
# transient registry downtime, full report.
verify:
	@$(PYTHON) verify.py

clean:
	rm -rf typescript/node_modules typescript/package-lock.json
	rm -rf javascript/node_modules javascript/package-lock.json
	rm -f go/go.sum
	rm -rf ruby/.gems
	rm -rf rust/target
	rm -rf csharp/bin csharp/obj perl/.build java/.build java/target lua/.build clojure/.cpcache
	rm -rf php/.build zig/.build c/.build cpp/.build swift/.build
	rm -rf */.venv
	find . -name '__pycache__' -type d -prune -exec rm -rf {} +
