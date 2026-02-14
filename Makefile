# See if we want verbose make.
V                  ?= 0
# Beta build or not?
BETA               ?= 0
# Build Nightly or not?
NIGHTLY            ?= 0
# Build from automation or not
AUTOMATION         ?= 0
# Build for all bootstraps or not
ALL_BOOTSTRAPS     ?= 1

DEBUG              ?= 0
IOS_DEPLOYMENT_TARGET ?= 13.0
RUN_CLANG_STATIC_ANALYZER ?= NO
SWIFT_TREAT_WARNINGS_AS_ERRORS ?= NO
GCC_TREAT_WARNINGS_AS_ERRORS ?= NO
CLANG_TREAT_WARNINGS_AS_ERRORS ?= NO
EMBED_SWIFT_STDLIB ?= 0

TARGET_CODESIGN = $(shell which ldid)

ifeq ($(EMBED_SWIFT_STDLIB),1)
SWIFT_STDLIB_EMBED_FLAG = YES
SWIFT_STDLIB_SUFFIX = -embedded-swift
else
SWIFT_STDLIB_EMBED_FLAG = NO
SWIFT_STDLIB_SUFFIX = -system-swift
endif

SILEOTMP = $(TMPDIR)/sileo
SILEO_STAGE_DIR = $(SILEOTMP)/stage

# Platform to build for.
SILEO_PLATFORM ?= iphoneos-arm
PREFIX ?=

ifeq ($(SILEO_PLATFORM),iphoneos-arm)
ARCH            = arm64
PLATFORM        = iphoneos
DEB_ARCH        = iphoneos-arm
DESTINATION     =
CONTENTS        =
SCHEME          = Sileo
BUILD_CONFIG	= Release
SILEO_APP_DIR 	= $(SILEOTMP)/Build/Products/Release-iphoneos/Sileo.app
else ifeq ($(SILEO_PLATFORM),iphoneos-arm64)
ARCH            = arm64
PLATFORM        = iphoneos
DEB_ARCH        = iphoneos-arm64
DESTINATION     =
CONTENTS        =
PREFIX          = /var/jb
SCHEME 			= Sileo
BUILD_CONFIG	= Release
SILEO_APP_DIR 	= $(SILEOTMP)/Build/Products/Release-iphoneos/Sileo.app

else ifeq ($(SILEO_PLATFORM),darwin-arm64)
# These trues are temporary
ARCH            = arm64
PLATFORM        = macosx
DEB_ARCH        = darwin-arm64
DEB_DEPENDS     = coreutils (>= 8.32-4), dpkg (>= 1.20.0), apt (>= 2.3.0), libzstd1
PREFIX          = /opt/procursus
MAC             = 1
DESTINATION     = -destination "generic/platform=macOS,variant=Mac Catalyst,name=Any Mac"
CONTENTS        = Contents/
SCHEME 			= Sileo
else ifeq ($(SILEO_PLATFORM),darwin-amd64)
# These trues are temporary
ARCH            = x86_64
PLATFORM        = macosx
DEB_ARCH        = darwin-amd64
DEB_DEPENDS     = coreutils (>= 8.32-4), dpkg (>= 1.20.0), apt (>= 2.3.0), libzstd1
PREFIX          = /opt/procursus
MAC             = 1
DESTINATION     = -destination "generic/platform=macOS,variant=Mac Catalyst,name=Any Mac"
CONTENTS        = Contents/
SCHEME 			= Sileo
endif

ifeq ($(PLATFORM),macosx)

ifneq ($(DEBUG),0)
BUILD_CONFIG  := Debug
SILEO_APP_DIR = $(SILEOTMP)/Build/Products/Debug-maccatalyst/Sileo.app
else
BUILD_CONFIG  := Release
SILEO_APP_DIR = $(SILEOTMP)/Build/Products/Release-maccatalyst/Sileo.app
endif

ifeq ($(AUTOMATION),1)
BUILD_CONFIG  := Mac_Automations
SILEO_APP_DIR = $(SILEOTMP)/Build/Products/Mac_Automations-maccatalyst/Sileo.app
endif

else
ifneq ($(DEBUG),0)
BUILD_CONFIG  := Debug
SILEO_APP_DIR = $(SILEOTMP)/Build/Products/Debug-iphoneos/Sileo.app
endif
endif

ifeq ($(PLATFORM),iphoneos)
ifeq ($(ALL_BOOTSTRAPS), 1)
DEB_DEPENDS     = firmware (>= 11.0), firmware(>=12.2) | org.swift.libswift (>=5.0), coreutils (>= 8.30-1), dpkg (>= 1.19.4-1), apt (>= 1.8.2), libzstd1
else
DEB_DEPENDS     = firmware (>= 11.0), firmware(>=12.2) | org.swift.libswift (>=5.0), coreutils (>= 8.32-4), dpkg (>= 1.20.0), apt (>= 2.3.0), libzstd1
endif
endif

ifneq (,$(shell which xcpretty))
ifeq ($(V),0)
XCPRETTY := | xcpretty
endif
endif

ifeq ($(PLATFORM),iphoneos)
ifeq ($(ALL_BOOTSTRAPS), 1)
DEB_DEPENDS     = firmware (>= 11.0), firmware(>=12.2) | org.swift.libswift (>=5.0), coreutils (>= 8.30-1), dpkg (>= 1.19.4-1), apt (>= 1.8.2), libzstd1
else
DEB_DEPENDS     = firmware (>= 11.0), firmware(>=12.2) | org.swift.libswift (>=5.0), coreutils (>= 8.32-4), dpkg (>= 1.20.0), apt (>= 2.3.0), libzstd1
endif
endif

ifneq (,$(shell which xcpretty))
ifeq ($(V),0)
XCPRETTY := | xcpretty
endif
endif

MAKEFLAGS += --no-print-directory

export EXPANDED_CODE_SIGN_IDENTITY =
export EXPANDED_CODE_SIGN_IDENTITY_NAME =

STRIP = xcrun strip

ifneq ($(MAC), 1)
export PRODUCT_BUNDLE_IDENTIFIER = "org.coolstar.SileoStore"
SILEO_ID   = org.coolstar.sileo
else
export PRODUCT_BUNDLE_IDENTIFIER = "sileo"
SILEO_ID   = sileo
endif
export DISPLAY_NAME = "Sileo"
ICON = https:\/\/getsileo.app\/img\/icon.png
SILEO_NAME = Sileo
SILEO_APP  = Sileo.app
SILEO_VERSION = $$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" $(SILEO_STAGE_DIR)/$(PREFIX)/Applications/$(SILEO_APP)/$(CONTENTS)Info.plist)


ifeq ($(BETA), 1)
ifeq ($(MAC), 1)
export PRODUCT_BUNDLE_IDENTIFIER = "sileobeta"
SILEO_ID   = sileobeta
SILEO_APP  = Sileo.app
else
export PRODUCT_BUNDLE_IDENTIFIER = "org.coolstar.SileoBeta"
SILEO_ID   = org.coolstar.sileobeta
SILEO_APP  = Sileo-Beta.app
endif
ICON = https:\/\/getsileo.app\/img\/icon.png
export DISPLAY_NAME = "Sileo Beta"
SILEO_NAME = Sileo (Beta Channel)
SILEO_VERSION = $$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" $(SILEO_STAGE_DIR)/$(PREFIX)/Applications/$(SILEO_APP)/$(CONTENTS)Info.plist)+$$(git show -s --format=%cd --date=short HEAD | sed s/-//g).$$(git show -s --format=%cd --date=unix HEAD | sed s/-//g).$$(git rev-parse --short=7 HEAD)
endif

ifeq ($(NIGHTLY), 1)
ifeq ($(MAC), 1)
export PRODUCT_BUNDLE_IDENTIFIER = "sileonightly"
SILEO_ID   = sileonightly
SILEO_APP  = Sileo.app
else
export PRODUCT_BUNDLE_IDENTIFIER = "org.coolstar.SileoNightly"
SILEO_ID   = org.coolstar.sileonightly
SILEO_APP  = Sileo-Nightly.app
endif
export DISPLAY_NAME = "Sileo Nightly"
ICON = https:\/\/github.com\/Sileo\/Sileo\/raw\/stable\/Icons\/Nightly\/Nightly_iOS.png
SILEO_NAME = Sileo (Nightly Channel)
SILEO_VERSION = $$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" $(SILEO_STAGE_DIR)/$(PREFIX)/Applications/$(SILEO_APP)/$(CONTENTS)Info.plist)+$$(git show -s --format=%cd --date=short HEAD | sed s/-//g).$$(git show -s --format=%cd --date=unix HEAD | sed s/-//g).$$(git rev-parse --short=7 HEAD)
endif

ifeq ($(ALL_BOOTSTRAPS), 1)
DPKG_TYPE ?= xz
else ifeq ($(shell dpkg-deb --help | grep -qi "zstd" && echo 1),1)
DPKG_TYPE ?= zstd
else
DPKG_TYPE ?= xz
endif

giveMeRoot/bin/giveMeRoot: giveMeRoot/giveMeRoot.c
	$(MAKE) -C giveMeRoot \
		CC="xcrun -sdk $(PLATFORM) clang -arch $(ARCH) -mios-version-min=11.0"
		
ifneq ($(MAC), 1)
all:: giveMeRoot/bin/giveMeRoot
else
all ::
endif

ifneq ($(MAC),1)
stage: all
	@echo $(BUILD_CONFIG)
	@echo $(ARCH)
	@echo $(PLATFORM)
	@echo $(SILEO_APP_DIR)
	@echo $(SILEO_STAGE_DIR)/$(PREFIX)/Applications/$(SILEO_APP)
	@set -o pipefail; \
		xcodebuild -jobs $(shell sysctl -n hw.ncpu) -project 'Sileo.xcodeproj' -scheme "$(SCHEME)" -configuration $(BUILD_CONFIG) -arch $(ARCH) -sdk $(PLATFORM) -derivedDataPath $(SILEOTMP) \
		CODE_SIGNING_ALLOWED=NO IPHONEOS_DEPLOYMENT_TARGET=$(IOS_DEPLOYMENT_TARGET) RUN_CLANG_STATIC_ANALYZER=$(RUN_CLANG_STATIC_ANALYZER) SWIFT_TREAT_WARNINGS_AS_ERRORS=$(SWIFT_TREAT_WARNINGS_AS_ERRORS) GCC_TREAT_WARNINGS_AS_ERRORS=$(GCC_TREAT_WARNINGS_AS_ERRORS) CLANG_TREAT_WARNINGS_AS_ERRORS=$(CLANG_TREAT_WARNINGS_AS_ERRORS) PRODUCT_BUNDLE_IDENTIFIER=$(PRODUCT_BUNDLE_IDENTIFIER) DISPLAY_NAME=$(DISPLAY_NAME) \
		DSTROOT=$(SILEOTMP)/install $(XCPRETTY) ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES=$(SWIFT_STDLIB_EMBED_FLAG)
	@rm -rf $(SILEO_STAGE_DIR)/
	@mkdir -p $(SILEO_STAGE_DIR)/$(PREFIX)/Applications/
	@mv $(SILEO_APP_DIR) $(SILEO_STAGE_DIR)/$(PREFIX)/Applications/$(SILEO_APP)
	@APP_DIR="$(SILEO_STAGE_DIR)/$(PREFIX)/Applications/$(SILEO_APP)"; \
	APP_EXE="$$APP_DIR/Sileo"; \
	if [ ! -f "$$APP_EXE" ]; then \
		APP_EXE="$$APP_DIR/$$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$$APP_DIR/Info.plist" 2>/dev/null || echo Sileo)"; \
	fi; \
	if [ ! -f "$$APP_EXE" ]; then \
		echo "Unable to resolve app executable path: $$APP_EXE"; \
		exit 1; \
	fi; \
	if [ "$(SWIFT_STDLIB_EMBED_FLAG)" = "YES" ]; then \
		for SWIFT_LIB in $$(xcrun otool -L "$$APP_EXE" | awk '/\/usr\/lib\/swift\/libswift.*\.dylib/ {print $$1}'); do \
			SWIFT_BASE=$$(basename "$$SWIFT_LIB"); \
			xcrun install_name_tool -change "$$SWIFT_LIB" "@rpath/$$SWIFT_BASE" "$$APP_EXE"; \
		done; \
		while xcrun otool -l "$$APP_EXE" | grep -q '@executable_path/Frameworks'; do \
			xcrun install_name_tool -delete_rpath @executable_path/Frameworks "$$APP_EXE"; \
		done; \
		while xcrun otool -l "$$APP_EXE" | grep -q '/opt/procursus/lib'; do \
			xcrun install_name_tool -delete_rpath /opt/procursus/lib "$$APP_EXE"; \
		done; \
		while xcrun otool -l "$$APP_EXE" | grep -q '/var/jb/usr/local/lib'; do \
			xcrun install_name_tool -delete_rpath /var/jb/usr/local/lib "$$APP_EXE"; \
		done; \
		while xcrun otool -l "$$APP_EXE" | grep -q '/var/jb/usr/lib'; do \
			xcrun install_name_tool -delete_rpath /var/jb/usr/lib "$$APP_EXE"; \
		done; \
		xcrun install_name_tool -add_rpath @executable_path/Frameworks "$$APP_EXE"; \
		xcrun install_name_tool -add_rpath /opt/procursus/lib "$$APP_EXE"; \
		xcrun install_name_tool -add_rpath /var/jb/usr/local/lib "$$APP_EXE"; \
		xcrun install_name_tool -add_rpath /var/jb/usr/lib "$$APP_EXE"; \
		while xcrun otool -l "$$APP_EXE" | grep -q '/usr/lib/swift'; do \
			xcrun install_name_tool -delete_rpath /usr/lib/swift "$$APP_EXE"; \
		done; \
		while xcrun otool -l "$$APP_EXE" | grep -q '/usr/lib/libswift/stable'; do \
			xcrun install_name_tool -delete_rpath /usr/lib/libswift/stable "$$APP_EXE"; \
		done; \
		if xcrun otool -L "$$APP_EXE" | grep -q '/usr/lib/swift/libswift'; then \
			echo "Embedded mode validation failed: still has absolute /usr/lib/swift/libswift load commands"; \
			exit 1; \
		fi; \
	else \
		if ! xcrun otool -l "$$APP_EXE" | grep -q '/usr/lib/swift'; then \
			xcrun install_name_tool -add_rpath /usr/lib/swift "$$APP_EXE"; \
		fi; \
	fi
	@if [ "$(SWIFT_STDLIB_EMBED_FLAG)" = "YES" ]; then \
		APP_DIR="$(SILEO_STAGE_DIR)/$(PREFIX)/Applications/$(SILEO_APP)"; \
		APP_EXE="$$APP_DIR/Sileo"; \
		if [ ! -f "$$APP_EXE" ]; then \
			APP_EXE="$$APP_DIR/$$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$$APP_DIR/Info.plist" 2>/dev/null || echo Sileo)"; \
		fi; \
		if [ ! -f "$$APP_EXE" ]; then \
			echo "Unable to resolve app executable path for swift-stdlib-tool: $$APP_EXE"; \
			exit 1; \
		fi; \
		mkdir -p "$$APP_DIR/Frameworks"; \
		xcrun swift-stdlib-tool --copy --scan-executable "$$APP_EXE" --scan-folder "$$APP_DIR/Frameworks" --platform iphoneos --destination "$$APP_DIR/Frameworks"; \
		SWIFT_BIN="$$(xcrun --find swift)"; \
		TOOLCHAIN_DIR="$$(cd "$$(dirname "$$SWIFT_BIN")/.." && pwd)"; \
		for SWIFT_REF in $$(xcrun otool -L "$$APP_EXE" | awk '/@rpath\/libswift.*\.dylib/ {print $$1}'); do \
			SWIFT_BASE="$$(basename "$$SWIFT_REF")"; \
			if [ ! -f "$$APP_DIR/Frameworks/$$SWIFT_BASE" ]; then \
				COPIED=0; \
				for SEARCH_DIR in "$$TOOLCHAIN_DIR/lib/swift/iphoneos" "$$TOOLCHAIN_DIR/lib/swift-5.5/iphoneos" "$$TOOLCHAIN_DIR/usr/lib/swift/iphoneos" "$$TOOLCHAIN_DIR/usr/lib/swift-5.5/iphoneos"; do \
					if [ -f "$$SEARCH_DIR/$$SWIFT_BASE" ]; then \
						cp "$$SEARCH_DIR/$$SWIFT_BASE" "$$APP_DIR/Frameworks/$$SWIFT_BASE"; \
						COPIED=1; \
						break; \
					fi; \
				done; \
				if [ $$COPIED -ne 1 ]; then \
					echo "Missing required Swift runtime library in toolchain: $$SWIFT_BASE"; \
					exit 1; \
				fi; \
			fi; \
		done; \
		for SWIFT_DYLIB in $$APP_DIR/Frameworks/libswift*.dylib; do \
			if [ -f "$$SWIFT_DYLIB" ]; then \
				SWIFT_BASE=$$(basename "$$SWIFT_DYLIB"); \
				xcrun install_name_tool -id "@rpath/$$SWIFT_BASE" "$$SWIFT_DYLIB"; \
			fi; \
		done; \
	fi
	
	@function process_exec { \
		$(STRIP) $$1; \
	}; \
	function process_bundle { \
		process_exec $$1/$$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" $$1/Info.plist); \
	}; \
	export -f process_exec process_bundle; \
	if [ "$(SWIFT_STDLIB_EMBED_FLAG)" = "YES" ]; then \
		find $(SILEO_STAGE_DIR)/$(PREFIX)/Applications/$(SILEO_APP) -name '*.dylib' ! -path '*/Frameworks/*' -print0 | xargs -I{} -0 bash -c 'process_exec "$$@"' _ {}; \
	else \
		find $(SILEO_STAGE_DIR)/$(PREFIX)/Applications/$(SILEO_APP) -name '*.dylib' -print0 | xargs -I{} -0 bash -c 'process_exec "$$@"' _ {}; \
	fi; \
	find $(SILEO_STAGE_DIR)/$(PREFIX)/Applications/$(SILEO_APP) \( -name '*.framework' -or -name '*.appex' \) -print0 | xargs -I{} -0 bash -c 'process_bundle "$$@"' _ {}; \
	process_bundle $(SILEO_STAGE_DIR)/$(PREFIX)/Applications/$(SILEO_APP)
	
	@rm -rf $(SILEO_STAGE_DIR)/$(PREFIX)/Applications/$(SILEO_APP)/_CodeSignature
	@if [ "$(SWIFT_STDLIB_EMBED_FLAG)" = "YES" ]; then \
		find $(SILEO_STAGE_DIR)/$(PREFIX)/Applications/$(SILEO_APP)/Frameworks -type f -name '*.dylib' -print0 | xargs -0 -I{} $(TARGET_CODESIGN) -S {}; \
	fi
	@if [ "$(SWIFT_STDLIB_EMBED_FLAG)" = "NO" ]; then \
		rm -rf $(SILEO_STAGE_DIR)/$(PREFIX)/Applications/$(SILEO_APP)/Frameworks; \
	fi
	@cp giveMeRoot/bin/giveMeRoot $(SILEO_STAGE_DIR)/$(PREFIX)/Applications/$(SILEO_APP)/
	@$(TARGET_CODESIGN) -SSileo/Entitlements.entitlements $(SILEO_STAGE_DIR)/$(PREFIX)/Applications/$(SILEO_APP)/
	@$(TARGET_CODESIGN) -SgiveMeRoot/Entitlements.plist $(SILEO_STAGE_DIR)/$(PREFIX)/Applications/$(SILEO_APP)/giveMeRoot
	@chmod 4755 $(SILEO_STAGE_DIR)/$(PREFIX)/Applications/$(SILEO_APP)/giveMeRoot
else
stage: all
	@set -o pipefail; \
		xcodebuild -jobs $(shell sysctl -n hw.ncpu) -project 'Sileo.xcodeproj' -scheme 'Sileo' $(DESTINATION) -configuration $(BUILD_CONFIG) ARCHS=$(ARCH) -derivedDataPath $(SILEOTMP) \
		RUN_CLANG_STATIC_ANALYZER=$(RUN_CLANG_STATIC_ANALYZER) SWIFT_TREAT_WARNINGS_AS_ERRORS=$(SWIFT_TREAT_WARNINGS_AS_ERRORS) GCC_TREAT_WARNINGS_AS_ERRORS=$(GCC_TREAT_WARNINGS_AS_ERRORS) CLANG_TREAT_WARNINGS_AS_ERRORS=$(CLANG_TREAT_WARNINGS_AS_ERRORS) \
		DSTROOT=$(SILEOTMP)/install $(XCPRETTY) ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES=$(SWIFT_STDLIB_EMBED_FLAG)
	@rm -rf $(SILEO_STAGE_DIR)
	@mkdir -p $(SILEO_STAGE_DIR)/$(PREFIX)/Applications/
	@rm -rf $(SILEO_STAGE_DIR)/$(PREFIX)/Applications/$(SILEO_APP)
	@mv $(SILEO_APP_DIR) $(SILEO_STAGE_DIR)/$(PREFIX)/Applications/$(SILEO_APP)
	@if [ "$(SWIFT_STDLIB_EMBED_FLAG)" = "NO" ]; then \
		rm -rf $(SILEO_STAGE_DIR)/$(PREFIX)/Applications/$(SILEO_APP)/Frameworks; \
	fi
endif

ifeq ($(MAC), 1)
package: stage
	@cp -a ./layout/DEBIAN $(SILEO_STAGE_DIR)
	@sed -e s/@@MARKETING_VERSION@@/$(SILEO_VERSION)/ \
		-e 's/@@PACKAGE_ID@@/$(SILEO_ID)/' \
		-e 's/@@PACKAGE_NAME@@/$(SILEO_NAME)/' \
		-e 's/@@DEB_ARCH@@/$(DEB_ARCH)/' \
		-e 's/@@ICON@@/$(ICON)/' \
		-e 's/@@DEB_DEPENDS@@/$(DEB_DEPENDS)/' $(SILEO_STAGE_DIR)/DEBIAN/control.in > $(SILEO_STAGE_DIR)/DEBIAN/control
	@mv $(SILEO_STAGE_DIR)/DEBIAN/postinst-mac.in $(SILEO_STAGE_DIR)/DEBIAN/postinst
	@chmod 0755 $(SILEO_STAGE_DIR)/DEBIAN/postinst
	@rm -f $(SILEO_STAGE_DIR)/DEBIAN/control.in
	@rm -rf $(SILEO_STAGE_DIR)/DEBIAN/postinst.in
	@rm -rf $(SILEO_STAGE_DIR)/DEBIAN/postinst-mac.in
	@rm -rf $(SILEO_STAGE_DIR)/DEBIAN/prerm
	@rm -rf $(SILEO_STAGE_DIR)/DEBIAN/triggers
	@rm -rf $(SILEO_STAGE_DIR)/$(PREFIX)/Applications/$(SILEO_APP)/Contents/PkgInfo
	@mv $(SILEO_STAGE_DIR)/DEBIAN/prerm-mac $(SILEO_STAGE_DIR)/DEBIAN/prerm
	@chmod 0755 $(SILEO_STAGE_DIR)/DEBIAN/prerm
	@mkdir -p ./packages
	@dpkg-deb -Z$(DPKG_TYPE) --root-owner-group -b $(SILEO_STAGE_DIR) ./packages/$(SILEO_ID)_$(SILEO_VERSION)_$(DEB_ARCH)$(SWIFT_STDLIB_SUFFIX).deb
else
package: stage
	@cp -a ./layout/DEBIAN $(SILEO_STAGE_DIR)
	@sed -e s/@@MARKETING_VERSION@@/$(SILEO_VERSION)/ \
		-e 's/@@PACKAGE_ID@@/$(SILEO_ID)/' \
		-e 's/@@PACKAGE_NAME@@/$(SILEO_NAME)/' \
		-e 's/@@DEB_ARCH@@/$(DEB_ARCH)/' \
		-e 's/@@ICON@@/$(ICON)/' \
		-e 's/@@DEB_DEPENDS@@/$(DEB_DEPENDS)/' $(SILEO_STAGE_DIR)/DEBIAN/control.in > $(SILEO_STAGE_DIR)/DEBIAN/control
	@rm -f $(SILEO_STAGE_DIR)/DEBIAN/control.in
	@sed -e s/@@SILEO_APP@@/$(SILEO_APP)/ \
		$(SILEO_STAGE_DIR)/DEBIAN/postinst.in > $(SILEO_STAGE_DIR)/DEBIAN/postinst
	@chmod 0755 $(SILEO_STAGE_DIR)/DEBIAN/postinst
	@rm -f $(SILEO_STAGE_DIR)/DEBIAN/postinst.in
	@rm -rf $(SILEO_STAGE_DIR)/DEBIAN/postinst-mac.in
	@rm -rf $(SILEO_STAGE_DIR)/DEBIAN/prerm-mac
	@rm -rf "$(SILEO_STAGE_DIR)/Applications/$(SILEO_APP)/Down_Down.bundle/DownView (macOS).bundle"
	@mkdir -p ./packages
	@dpkg-deb -Z$(DPKG_TYPE) --root-owner-group -b $(SILEO_STAGE_DIR) ./packages/$(SILEO_ID)_$(SILEO_VERSION)_$(DEB_ARCH)$(SWIFT_STDLIB_SUFFIX).deb
endif

clean::
	@$(MAKE) -C giveMeRoot clean
	@rm -rf $(SILEOTMP)
