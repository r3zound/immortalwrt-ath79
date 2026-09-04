#!/bin/bash
# ============================================================================
# vendor.sh — 在 GitHub Actions 里把主源码 + 5 feeds 全 vendor 进仓库根
# 策略：在临时目录里组装完整"主源码+edgelink 改动+自留文件"，
#      再 rsync 到工作区，安全不破坏 runner checkout。
# ============================================================================
set -euo pipefail

cd "$GITHUB_WORKSPACE"
WS="$GITHUB_WORKSPACE"

# 1. 准备 stage 目录（全新）
STAGE=$(mktemp -d -t el953_vendor_XXXXXX)
echo ">>> stage dir: $STAGE"
trap "rm -rf $STAGE" EXIT

# 2. clone 6 个仓库到 stage
clone_one() {
  local url=$1 ref=$2 name=$3
  echo ">>> clone $name @ $ref"
  git clone --filter=blob:none --no-tags --depth 1 "$url" "$STAGE/$name"
  (cd "$STAGE/$name" && git fetch --depth 1 origin "$ref" && git checkout "$ref")
}

clone_one "$MAIN_REPO"  "$MAIN_REF"  "immortalwrt"
clone_one "$PKG_REPO"   "$PKG_REF"   "packages"
clone_one "$LUCI_REPO"  "$LUCI_REF"  "luci"
clone_one "$RT_REPO"    "$RT_REF"    "routing"
clone_one "$TEL_REPO"   "$TEL_REF"   "telephony"
clone_one "$MF_REPO"    "$MF_REF"    "modemfeed"

# 3. 平铺主源码到 stage
shopt -s dotglob
echo ">>> flatten main source into stage"
mv "$STAGE/immortalwrt"/* "$STAGE/immortalwrt"/.[!.]* "$STAGE/" 2>/dev/null || true
rmdir "$STAGE/immortalwrt"
shopt -u dotglob

# 4. 5 个 feed 放到 stage/feeds-src/
mkdir -p "$STAGE/feeds-src"
for f in packages luci routing telephony modemfeed; do
  mv "$STAGE/$f" "$STAGE/feeds-src/$f"
done

# 5. 写 feeds.conf
cat > "$STAGE/feeds.conf" <<'EOF'
src-link packages  feeds-src/packages
src-link luci      feeds-src/luci
src-link routing   feeds-src/routing
src-link telephony feeds-src/telephony
src-link modemfeed feeds-src/modemfeed
EOF

# 6. 应用 edgelink_el-953 设备支持
echo ">>> apply edgelink_el-953 device support"
# 6.1 dts（从仓库自带的 patches/ 复制）
cp "$WS/patches/qca9531_edgelink_el-953.dts" \
   "$STAGE/target/linux/ath79/dts/"

# 6.2 generic.mk
cat >> "$STAGE/target/linux/ath79/image/generic.mk" <<'EOF'

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

# 6.3 board.d/02_network
NET="$STAGE/target/linux/ath79/generic/base-files/etc/board.d/02_network"
if [[ -f "$NET" ]] && ! grep -q "edgelink,el-953)" "$NET"; then
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
    print("02_network: anchor missing or already inserted")
PYEOF
fi

# 6.4 board.d/01_leds
LEDS="$STAGE/target/linux/ath79/generic/base-files/etc/board.d/01_leds"
if [[ -f "$LEDS" ]] && ! grep -q "edgelink,el-953)" "$LEDS"; then
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
    print("01_leds: anchor missing or already inserted")
PYEOF
fi

# 6.5 uci-defaults
UCI="$STAGE/target/linux/ath79/generic/base-files/etc/uci-defaults"
mkdir -p "$UCI"
cat > "$UCI/99-edgelink-4g" <<'EOF'
#!/bin/sh
# EdgeLink EL-953: default WAN over 4G ECM (usb0 static), drop bogus qmi/ncm
[ -e /etc/config/network ] || exit 0
uci set network.wan.proto='static'
uci set network.wan.device='usb0'
uci set network.wan.ipaddr='192.168.43.100'
uci set network.wan.netmask='255.255.255.0'
uci set network.wan.gateway='192.168.43.1'
uci set network.wan.metric='10'
uci -q delete network.wan6
uci -q delete network.wwan
uci commit network
# Static upstream DNS (ECM module does not provide DNS)
uci -q delete dhcp.@dnsmasq[0].server
uci add_list dhcp.@dnsmasq[0].server='223.5.5.5'
uci add_list dhcp.@dnsmasq[0].server='119.29.29.29'
uci commit dhcp
# frpc: 服务器信息留空（删掉默认占位）
if [ -f /etc/config/frpc ]; then
  while uci -q delete frpc.@conf[0]; do :; done
  uci commit frpc
fi
exit 0
EOF
chmod +x "$UCI/99-edgelink-4g"

# 7. 把仓库自带的"自留文件"复制到 stage（不覆盖已 baked 的）
echo ">>> copy self-owned files onto stage"
cp -f .config       "$STAGE/.config"
cp -f .gitignore     "$STAGE/.gitignore"
# 重要：先删 stage 中可能存在的同名（清掉主源码自带的 README/old）
rm -f "$STAGE/README.md"  # 主源码也有 README，写入新版本
cp -f README.md      "$STAGE/README.md"

# .github/workflows：保留 vendor.yml + build.yml，删主源码里的
mkdir -p "$STAGE/.github/workflows"
cp -f .github/workflows/vendor.yml "$STAGE/.github/workflows/vendor.yml"
cp -f .github/workflows/build.yml  "$STAGE/.github/workflows/build.yml"

# scripts/：保留我们自己的 vendor.sh
mkdir -p "$STAGE/scripts"
cp -f scripts/vendor.sh "$STAGE/scripts/vendor.sh"
chmod +x "$STAGE/scripts/vendor.sh"

# patches/：保留我们自己的 dts
mkdir -p "$STAGE/patches"
cp -f patches/qca9531_edgelink_el-953.dts "$STAGE/patches/qca9531_edgelink_el-953.dts"
cp -f patches/device-add.sh "$STAGE/patches/device-add.sh"

# 8. 把 stage 整个 rsync 进工作区（stage 已含全部 vendor 后产物）
echo ">>> rsync stage -> workspace"
shopt -s dotglob
# 清空工作区除了 .git 和 vendor.yml 自身
# 用 rsync --delete，但保留 .git
rsync -a --delete --exclude='.git' --exclude='.git/' "$STAGE/" "$WS/"
shopt -u dotglob

# 9. .gitignore：补全
cat >> "$WS/.gitignore" <<'EOF'

# OpenWrt build outputs
/bin/
/build_dir/
/staging_dir/
/tmp/
/dl/
/logs/
/ccache/
/.config.built
EOF

echo ">>> vendor done"
ls -la | head -20
du -sh feeds-src
