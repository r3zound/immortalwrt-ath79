#!/bin/bash
# ============================================================================
# device-add.sh - add zbt_we826-q device support to Y0518/immortalwrt source
# Run after cloning source, before make.
# NOTE: modemfeed feed is added by the workflow (with ^commit pin), NOT here,
#       to avoid duplicate feed names breaking ./scripts/feeds update -a.
# Usage: in immortalwrt source root: bash ../device-add.sh
# ============================================================================
set -e

HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="${1:-.}"

echo "[1/4] copy dts"
cp "$HERE/qca9531_zbt_we826-q.dts" "$SRC/target/linux/ath79/dts/"

echo "[2/4] append generic.mk Device block"
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

echo "[3/4] append 02_network case"
NET="$SRC/target/linux/ath79/generic/base-files/etc/board.d/02_network"
if ! grep -q "zbt,we826-q)" "$NET"; then
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
fi

echo "[4/4] append 01_leds case"
LEDS="$SRC/target/linux/ath79/generic/base-files/etc/board.d/01_leds"
if ! grep -q "zbt,we826-q)" "$LEDS"; then
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
fi

echo "device-add.sh done"
