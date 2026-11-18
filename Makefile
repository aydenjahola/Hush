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

# Building needs a full Xcode (26+), not just the Command Line Tools: Swift Testing and the
# SwiftUI/Observation macros ship with Xcode. DEVELOPER_DIR, when set, wins over xcode-select.
DEV_DIR := $(or $(DEVELOPER_DIR),$(shell xcode-select -p 2>/dev/null))

.PHONY: require-xcode build test app dmg icon run clean

require-xcode:
	@case "$(DEV_DIR)" in \
		*.app/Contents/Developer|*.app/Contents/Developer/) ;; \
		*) echo "Hush needs Xcode 26+ to build. Install Xcode, then run: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer (or set DEVELOPER_DIR)" >&2; \
		   echo "Current developer directory: $(or $(DEV_DIR),none)" >&2; \
		   exit 1 ;; \
	esac

build: require-xcode
	swift build

test: require-xcode
	swift test

app: require-xcode
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
