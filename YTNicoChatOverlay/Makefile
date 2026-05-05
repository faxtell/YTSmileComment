ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:16.0
INSTALL_TARGET_PROCESSES = YouTube SpringBoard

THEOS_PACKAGE_SCHEME ?= rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = YTNicoChatOverlay

YTNicoChatOverlay_FILES = src/Tweak.xm src/AutoFetchHooks.xm src/WatchResponseAutoFetch.xm src/NetworkVideoCandidate.xm src/FetchStartDedup.xm src/ActiveAdapterDedup.xm src/PlaybackHooks.xm src/PremiereReplayRouting.xm src/ReplayParsingFallback.xm src/SettingsFetchCountAddon.xm src/NiconicoStyleSettings.xm src/MoreComments.xm src/OverlayTargetFix.xm src/BubbleButtonFade.xm src/NicoChatOverlayView.m src/NicoCommentLayer.m src/NicoChatMessage.m src/YouTubeChatAdapter.m src/YouTubeChatAdapter+DirectFetchV2.m src/YTNicoSettingsViewController.m src/SettingsManager.m src/DebugInspector.m src/UseGate.xm src/YTNicoTutorialViewController.m src/TutorialEntryHooks.xm src/AutoLaneCapacity.xm src/TutorialBubbleGuard.xm src/RotationOverlayKeepAlive.xm src/PiPCommentOverlay.xm src/SettingsBrandingAndReport.xm src/PiPBubbleButtonHide.xm src/PiPBridgeOverlay.xm src/BubbleButtonPosition.xm

YTNicoChatOverlay_FRAMEWORKS = UIKit Foundation QuartzCore WebKit AVFoundation AVKit CoreMedia
YTNicoChatOverlay_CFLAGS = -fobjc-arc -Wno-deprecated-declarations

include $(THEOS_MAKE_PATH)/tweak.mk
