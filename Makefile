APP     := AppPause
BUNDLE  := build/$(APP).app
BINARY  := .build/release/$(APP)
INSTALL := /Applications

.PHONY: test build bundle run install clean

test:
	swift test

build:
	swift build -c release

bundle: build
	rm -rf $(BUNDLE)
	mkdir -p $(BUNDLE)/Contents/MacOS
	cp $(BINARY) $(BUNDLE)/Contents/MacOS/
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
