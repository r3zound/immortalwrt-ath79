#!/bin/bash
# ============================================================================
# device-add.sh — 给 immortalwrt 源码添加 zbt_we826-q 设备支持
# 在 clone 源码后、make 前执行。
# 用法：在 immortalwrt 源码根目录执行：bash ../device-add.sh
# ============================================================================
set -e

HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="${1:-.}"

echo "[1/4] 复制 dts"
cp "$HERE/qca9531_zbt_we826-q.dts" "$SRC/target/linux/ath79/dts/"

echo "[2/4] 追加 generic.mk Device 段"
cat >> "$SRC/target/linux/ath79/image/generic.mk" <<'EOF'

define Device/zbt_we826-q
  $(Device/tplink-16mlzma)
  SOC := qca9531
  DEVICE_VENDOR := ZBT
  DEVICE_MODEL := WE826-Q
  IMAGE_SIZE := 16000k
  DEVICE_PACKAGES := kmod-usb2
  SUPPORTED_DEVICES += zbt-we826q
endef
TARGET_DEVICES += zbt_we826-q
EOF

echo "[3/4] 追加 02_network 分支"
# 在 ath79_setup_interfaces() 函数里、最后一个 case 的 ;; 之前插入。
# 用一个锚点：找 "zbtlink,zbt-wd323)" 或直接追加到文件尾部一个新函数前不合适，
# 这里用 sed 在 "glinet,gl-x300b)" 分支前插入（字母序接近）。
NET="$SRC/target/linux/ath79/generic/base-files/etc/board.d/02_network"
grep -q "zbt,we826-q)" "$NET" || {
  python3 - "$NET" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p).read()
anchor = "glinet,gl-x300b)"
add = '''\tzbt,we826-q)
\t\tucidef_set_interface_wan "eth1"
\t\tucidef_add_switch "switch0" \\
\t\t\t"0@eth0" "1:lan"
\t\t;;
'''
if anchor in s and "zbt,we826-q)" not in s:
    s = s.replace(anchor, add + anchor, 1)
    open(p, "w").write(s)
    print("inserted 02_network")
else:
    print("02_network: anchor not found or already present")
PYEOF
}

echo "[4/4] 追加 01_leds 分支"
LEDS="$SRC/target/linux/ath79/generic/base-files/etc/board.d/01_leds"
grep -q "zbt,we826-q)" "$LEDS" || {
  python3 - "$LEDS" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p).read()
anchor = "glinet,gl-x300b)"
add = '''\tzbt,we826-q)
\t\tucidef_set_led_switch "lan" "LAN" "blue:lan1" "switch0" "0x02"
\t\tucidef_set_led_netdev "wan" "WAN" "blue:wan" "eth1"
\t\tucidef_set_led_wlan "wlan" "WLAN" "blue:wifi" "phy0tpt"
\t\t;;
'''
if anchor in s and "zbt,we826-q)" not in s:
    s = s.replace(anchor, add + anchor, 1)
    open(p, "w").write(s)
    print("inserted 01_leds")
else:
    print("01_leds: anchor not found or already present")
PYEOF
}

echo "device-add.sh done"
