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

XCODE_MESSAGE := Hush needs Xcode 26+ to build. Install Xcode, then run: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer (or set DEVELOPER_DIR)

INSTALL_DIR ?= /Applications
BUNDLE_ID := io.github.aydenjahola.Hush

.PHONY: require-xcode build test integration-test app dmg install icon run clean

# Fails unless the developer directory is inside an Xcode app whose version is 26 or later.
require-xcode:
	@case "$(DEV_DIR)" in \
		*.app/Contents/Developer|*.app/Contents/Developer/) ;; \
		*) echo "$(XCODE_MESSAGE)" >&2; \
		   echo "Current developer directory: $(or $(DEV_DIR),none)" >&2; \
		   exit 1 ;; \
	esac; \
	version="$$(DEVELOPER_DIR="$(DEV_DIR)" xcodebuild -version 2>/dev/null | awk 'NR == 1 { print $$2 }')"; \
	major="$${version%%.*}"; \
	case "$$major" in ''|*[!0-9]*) major=0 ;; esac; \
	if [ "$$major" -lt 26 ]; then \
		echo "$(XCODE_MESSAGE)" >&2; \
		echo "Found Xcode $${version:-(unknown version)} at $(DEV_DIR)" >&2; \
		exit 1; \
	fi

build: require-xcode
	swift build

test: require-xcode
	swift test

# Real Core Audio tests (taps, aggregates, BlackHole loopback). Needs Audio Recording permission
# for the app running this (Terminal/VS Code); Group B also needs BlackHole 2ch. See website/src/content/docs/contributing/testing.md.
# Tests that can't run are reported as skipped with the reason.
integration-test: require-xcode
	swift build --product HushToneGenerator
	HUSH_INTEGRATION=1 swift test --no-parallel --filter HushIntegrationTests

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

# Builds first, so a failed build leaves the installed copy running. Then asks Hush to quit
# (falling back to pkill after 5 s), replaces the installed app and relaunches it. Honors ARCHS
# like `app`. The quit event is only sent while Hush runs: AppleScript would otherwise launch it.
install: app
	if pgrep -x Hush >/dev/null; then \
		osascript -e 'quit app id "$(BUNDLE_ID)"' >/dev/null 2>&1 || true; \
		for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25; do \
			pgrep -x Hush >/dev/null || break; sleep 0.2; \
		done; \
	fi
	if pgrep -x Hush >/dev/null; then \
		pkill -x Hush || true; \
		for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -x Hush >/dev/null || break; sleep 0.2; done; \
	fi
	@if pgrep -x Hush >/dev/null; then \
		echo "Hush is still running. Quit it (right-click the gear, then Quit Hush) and run make install again." >&2; \
		exit 1; \
	fi
	rm -rf "$(INSTALL_DIR)/Hush.app"
	ditto $(APP) "$(INSTALL_DIR)/Hush.app"
	open "$(INSTALL_DIR)/Hush.app"

clean:
	rm -rf .build build
