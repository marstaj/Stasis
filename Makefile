APP     := Stasis
BUNDLE  := build/$(APP).app
# Set by `make release`. SwiftPM puts a universal build in a directory that differs between
# toolchains, so the products path is asked for instead of hardcoded.
ARCHS   :=
PRODUCTS = $(shell swift build -c release $(ARCHS) --show-bin-path)
BINARY   = $(PRODUCTS)/$(APP)
CLI      = $(PRODUCTS)/stasis-cli
ICONDIR := build/icon
ZIP     := build/$(APP).zip
# Stamped into the bundle so the update check knows which release a build came from. Defaults
# to the latest release tag; empty outside a tagged checkout, which keeps Info.plist's version.
# Also empty for a tag that is not purely dotted numbers: the value is pasted into shell commands
# below, and a tag name may contain shell syntax.
VERSION := $(shell git describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null | sed -n 's/^v\([0-9.]*\)$$/\1/p')
INSTALL := /Applications
# Where the `stasis` command is symlinked; override with `make install BIN=~/.local/bin`.
BIN     := /opt/homebrew/bin

.PHONY: test build bundle run install release raycast clean

test:
	swift test

build:
	swift build -c release $(ARCHS)

# Compiles the Icon Composer document into Assets.car (macOS 26+ icon) plus a legacy .icns.
# A plain .icns alone gets drawn shrunken inside a system tile on macOS 26+.
$(ICONDIR)/Assets.car: $(wildcard Resources/AppIcon.icon/*) $(wildcard Resources/AppIcon.icon/Assets/*)
	rm -rf $(ICONDIR)
	mkdir -p $(ICONDIR)
	xcrun actool Resources/AppIcon.icon --compile $(ICONDIR) --platform macosx \
		--minimum-deployment-target 14.0 --app-icon AppIcon --include-all-app-icons \
		--output-partial-info-plist $(ICONDIR)/partial.plist --output-format human-readable-text \
		--errors --warnings

# The CLI lives in Contents/Helpers because Contents/MacOS already holds "Stasis" and the
# filesystem is case-insensitive. Signed before the bundle so the outer signature covers it.
bundle: build $(ICONDIR)/Assets.car
	rm -rf $(BUNDLE)
	mkdir -p $(BUNDLE)/Contents/MacOS $(BUNDLE)/Contents/Helpers $(BUNDLE)/Contents/Resources
	cp $(BINARY) $(BUNDLE)/Contents/MacOS/
	cp $(CLI) $(BUNDLE)/Contents/Helpers/stasis
	cp $(ICONDIR)/Assets.car $(ICONDIR)/AppIcon.icns $(BUNDLE)/Contents/Resources/
	cp Resources/MenuBarIdle.svg Resources/MenuBarPaused.svg $(BUNDLE)/Contents/Resources/
	cp Info.plist $(BUNDLE)/Contents/
ifneq ($(VERSION),)
	plutil -replace CFBundleShortVersionString -string $(VERSION) $(BUNDLE)/Contents/Info.plist
	plutil -replace CFBundleVersion -string $(VERSION) $(BUNDLE)/Contents/Info.plist
endif
	printf 'APPL????' > $(BUNDLE)/Contents/PkgInfo
	codesign --force --sign - $(BUNDLE)/Contents/Helpers/stasis
	codesign --force --sign - $(BUNDLE)

run: bundle
	open $(BUNDLE)

install: bundle
	pkill -x $(APP) || true
	rm -rf $(INSTALL)/$(APP).app
	cp -R $(BUNDLE) $(INSTALL)/
	ln -sfn $(INSTALL)/$(APP).app/Contents/Helpers/stasis $(BIN)/stasis
	open $(INSTALL)/$(APP).app

# Universal build zipped for a GitHub release. ditto, unlike zip, keeps the symlinks and
# extended attributes the signature depends on.
release:
	$(MAKE) bundle ARCHS="--arch arm64 --arch x86_64"
	rm -f $(ZIP)
	ditto -c -k --keepParent $(BUNDLE) $(ZIP)

# Installs the Raycast extension's dependencies and registers it with Raycast via its dev
# server; stop the server with Ctrl-C once the commands show up, they stay registered.
raycast:
	cd raycast && npm install && npm run dev

clean:
	rm -rf .build build raycast/node_modules raycast/dist
