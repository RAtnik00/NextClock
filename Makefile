ARCHS = arm64 arm64e
TARGET := iphone:clang:16.5:15.0
THEOS_PACKAGE_SCHEME = rootless
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = NextClock

NextClock_FILES = Tweak.x
NextClock_CFLAGS = -fobjc-arc
NextClock_FRAMEWORKS = UIKit ImageIO QuartzCore

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += NextClockPrefs
include $(THEOS_MAKE_PATH)/aggregate.mk
