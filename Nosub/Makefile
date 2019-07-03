include /Users/dabeecao/theos/makefiles/common.mk

ARCHS = armv7 armv7s arm64 arm64e
TWEAK_NAME = HideJBNosub

FindFiles = $(foreach ext, c cpp m mm x xm xi xmi, $(wildcard $(1)/*.$(ext)))
HideJBNosub_FILES = Classes/HideJBTweak.m $(call FindFiles, Hooks)

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/aggregate.mk

after-install::
	install.exec "killall -9 SpringBoard"
