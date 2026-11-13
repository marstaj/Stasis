APP     := Stasis
BUNDLE  := build/$(APP).app
BINARY  := .build/release/$(APP)
ICONDIR := build/icon
INSTALL := /Applications

.PHONY: test build bundle run install clean

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

bundle: build $(ICONDIR)/Assets.car
	rm -rf $(BUNDLE)
	mkdir -p $(BUNDLE)/Contents/MacOS $(BUNDLE)/Contents/Resources
	cp $(BINARY) $(BUNDLE)/Contents/MacOS/
	cp $(ICONDIR)/Assets.car $(ICONDIR)/AppIcon.icns $(BUNDLE)/Contents/Resources/
	cp Info.plist $(BUNDLE)/Contents/
	printf 'APPL????' > $(BUNDLE)/Contents/PkgInfo
	codesign --force --sign - $(BUNDLE)

run: bundle
	open $(BUNDLE)

install: bundle
	pkill -x $(APP) || true
	rm -rf $(INSTALL)/$(APP).app
	cp -R $(BUNDLE) $(INSTALL)/
	open $(INSTALL)/$(APP).app

clean:
	rm -rf .build build
