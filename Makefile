ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0
INSTALL_TARGET_PROCESSES = VLC

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = BackgroundAudio
BackgroundAudio_FILES = Tweak.xm
BackgroundAudio_FRAMEWORKS = AVFoundation UIKit
BackgroundAudio_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 SpringBoard"
