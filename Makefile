ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = K4LSnap K4LSnapSpringBoard

K4LSnap_ARCHS = arm64 arm64e
K4LSnap_FILES =
K4LSnap_CFLAGS = -fobjc-arc -fblocks -Wall -Wextra -Werror=return-type
K4LSnap_FRAMEWORKS = Foundation CoreFoundation
K4LSnap_LIBRARIES = substrate

K4LSnapSpringBoard_ARCHS = arm64 arm64e
K4LSnapSpringBoard_FILES =
K4LSnapSpringBoard_CFLAGS = -fobjc-arc -fblocks -Wall -Wextra -Werror=return-type
K4LSnapSpringBoard_FRAMEWORKS = Foundation CoreFoundation UIKit
K4LSnapSpringBoard_LIBRARIES = substrate

BUNDLE_NAME = K4LSnapPrefs

K4LSnapPrefs_ARCHS = arm64 arm64e
K4LSnapPrefs_FILES =
K4LSnapPrefs_CFLAGS = -fobjc-arc -fblocks -Wall -Wextra -Werror=return-type
K4LSnapPrefs_FRAMEWORKS = Foundation UIKit
K4LSnapPrefs_PRIVATE_FRAMEWORKS = Preferences
K4LSnapPrefs_INSTALL_PATH = /Library/PreferenceBundles

TOOL_NAME = k4lsnapd k4lsnapctl

k4lsnapd_ARCHS = arm64
k4lsnapd_FILES =
k4lsnapd_CFLAGS = -fobjc-arc -fblocks -Wall -Wextra -Werror=return-type
k4lsnapd_FRAMEWORKS = Foundation
k4lsnapd_INSTALL_PATH = /usr/libexec

k4lsnapctl_ARCHS = arm64 arm64e
k4lsnapctl_FILES =
k4lsnapctl_CFLAGS = -fobjc-arc -fblocks -Wall -Wextra -Werror=return-type
k4lsnapctl_FRAMEWORKS = Foundation
k4lsnapctl_INSTALL_PATH = /usr/local/bin

# Source files are admitted only by their owning roadmap steps. Empty source lists
# are deliberate in Step 3: no inert constructors, fake services, or placeholder
# implementations are permitted merely to make a target link.

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/bundle.mk
include $(THEOS_MAKE_PATH)/tool.mk
