#!/system/bin/sh
# Magisk post-fs-data script: place the keyboard IDC early (before the input
# device is created at boot) so arrow-key orientation and external-device flags
# are applied from the first add. Install to /data/adb/post-fs-data.d/.
mkdir -p /data/system/devices/idc
cat > /data/system/devices/idc/Vendor_15d9_Product_00a3.idc << 'IDC'
keyboard.orientationAware = 0
keyboard.builtIn = 0
device.internal = 0
IDC
chmod 644 /data/system/devices/idc/Vendor_15d9_Product_00a3.idc
