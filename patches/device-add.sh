#!/bin/bash
# ============================================================================
# device-add.sh — 给 Y0518/immortalwrt 源码添加 zbt_we826-q 设备支持
# 在 clone 源码后、make 前执行。依赖 Y0518/modemfeed feed（脚本会自动加）。
# 用法：在 immortalwrt 源码根目录执行：bash ../device-add.sh
# ============================================================================
set -e

HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="${1:-.}"

echo "[0/5] 加 Y0518/modemfeed feed（含 we826q 私有包 + luci-app-mmconfig + qfirehose + wwan）"
F="$SRC/feeds.conf.default"
grep -q "koshev-msk\|Y0518/modemfeed" "$F" || \
  echo 'src-git modemfeed https://github.com/Y0518/modemfeed.git' >> "$F"

echo "[1/5] 复制 dts"
cp "$HERE/qca9531_zbt_we826-q.dts" "$SRC/target/linux/ath79/dts/"

echo "[2/5] 追加 generic.mk Device 段"
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

echo "[3/5] 追加 02_network 分支"
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

echo "[4/5] 追加 01_leds 分支"
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

echo "[5/5] 默认选中 we826q 包（如果存在）"
[ -d "$SRC/package/feeds/modemfeed/we826q" ] && \
  echo 'CONFIG_PACKAGE_we826q=y' >> "$SRC/.config"

echo "device-add.sh done"
