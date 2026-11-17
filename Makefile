CONFIG ?= release
APP := build/Hush.app

# Command Line Tools (no Xcode) don't load the Swift Testing macro plugin on their own.
CLT := /Library/Developer/CommandLineTools
TESTING_PLUGIN := $(CLT)/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib
ifeq ($(shell xcode-select -p),$(CLT))
TEST_FLAGS := -Xswiftc -load-plugin-library -Xswiftc $(TESTING_PLUGIN)
endif

.PHONY: build test app run clean

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
	codesign --force --sign - --entitlements Resources/Hush.entitlements $(APP)

run: app
	open $(APP)

clean:
	rm -rf .build build
