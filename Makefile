CONFIG ?= release
APP := build/Hush.app

# version.txt is the single source of truth for the version; release-please bumps it.
VERSION := $(shell cat version.txt)
BUILD_NUMBER := $(shell git rev-list --count HEAD 2>/dev/null || echo 1)

# Release builds pass ARCHS="arm64 x86_64" for a universal binary.
ARCHS ?= arm64
ARCH_FLAGS := $(foreach arch,$(ARCHS),--arch $(arch))
SWIFT_BUILD := swift build -c $(CONFIG) --product Hush $(ARCH_FLAGS)

# "-" is ad-hoc. CI passes a "Developer ID Application: …" identity when signing secrets exist.
SIGN_IDENTITY ?= -
ifeq ($(SIGN_IDENTITY),-)
SIGN_FLAGS :=
else
SIGN_FLAGS := --options runtime --timestamp
endif

DMG := build/Hush-$(VERSION).dmg
DMG_ROOT := build/dmg-root

# Command Line Tools (no Xcode) don't load the Swift Testing macro plugin on their own.
CLT := /Library/Developer/CommandLineTools
TESTING_PLUGIN := $(CLT)/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib
ifeq ($(shell xcode-select -p),$(CLT))
TEST_FLAGS := -Xswiftc -load-plugin-library -Xswiftc $(TESTING_PLUGIN)
endif

.PHONY: build test app dmg icon run clean

build:
	swift build

test:
	swift test $(TEST_FLAGS)

app:
	$(SWIFT_BUILD)
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp "$$($(SWIFT_BUILD) --show-bin-path)/Hush" $(APP)/Contents/MacOS/Hush
	cp Resources/Info.plist $(APP)/Contents/Info.plist
	plutil -replace CFBundleShortVersionString -string "$(VERSION)" $(APP)/Contents/Info.plist
	plutil -replace CFBundleVersion -string "$(BUILD_NUMBER)" $(APP)/Contents/Info.plist
	plutil -lint $(APP)/Contents/Info.plist
	cp Resources/Hush.icns $(APP)/Contents/Resources/Hush.icns
	codesign --force --sign "$(SIGN_IDENTITY)" $(SIGN_FLAGS) --entitlements Resources/Hush.entitlements $(APP)

# Uses `diskutil image create from` when available, otherwise hdiutil (e.g. the macos-26 CI runner).
dmg: app
	rm -rf $(DMG_ROOT)
	mkdir -p $(DMG_ROOT)
	ditto $(APP) $(DMG_ROOT)/Hush.app
	ln -s /Applications $(DMG_ROOT)/Applications
	rm -f $(DMG)
	if diskutil image create from -h 2>&1 | grep -q 'USAGE: diskutil image create from'; then \
		diskutil image create from --format UDZO --volumeName Hush $(DMG_ROOT) $(DMG); \
	else \
		hdiutil create -volname Hush -srcfolder $(DMG_ROOT) -fs HFS+ -format UDZO -ov $(DMG); \
	fi
	cp $(DMG) build/Hush.dmg
	rm -rf $(DMG_ROOT)
	@echo "Built $(DMG) and build/Hush.dmg"

# Regenerates Resources/Hush.icns and the website icons. The .icns is committed,
# so `app` doesn't depend on this.
icon:
	rm -rf build/icon
	mkdir -p build/icon website/public
	swift scripts/make-icon.swift build/icon
	iconutil -c icns build/icon/AppIcon.iconset -o Resources/Hush.icns
	cp build/icon/favicon-32.png build/icon/logo-512.png website/public/

run: app
	open $(APP)

clean:
	rm -rf .build build
