# MHI2Q MMI Mirror V2.2 / JAVA80 pixel-only Native build

BUILD_DIR ?= build
TARGET ?= $(BUILD_DIR)/mmi-mirror-display

QNX_HOST ?= /usr/qnx650/host/qnx6/x86
QNX_TARGET ?= /usr/qnx650/target/qnx6
CC ?= $(QNX_HOST)/usr/bin/ntoarmv7-gcc
STATIC_STDCXX ?= $(QNX_TARGET)/armle-v7/lib/gcc/4.4.2/libstdc++.a

SOURCES = \
	src/main_v2.cpp \
	src/v2_options.cpp \
	src/v2_runtime.cpp \
	src/mmi_capture_source.cpp \
	src/cluster_layout_state.cpp \
	src/base_video_layout_controller.cpp \
	src/cluster_video_display.cpp \
	src/mhi2q_backend.cpp \
	src/gl_renderer.cpp

CXXFLAGS += -O2 -Wall -Wextra -fno-exceptions -fno-rtti
LDFLAGS += -lEGL -lGLESv2 -lm

.PHONY: all clean
all: $(TARGET)
$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)
$(TARGET): $(SOURCES) | $(BUILD_DIR)
	@test -f "$(STATIC_STDCXX)" || { echo "ERROR: static QNX ARMv7 libstdc++ not found: $(STATIC_STDCXX)"; exit 1; }
	QNX_HOST="$(QNX_HOST)" QNX_TARGET="$(QNX_TARGET)" "$(CC)" $(CXXFLAGS) -Isrc $(SOURCES) -o "$@" "$(STATIC_STDCXX)" $(LDFLAGS)
	@echo "Built: $@"
clean:
	rm -rf $(BUILD_DIR)
