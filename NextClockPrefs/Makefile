ARCHS = arm64 arm64e
TARGET := iphone:clang:16.5:15.0
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = NextClockPrefs

NextClockPrefs_FILES = NCRootListControllerRootListController.m
NextClockPrefs_FRAMEWORKS = UIKit UniformTypeIdentifiers ImageIO
NextClockPrefs_PRIVATE_FRAMEWORKS = Preferences
NextClockPrefs_INSTALL_PATH = /Library/PreferenceBundles
NextClockPrefs_CFLAGS = -fobjc-arc

NextClockPrefs_LIBRARIES = z

include $(THEOS_MAKE_PATH)/bundle.mk
