ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:16.0
INSTALL_TARGET_PROCESSES = YouTube

THEOS_PACKAGE_SCHEME ?= rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = YTNicoChatOverlay

YTNicoChatOverlay_FILES = \
	src/Tweak.xm \
	src/AutoFetchHooks.xm \
	src/NicoChatOverlayView.m \
	src/NicoCommentLayer.m \
	src/NicoChatMessage.m \
	src/YouTubeChatAdapter.m \
	src/YouTubeChatAdapter+DirectFetch.m \
	src/YTNicoSettingsViewController.m \
	src/SettingsManager.m \
	src/DebugInspector.m

YTNicoChatOverlay_FRAMEWORKS = UIKit Foundation QuartzCore WebKit
YTNicoChatOverlay_CFLAGS = -fobjc-arc -Wno-deprecated-declarations

include $(THEOS_MAKE_PATH)/tweak.mk
