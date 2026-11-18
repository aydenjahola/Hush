CONFIG ?= release
APP := build/Hush.app

# Command Line Tools (no Xcode) don't load the Swift Testing macro plugin on their own.
CLT := /Library/Developer/CommandLineTools
TESTING_PLUGIN := $(CLT)/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib
ifeq ($(shell xcode-select -p),$(CLT))
TEST_FLAGS := -Xswiftc -load-plugin-library -Xswiftc $(TESTING_PLUGIN)
endif

.PHONY: build test app icon run clean

build:
	swift build

test:
	swift test $(TEST_FLAGS)

app:
	swift build -c $(CONFIG) --product Hush
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp "$$(swift build -c $(CONFIG) --show-bin-path)/Hush" $(APP)/Contents/MacOS/Hush
	cp Resources/Info.plist $(APP)/Contents/Info.plist
	plutil -lint $(APP)/Contents/Info.plist
	cp Resources/Hush.icns $(APP)/Contents/Resources/Hush.icns
	codesign --force --sign - --entitlements Resources/Hush.entitlements $(APP)

# Regenerates Resources/Hush.icns and the website icons. The .icns is committed,
# so `app` doesn't depend on this.
icon:
	rm -rf build/icon
	mkdir -p build/icon website-assets
	swift scripts/make-icon.swift build/icon
	iconutil -c icns build/icon/AppIcon.iconset -o Resources/Hush.icns
	cp build/icon/favicon-32.png build/icon/logo-512.png website-assets/

run: app
	open $(APP)

clean:
	rm -rf .build build
