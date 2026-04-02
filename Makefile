# Makefile for xiaomi_kbd_daemon
# Cross-compile for Android arm64-v8a using NDK clang

# --- NDK Configuration ---
# Set NDK_HOME to your NDK installation path, e.g.:
#   export NDK_HOME=~/android-ndk-r27c
NDK_HOME ?= $(HOME)/android-ndk-r27c
NDK_TOOLCHAIN = $(NDK_HOME)/toolchains/llvm/prebuilt/linux-x86_64
API_LEVEL = 30

CC = $(NDK_TOOLCHAIN)/bin/aarch64-linux-android$(API_LEVEL)-clang
STRIP = $(NDK_TOOLCHAIN)/bin/llvm-strip

# --- Build flags ---
CFLAGS = -Wall -Wextra -Werror -O2 -DNDEBUG
# Static link so we have zero runtime dependencies on the device
LDFLAGS = -static -pthread

TARGET = xiaomi_kbd_daemon
SRC = xiaomi_kbd_daemon.c

.PHONY: all clean push install

all: $(TARGET)

$(TARGET): $(SRC)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $<
	$(STRIP) $@
	@echo "Built: $@ ($(shell file $@ | grep -o 'ARM aarch64' || echo 'check arch'))"
	@ls -lh $@

clean:
	rm -f $(TARGET)

# Push binary + service script to device via adb
push: $(TARGET)
	adb push $(TARGET) /data/local/tmp/
	adb push magisk/service.d/xiaomi_kbd_service.sh /data/local/tmp/
	@echo "Files pushed. Run 'make install' to install to Magisk service.d"

install: push
	adb shell "su -c 'cp /data/local/tmp/$(TARGET) /data/adb/service.d/$(TARGET)'"
	adb shell "su -c 'cp /data/local/tmp/xiaomi_kbd_service.sh /data/adb/service.d/'"
	adb shell "su -c 'chmod 755 /data/adb/service.d/$(TARGET)'"
	adb shell "su -c 'chmod 755 /data/adb/service.d/xiaomi_kbd_service.sh'"
	@echo "Installed. Reboot device or run the service script manually."

# Quick test: run daemon in foreground on device
test: push
	adb shell "su -c '/data/local/tmp/$(TARGET) -f'"
