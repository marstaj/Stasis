APP     := Stasis
BUNDLE  := build/$(APP).app
BINARY  := .build/release/$(APP)
CLI     := .build/release/stasis-cli
ICONDIR := build/icon
INSTALL := /Applications
# Where the `stasis` command is symlinked; override with `make install BIN=~/.local/bin`.
BIN     := /opt/homebrew/bin

.PHONY: test build bundle run install raycast clean

test:
	swift test

build:
	swift build -c release

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
	cp Info.plist $(BUNDLE)/Contents/
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

# Installs the Raycast extension's dependencies and registers it with Raycast via its dev
# server; stop the server with Ctrl-C once the commands show up, they stay registered.
raycast:
	cd raycast && npm install && npm run dev

clean:
	rm -rf .build build raycast/node_modules raycast/dist
