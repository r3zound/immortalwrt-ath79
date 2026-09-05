#!/bin/bash
# ============================================================================
# vendor-script.sh — 在 WS 原地 vendor（clone 到 STAGE，rsync 回 WS）
# 内联在 .github/workflows/vendor.yml 用
# ============================================================================
set -x

cd "$GITHUB_WORKSPACE"
WS="$GITHUB_WORKSPACE"
echo "WS=$WS"

STAGE="/tmp/el953_stage"
rm -rf "$STAGE"
mkdir -p "$STAGE"

# 1. clone 6 仓库到 STAGE（不指定 -b，避免 Y0518 default=master 报 -b 错）
clone_one() {
  local url=$1 ref=$2 name=$3
  echo ">>> clone $name @ $ref"
  git clone "$url" "$STAGE/$name"
  (cd "$STAGE/$name" && git fetch --depth 1 origin "$ref" && git checkout "$ref")
}

clone_one "$MAIN_REPO"  "$MAIN_REF"  "immortalwrt"
clone_one "$PKG_REPO"   "$PKG_REF"   "packages"
clone_one "$LUCI_REPO"  "$LUCI_REF"  "luci"
clone_one "$RT_REPO"    "$RT_REF"    "routing"
clone_one "$TEL_REPO"   "$TEL_REF"   "telephony"
clone_one "$MF_REPO"    "$MF_REF"    "modemfeed"

# 2. 平铺主源码到 STAGE（用 find 而不是 dotglob）
echo ">>> flatten main source"
mkdir -p "$STAGE/_root"
(cd "$STAGE/immortalwrt" && find . -mindepth 1 -maxdepth 1 -exec cp -r {} "$STAGE/_root/" \;)
rm -rf "$STAGE/immortalwrt"
mv "$STAGE/_root" "$STAGE/root"

# 3. feeds -> STAGE/root/feeds-src/
mkdir -p "$STAGE/root/feeds-src"
for f in packages luci routing telephony modemfeed; do
  mv "$STAGE/$f" "$STAGE/root/feeds-src/$f"
done

# 4. 写 feeds.conf
cat > "$STAGE/root/feeds.conf" <<'EOF'
src-link packages  feeds-src/packages
src-link luci      feeds-src/luci
src-link routing   feeds-src/routing
src-link telephony feeds-src/telephony
src-link modemfeed feeds-src/modemfeed
EOF

# 5. edgelink 设备支持 baked
echo ">>> edgelink device support"
cp "$WS/patches/qca9531_edgelink_el-953.dts" \
   "$STAGE/root/target/linux/ath79/dts/"

cat >> "$STAGE/root/target/linux/ath79/image/generic.mk" <<'EOF'

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
NET="$STAGE/root/target/linux/ath79/generic/base-files/etc/board.d/02_network"
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
LEDS="$STAGE/root/target/linux/ath79/generic/base-files/etc/board.d/01_leds"
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
UCI="$STAGE/root/target/linux/ath79/generic/base-files/etc/uci-defaults"
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

# 6. 自留文件
echo ">>> copy self-owned files"
cp -f .config       "$STAGE/root/.config"
cp -f .gitignore     "$STAGE/root/.gitignore"
rm -f "$STAGE/root/README.md"
rm -rf "$STAGE/root/.github"
cp -f README.md      "$STAGE/root/README.md"

mkdir -p "$STAGE/root/.github/workflows"
cp -f .github/workflows/vendor.yml        "$STAGE/root/.github/workflows/vendor.yml"
cp -f .github/workflows/vendor-script.sh  "$STAGE/root/.github/workflows/vendor-script.sh"
cp -f .github/workflows/build.yml         "$STAGE/root/.github/workflows/build.yml"

mkdir -p "$STAGE/root/scripts"
cp -f scripts/vendor.sh "$STAGE/root/scripts/vendor.sh"
chmod +x "$STAGE/root/scripts/vendor.sh"

mkdir -p "$STAGE/root/patches"
cp -f patches/qca9531_edgelink_el-953.dts "$STAGE/root/patches/qca9531_edgelink_el-953.dts"
cp -f patches/device-add.sh "$STAGE/root/patches/device-add.sh"

# 7. .gitignore 补全
cat >> "$STAGE/root/.gitignore" <<'EOF'

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

# 8. rsync STAGE/root -> WS（清空除 .git）
echo ">>> rsync stage -> workspace"
rsync -a --delete --exclude='.git' "$STAGE/root/" "$WS/"

# 9. 删除主源码的 .gitignore（它会阻止 feeds/feeds.conf/target/Makefile 被 git add）
echo ">>> remove upstream .gitignore, restore ours"
rm -f "$WS/.gitignore"
cat > "$WS/.gitignore" <<'GITIGNORE_EOF'
# 本地构建产物
immortalwrt-*.zip
immortalwrt-*/
*.zst

# OpenWrt 构建产物（vendor 后由 build.yml 在 Actions 里产生，不入库）
/bin/
/build_dir/
/staging_dir/
/tmp/
/dl/
/logs/
/ccache/
/.config.built
GITIGNORE_EOF


echo ">>> done"
ls -la "$WS" | head -30
echo "=== feeds-src ==="
ls -la "$WS/feeds-src/" 2>/dev/null
du -sh "$WS/feeds-src" 2>/dev/null
