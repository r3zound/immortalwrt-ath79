#!/bin/bash
# ============================================================================
# vendor.sh — 1) clone 6 仓库 2) 平铺主源码+edgelink 改动 3) feeds-src/
# 4) feeds.conf src-link 5) rsync 回 GITHUB_WORKSPACE
# 目标：永不强类型 + 全程 set -x 让 Actions 报行号
# ============================================================================

set -x

cd "$GITHUB_WORKSPACE"
WS="$GITHUB_WORKSPACE"
echo "WS=$WS"

STAGE="/tmp/el953_vendor_stage"
rm -rf "$STAGE"
mkdir -p "$STAGE"

# 1. clone 6 仓库到 STAGE。不指定 -b（避免 Y0518 fork 的 default=master 报 -b 错），
#    而是先拉 default head 再 fetch + checkout 目标 commit。
clone_one() {
  local url=$1 ref=$2 name=$3
  echo ">>> clone $name @ $ref"
  git clone "$url" "$STAGE/$name"
  cd "$STAGE/$name"
  git fetch --depth 1 origin "$ref" || { echo "fetch $ref failed, trying without depth"; git fetch origin "$ref"; }
  git checkout "$ref"
  cd "$WS"
}

clone_one "$MAIN_REPO"  "$MAIN_REF"  "immortalwrt"
clone_one "$PKG_REPO"   "$PKG_REF"   "packages"
clone_one "$LUCI_REPO"  "$LUCI_REF"  "luci"
clone_one "$RT_REPO"    "$RT_REF"    "routing"
clone_one "$TEL_REPO"   "$TEL_REF"   "telephony"
clone_one "$MF_REPO"    "$MF_REF"    "modemfeed"

# 2. 平铺主源码到 STAGE
echo ">>> flatten main source"
# 处理点文件和非点文件
if compgen -G "$STAGE/immortalwrt/.*" > /dev/null; then
  cp -r "$STAGE/immortalwrt/". "$STAGE/" 2>/dev/null || true
fi
cp -r "$STAGE/immortalwrt/." "$STAGE/" 2>/dev/null || true
# cp -r 在 . 当 src 时会递归目录，先用更安全的方式
rm -rf "$STAGE/immortalwrt"

# 3. feeds 移到 STAGE/feeds-src/
mkdir -p "$STAGE/feeds-src"
for f in packages luci routing telephony modemfeed; do
  mv "$STAGE/$f" "$STAGE/feeds-src/$f"
done

# 4. 写 feeds.conf
cat > "$STAGE/feeds.conf" <<'EOF'
src-link packages  feeds-src/packages
src-link luci      feeds-src/luci
src-link routing   feeds-src/routing
src-link telephony feeds-src/telephony
src-link modemfeed feeds-src/modemfeed
EOF

# 5. 应用 edgelink_el-953 设备支持
echo ">>> edgelink device support"
cp "$WS/patches/qca9531_edgelink_el-953.dts" \
   "$STAGE/target/linux/ath79/dts/"

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
if [ -f "$NET" ] && ! grep -q "edgelink,el-953)" "$NET"; then
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
PYEOF
fi

# 6.4 board.d/01_leds
LEDS="$STAGE/target/linux/ath79/generic/base-files/etc/board.d/01_leds"
if [ -f "$LEDS" ] && ! grep -q "edgelink,el-953)" "$LEDS"; then
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

# 6. 拷贝自留文件
echo ">>> copy self-owned files"
cp -f .config       "$STAGE/.config"
cp -f .gitignore     "$STAGE/.gitignore"
# 移除主源码自带的 README/.github 模板
rm -f "$STAGE/README.md"
rm -rf "$STAGE/.github"
cp -f README.md      "$STAGE/README.md"

# 保留我们的 workflow + scripts + patches
mkdir -p "$STAGE/.github/workflows"
cp -f .github/workflows/vendor.yml "$STAGE/.github/workflows/vendor.yml"
cp -f .github/workflows/build.yml  "$STAGE/.github/workflows/build.yml"

mkdir -p "$STAGE/scripts"
cp -f scripts/vendor.sh "$STAGE/scripts/vendor.sh"
chmod +x "$STAGE/scripts/vendor.sh"

mkdir -p "$STAGE/patches"
cp -f patches/qca9531_edgelink_el-953.dts "$STAGE/patches/qca9531_edgelink_el-953.dts"
cp -f patches/device-add.sh "$STAGE/patches/device-add.sh"

# 7. .gitignore 补全
cat >> "$STAGE/.gitignore" <<'EOF'

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

# 8. rsync STAGE -> WS（清空除 .git）
echo ">>> rsync stage -> workspace"
rsync -a --delete --exclude='.git' "$STAGE/" "$WS/"

echo ">>> done"
ls -la "$WS" | head -30
echo "=== feeds-src ==="
ls -la "$WS/feeds-src/" 2>/dev/null
echo "=== top-level files count ==="
find "$WS" -maxdepth 1 -type f | wc -l
echo "=== repo size ==="
du -sh "$WS/feeds-src" 2>/dev/null
