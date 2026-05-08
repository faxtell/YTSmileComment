ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:16.0

THEOS_PACKAGE_SCHEME ?= rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = YTNicoChatOverlay YTNicoChatOverlaySB

YTNicoChatOverlay_INSTALL_TARGET_PROCESSES = YouTube
YTNicoChatOverlay_FILES = src/Tweak.xm src/AutoFetchHooks.xm src/WatchResponseAutoFetch.xm src/NetworkVideoCandidate.xm src/FetchStartDedup.xm src/ActiveAdapterDedup.xm src/PlaybackHooks.xm src/PremiereReplayRouting.xm src/ReplayParsingFallback.xm src/SettingsFetchCountAddon.xm src/NiconicoStyleSettings.xm src/MoreComments.xm src/OverlayTargetFix.xm src/NicoChatOverlayView.m src/NicoCommentLayer.m src/NicoChatMessage.m src/YouTubeChatAdapter.m src/YouTubeChatAdapter+DirectFetchV2.m src/YTNicoSettingsViewController.m src/SettingsManager.m src/DebugInspector.m src/UseGate.xm src/YTNicoTutorialViewController.m src/TutorialEntryHooks.xm src/AutoLaneCapacity.xm src/TutorialBubbleGuard.xm src/RotationOverlayKeepAlive.xm src/PiPCommentOverlay.xm src/PiPBubbleButtonHide.xm src/PiPBridgeOverlay.xm src/ChatStabilityWatchdog.xm src/BubbleControllerIdleFade.xm src/ReplayHTMLFallback.xm src/ChatUIScrapeFallback.xm
YTNicoChatOverlay_FRAMEWORKS = UIKit Foundation QuartzCore WebKit AVFoundation AVKit CoreMedia
YTNicoChatOverlay_CFLAGS = -fobjc-arc -Wno-deprecated-declarations

YTNicoChatOverlaySB_INSTALL_TARGET_PROCESSES = SpringBoard
YTNicoChatOverlaySB_FILES = src/PiPBridgeOverlay.xm
YTNicoChatOverlaySB_FRAMEWORKS = UIKit Foundation QuartzCore AVFoundation AVKit CoreMedia
YTNicoChatOverlaySB_CFLAGS = -fobjc-arc -Wno-deprecated-declarations

include $(THEOS_MAKE_PATH)/tweak.mk
