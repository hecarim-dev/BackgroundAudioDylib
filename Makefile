export TARGET = iphone:clang:latest:15.0
export ARCHS = arm64 arm64e
export THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = BackgroundAudio
BackgroundAudio_FILES = Tweak.xm
BackgroundAudio_FRAMEWORKS = UIKit AVFoundation Foundation
BackgroundAudio_CFLAGS = -fobjc-arc -w
BackgroundAudio_LDFLAGS += -undefined dynamic_lookup

include $(THEOS_MAKE_PATH)/tweak.mk
