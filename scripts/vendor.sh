#!/bin/bash
# ============================================================================
# vendor.sh — 在 GitHub Actions 里把主源码 + 5 feeds 全 vendor 进仓库根
# 产出：仓库根 = immortalwrt 主源码 + feeds-src/<feed>/ + feeds.conf (src-link)
# 之后构建用 src-link 完全本地引用，不再 clone 外部
# ============================================================================
set -euo pipefail
shopt -s dotglob

cd "$GITHUB_WORKSPACE"

# 1. 拉 6 个仓库到临时目录
TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

clone_one() {
  local url=$1 ref=$2 name=$3
  echo ">>> clone $name @ $ref"
  git clone --filter=blob:none --no-tags --depth 1 "$url" "$TMP/$name"
  (cd "$TMP/$name" && git fetch --depth 1 origin "$ref" && git checkout "$ref")
}

clone_one "$MAIN_REPO"  "$MAIN_REF"  "immortalwrt"
clone_one "$PKG_REPO"   "$PKG_REF"   "packages"
clone_one "$LUCI_REPO"  "$LUCI_REF"  "luci"
clone_one "$RT_REPO"    "$RT_REF"    "routing"
clone_one "$TEL_REPO"   "$TEL_REF"   "telephony"
clone_one "$MF_REPO"    "$MF_REF"    "modemfeed"

# 2. 备份仓库自带的关键文件，merge 后还原（避免被主源码同名文件覆盖）
backup() {
  local rel=$1
  if [[ -e "$rel" && ! -L "$rel" ]]; then
    cp -a "$rel" "$TMP/keep_$(echo "$rel" | tr '/' '_')"
  fi
}
for f in .config README.md .github .gitignore scripts; do
  backup "$f"
done

# 3. 把主源码（immortalwrt/）所有内容平铺到仓库根
echo ">>> merge main source into repo root"
shopt -s dotglob
mv "$TMP/immortalwrt/"* "$TMP/immortalwrt/".* . 2>/dev/null || true

# 4. 恢复我们自己的关键文件
restore() {
  local rel=$1
  local bk="$TMP/keep_$(echo "$rel" | tr '/' '_')"
  if [[ -e "$bk" ]]; then
    rm -rf "$rel"
    cp -a "$bk" "$rel"
  fi
}
for f in .config README.md .github .gitignore scripts; do
  restore "$f"
done

# 5. 放 5 个 feed 到 feeds-src/
echo ">>> place feeds under feeds-src/"
mkdir -p feeds-src
for f in packages luci routing telephony modemfeed; do
  rm -rf "feeds-src/$f"
  mv "$TMP/$f" "feeds-src/$f"
done

# 6. 重写 feeds.conf：全部 src-link 到本地
echo ">>> write feeds.conf (src-link)"
cat > feeds.conf <<'EOF'
src-link packages  feeds-src/packages
src-link luci      feeds-src/luci
src-link routing   feeds-src/routing
src-link telephony feeds-src/telephony
src-link modemfeed feeds-src/modemfeed
EOF

# 7. 应用 edgelink_el-953 设备支持（dts + generic.mk + board.d + uci-defaults）
#    这些改动 baked 进源码树，build.yml 不再现场跑 device-add.sh
echo ">>> apply edgelink_el-953 device support"
cp patches/qca9531_edgelink_el-953.dts target/linux/ath79/dts/

cat >> target/linux/ath79/image/generic.mk <<'EOF'

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

NET=target/linux/ath79/generic/base-files/etc/board.d/02_network
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

LEDS=target/linux/ath79/generic/base-files/etc/board.d/01_leds
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

UCI=target/linux/ath79/generic/base-files/etc/uci-defaults
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

# 8. .gitignore：排除运行时产生的大文件
cat >> .gitignore <<'EOF'

# vendored OpenWrt build outputs / caches
bin/
build_dir/
staging_dir/
tmp/
dl/
logs/
ccache/
EOF

echo ">>> vendor done"
ls -la | head -20
du -sh feeds-src
