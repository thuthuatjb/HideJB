ARCHS := armv7 armv7s arm64 arm64e
TARGET := iphone:clang:12.1.2:8.0

include /Users/dabeecao/theos/makefiles/common.mk

TWEAK_NAME = HideJB
$(TWEAK_NAME)_FILES = Classes/HideJB.m Tweak.xm
$(TWEAK_NAME)_EXTRA_FRAMEWORKS = Cephei
$(TWEAK_NAME)_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 SpringBoard"
SUBPROJECTS += Prefs Nosub
include $(THEOS_MAKE_PATH)/aggregate.mk
