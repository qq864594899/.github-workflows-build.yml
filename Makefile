ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = XiangqiAssist
XiangqiAssist_FILES = Tweak.x

include $(THEOS_MAKE_PATH)/tweak.mk
