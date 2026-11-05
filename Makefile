include $(CURDIR)/BuildConfig.mk
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = NextClock

NextClock_FILES = Tweak.x
NextClock_CFLAGS = -fobjc-arc
ifeq ($(NC_PRO),1)
NextClock_CFLAGS += -DNC_PRO_BUILD=1
endif
ifeq ($(NC_LEGACY),1)
NextClock_CFLAGS += -DNC_LEGACY_BUILD=1 -Werror=unguarded-availability
endif
NextClock_FRAMEWORKS = UIKit ImageIO QuartzCore

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += NextClockPrefs
include $(THEOS_MAKE_PATH)/aggregate.mk

ifeq ($(NC_PRO),1)
THEOS_PACKAGE_NAME := com.ratnik00.nextclock.pro
THEOS_PACKAGE_DIR = $(THEOS_PROJECT_DIR)/packages/pro-alpha
before-package::
	mkdir -p "$(THEOS_PACKAGE_DIR)"
	python3 "$(THEOS_PROJECT_DIR)/Scripts/pro_metadata.py" "$(THEOS_STAGING_DIR)"
endif

ifeq ($(NC_LEGACY),1)
THEOS_PACKAGE_ARCH := iphoneos-arm
ifeq ($(NC_LEGACY_ARM64E),1)
THEOS_PACKAGE_DIR = $(THEOS_PROJECT_DIR)/packages/legacy-ios14
else
THEOS_PACKAGE_DIR = $(THEOS_PROJECT_DIR)/packages/legacy-arm64
endif
before-package::
	mkdir -p "$(THEOS_PACKAGE_DIR)"
	python3 "$(THEOS_PROJECT_DIR)/Scripts/legacy_metadata.py" "$(THEOS_STAGING_DIR)" "$(NC_LEGACY_ARM64E)"
endif
