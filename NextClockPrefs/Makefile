include $(dir $(lastword $(MAKEFILE_LIST)))../BuildConfig.mk

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = NextClockPrefs

NextClockPrefs_FILES = NCRootListControllerRootListController.m NCProController.m
ifeq ($(NC_PRO),1)
NextClockPrefs_CFLAGS += -DNC_PRO_BUILD=1
endif
NextClockPrefs_FRAMEWORKS = UIKit UniformTypeIdentifiers ImageIO
ifeq ($(NC_LEGACY),1)
NextClockPrefs_FRAMEWORKS = UIKit ImageIO
NextClockPrefs_WEAK_FRAMEWORKS = UniformTypeIdentifiers
endif
NextClockPrefs_PRIVATE_FRAMEWORKS = Preferences
NextClockPrefs_INSTALL_PATH = /Library/PreferenceBundles
NextClockPrefs_CFLAGS += -fobjc-arc
NextClockPrefs_FRAMEWORKS += QuartzCore
ifeq ($(NC_LEGACY),1)
NextClockPrefs_CFLAGS += -DNC_LEGACY_BUILD=1 -Werror=unguarded-availability
endif

NextClockPrefs_LIBRARIES = z

include $(THEOS_MAKE_PATH)/bundle.mk
