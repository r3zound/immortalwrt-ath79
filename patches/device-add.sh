#!/bin/bash
# ============================================================================
# device-add.sh - add edgelink_el-953 device support to Y0518/immortalwrt source
# Run after cloning source, before make.
# NOTE: modemfeed feed is added by the workflow (with ^commit pin), NOT here,
#       to avoid duplicate feed names breaking ./scripts/feeds update -a.
# Usage: in immortalwrt source root: bash ../device-add.sh
# ============================================================================
set -e

HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="${1:-.}"

echo "[1/4] copy dts"
cp "$HERE/qca9531_edgelink_el-953.dts" "$SRC/target/linux/ath79/dts/"

echo "[2/4] append generic.mk Device block"
cat >> "$SRC/target/linux/ath79/image/generic.mk" <<'EOF'

define Device/edgelink_el-953
  $(Device/tplink-16mlzma)
  SOC := qca9531
  DEVICE_VENDOR := EdgeLink
  DEVICE_MODEL := EL-953
  IMAGE_SIZE := 16000k
  DEVICE_PACKAGES := kmod-usb2
  SUPPORTED_DEVICES += edgelink-el-953
endef
TARGET_DEVICES += edgelink_el-953
EOF

echo "[3/4] append 02_network case"
NET="$SRC/target/linux/ath79/generic/base-files/etc/board.d/02_network"
if ! grep -q "edgelink,el-953)" "$NET"; then
  python3 - "$NET" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p).read()
anchor = "glinet,gl-x300b)"
add = '''\tedgelink,el-953)
\t\tucidef_set_interface_wan "usb0"
\t\tucidef_add_switch "switch0" \\
\t\t\t"0@eth0" "1:lan"
\t\t;;
'''
if anchor in s and "edgelink,el-953)" not in s:
    s = s.replace(anchor, add + anchor, 1)
    open(p, "w").write(s)
    print("inserted 02_network")
else:
    print("02_network: anchor not found or already present")
PYEOF
fi

echo "[4/4] append 01_leds case"
LEDS="$SRC/target/linux/ath79/generic/base-files/etc/board.d/01_leds"
if ! grep -q "edgelink,el-953)" "$LEDS"; then
  python3 - "$LEDS" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p).read()
anchor = "glinet,gl-x300b)"
add = '''\tedgelink,el-953)
\t\tucidef_set_led_switch "lan" "LAN" "blue:lan1" "switch0" "0x02"
\t\tucidef_set_led_netdev "wan" "WAN" "blue:wan" "eth1"
\t\tucidef_set_led_wlan "wlan" "WLAN" "blue:wifi" "phy0tpt"
\t\t;;
'''
if anchor in s and "edgelink,el-953)" not in s:
    s = s.replace(anchor, add + anchor, 1)
    open(p, "w").write(s)
    print("inserted 01_leds")
else:
    print("01_leds: anchor not found or already present")
PYEOF
fi

echo "[5/5] add uci-defaults for 4G WAN (usb0 dhcp)"
UCI="$SRC/target/linux/ath79/generic/base-files/etc/uci-defaults"
mkdir -p "$UCI"
cat > "$UCI/99-edgelink-4g" <<'EOF'
#!/bin/sh
# EdgeLink EL-953: default WAN over 4G ECM (usb0 dhcp), drop bogus qmi/ncm
[ -e /etc/config/network ] || exit 0
uci set network.wan.proto='dhcp'
uci set network.wan.device='usb0'
uci -q delete network.wan6
uci -q delete network.wwan
uci commit network
exit 0
EOF
chmod +x "$UCI/99-edgelink-4g"

echo "device-add.sh done"
