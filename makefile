ARCHS := arm64
TARGET := iphone:clang:16.5:14.0
DEBUG = 0
FINALPACKAGE = 1
FOR_RELEASE = 1
INSTALL_TARGET_PROCESSES := External_ESP_FF

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME := External_ESP_FF

$(APPLICATION_NAME)_USE_MODULES := 0
$(APPLICATION_NAME)_FILES += $(wildcard sources/*.mm sources/*.m)
$(APPLICATION_NAME)_FILES += $(wildcard sources/KIF/*.mm sources/KIF/*.m)
$(APPLICATION_NAME)_FILES += $(wildcard esp/drawing_view/*.mm)
$(APPLICATION_NAME)_FILES += $(wildcard esp/Core/*.mm)
$(APPLICATION_NAME)_FILES += $(wildcard esp/Core/*.cpp)

sources/KIF/UITouch-KIFAdditions.m_CFLAGS := $(filter-out -mllvm -enable-fco,$(External_ESP_FF_CFLAGS))

$(APPLICATION_NAME)_CFLAGS += -fobjc-arc -Wno-deprecated-declarations -Wno-unused-function -Wno-unused-variable -Wno-unused-value -Wno-module-import-in-extern-c -Wunused-but-set-variable
$(APPLICATION_NAME)_CFLAGS += -Iheaders
$(APPLICATION_NAME)_CFLAGS += -Isources
$(APPLICATION_NAME)_CFLAGS += -Isources/KIF
$(APPLICATION_NAME)_CFLAGS += -Iesp/Core
$(APPLICATION_NAME)_CFLAGS += -Iesp/drawing_view
$(APPLICATION_NAME)_CFLAGS += -DNOTIFY_DESTROY_HUD="\"dev.metaware.external.hud.destroy\""
$(APPLICATION_NAME)_CFLAGS += -DPID_PATH="@\"/var/mobile/Library/Caches/dev.metaware.external.pid\""
$(APPLICATION_NAME)_CCFLAGS += -std=c++17

$(APPLICATION_NAME)_FRAMEWORKS += CoreGraphics CoreServices QuartzCore IOKit UIKit AVFoundation AVKit CoreMedia CoreVideo
$(APPLICATION_NAME)_PRIVATE_FRAMEWORKS += BackBoardServices GraphicsServices SpringBoardServices
$(APPLICATION_NAME)_CODESIGN_FLAGS += -Slayout/entitlements.plist
$(APPLICATION_NAME)_RESOURCE_DIRS = ./layout/Resources

include $(THEOS_MAKE_PATH)/application.mk
include $(THEOS_MAKE_PATH)/aggregate.mk

after-package::
	@rm -rf Payload
	@mkdir -p Payload
	@cp -r .theos/_/Applications/$(APPLICATION_NAME).app Payload/
	@cp layout/Info.plist Payload/$(APPLICATION_NAME).app/Info.plist
	@chmod 755 Payload/$(APPLICATION_NAME).app/$(APPLICATION_NAME)
	@zip -rq $(APPLICATION_NAME).tipa Payload
	@rm -rf Payload
	@mkdir -p packages
	@mv $(APPLICATION_NAME).tipa packages/
	@echo "[*] Build completed successfully: packages/$(APPLICATION_NAME).tipa"


