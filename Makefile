BUILD_DIR := /private/tmp/StreetPhotographySaverBuild
BUNDLE_DIR := $(BUILD_DIR)/StreetPhotography.saver
CONTENTS_DIR := $(BUNDLE_DIR)/Contents
MACOS_DIR := $(CONTENTS_DIR)/MacOS
PRODUCT := $(MACOS_DIR)/StreetPhotographySaver
CACHE_SOURCE_DIR := $(HOME)/Library/Screen Savers/Street Photography Cache
SYNC_APP_DIR := $(BUILD_DIR)/StreetPhotographySync.app
SYNC_CONTENTS_DIR := $(SYNC_APP_DIR)/Contents
SYNC_MACOS_DIR := $(SYNC_CONTENTS_DIR)/MacOS
SYNC_PRODUCT := $(SYNC_MACOS_DIR)/StreetPhotographySync
INSTALL_DIR := $(HOME)/Library/Screen Savers
APP_INSTALL_DIR := /Applications
SDK_PATH := $(shell xcrun --sdk macosx --show-sdk-path)

.PHONY: all clean install verify

all: $(PRODUCT) $(SYNC_PRODUCT) $(BUILD_DIR)/BundleVerifier

$(PRODUCT): Sources/StreetPhotographySaver/StreetPhotographySaverView.m Sources/StreetPhotographySaver/StreetPhotographySaverView.h Info.plist
	mkdir -p "$(MACOS_DIR)"
	cp Info.plist "$(CONTENTS_DIR)/Info.plist"
	xcrun clang -bundle -fobjc-arc \
		-isysroot "$(SDK_PATH)" \
		-framework AppKit \
		-framework ScreenSaver \
		-o "$(PRODUCT)" \
		Sources/StreetPhotographySaver/StreetPhotographySaverView.m
	if [ -d "$(CACHE_SOURCE_DIR)" ]; then \
		mkdir -p "$(CONTENTS_DIR)/Resources"; \
		ditto "$(CACHE_SOURCE_DIR)" "$(CONTENTS_DIR)/Resources/Cache"; \
	fi
	xattr -cr "$(BUNDLE_DIR)"
	codesign --force --sign - "$(BUNDLE_DIR)"

$(SYNC_PRODUCT): Sources/StreetPhotographySync/main.m SyncInfo.plist
	mkdir -p "$(SYNC_MACOS_DIR)"
	cp SyncInfo.plist "$(SYNC_CONTENTS_DIR)/Info.plist"
	xcrun clang -fobjc-arc \
		-isysroot "$(SDK_PATH)" \
		-framework AppKit \
		-framework Photos \
		-o "$(SYNC_PRODUCT)" \
		Sources/StreetPhotographySync/main.m
	xattr -cr "$(SYNC_APP_DIR)"
	codesign --force --sign - "$(SYNC_APP_DIR)"

$(BUILD_DIR)/PhotoAlbumVerifier: Sources/PhotoAlbumVerifier/main.m
	mkdir -p "$(BUILD_DIR)"
	xcrun clang -fobjc-arc \
		-isysroot "$(SDK_PATH)" \
		-framework Foundation \
		-framework Photos \
		-o "$(BUILD_DIR)/PhotoAlbumVerifier" \
		Sources/PhotoAlbumVerifier/main.m
	codesign --force --sign - "$(BUILD_DIR)/PhotoAlbumVerifier"

$(BUILD_DIR)/BundleVerifier: Sources/BundleVerifier/main.m
	mkdir -p "$(BUILD_DIR)"
	xcrun clang -fobjc-arc \
		-isysroot "$(SDK_PATH)" \
		-framework Foundation \
		-framework ScreenSaver \
		-o "$(BUILD_DIR)/BundleVerifier" \
		Sources/BundleVerifier/main.m
	codesign --force --sign - "$(BUILD_DIR)/BundleVerifier"

install: $(PRODUCT) $(SYNC_PRODUCT)
	mkdir -p "$(INSTALL_DIR)"
	ditto "$(BUNDLE_DIR)" "$(INSTALL_DIR)/Street Photography.saver"
	mkdir -p "$(APP_INSTALL_DIR)"
	ditto "$(SYNC_APP_DIR)" "$(APP_INSTALL_DIR)/Street Photography Sync.app"

verify: all
	"$(BUILD_DIR)/BundleVerifier" "$(BUNDLE_DIR)"

clean:
	rm -rf "$(BUILD_DIR)"
