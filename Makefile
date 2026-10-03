ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = XiangqiAssist
XiangqiAssist_FILES = Tweak.xm
XiangqiAssist_PLIST = XiangqiAssist.plist
XiangqiAssist_FRAMEWORKS = UIKit CoreML
XiangqiAssist_CFLAGS = -Ilibs -std=c++17
XiangqiAssist_LDFLAGS = -Llibs -lpikafish -lc++
XiangqiAssist_LIBRARIES = pikafish
XiangqiAssist_OBJ_FILES = libs/pikafish_wrapper.o

include $(THEOS_MAKE_PATH)/tweak.mk
