# Default release remains rootless iOS 15+. Legacy builds are opt-in.
ifeq ($(NC_PRO),1)
ifeq ($(NC_LEGACY),1)
$(error Pro prototype currently targets rootless iOS 15+ only)
endif
PACKAGE_VERSION = 0.1.0~alpha1
ifneq ($(PACKAGE_VERSION),0.1.0~alpha1)
$(error Pro package version must match Shared/NCVersion.h: 0.1.0~alpha1)
endif
export NC_PRO
endif
ifeq ($(NC_LEGACY),1)
PACKAGE_VERSION = 1.1.1~legacy1
ifneq ($(PACKAGE_VERSION),1.1.1~legacy1)
$(error Legacy package version must match Shared/NCVersion.h: 1.1.1~legacy1)
endif
THEOS_PACKAGE_SCHEME =
ifeq ($(NC_LEGACY_ARM64E),1)
ARCHS = arm64 arm64e
TARGET := iphone:clang:16.5:14.0
else
# Modern Xcode cannot emit the iOS 12/13 arm64e ABI.
ARCHS = arm64
TARGET := iphone:clang:16.5:12.0
endif
export NC_LEGACY NC_LEGACY_ARM64E
else
ARCHS = arm64 arm64e
TARGET := iphone:clang:16.5:15.0
THEOS_PACKAGE_SCHEME = rootless
endif
