# ImmortalWrt — EdgeLink EL-953 4G Router (QCA9531) 自包含构建工程

## 背景

**EdgeLink EL-953** 是边缘联网 4G 路由器（品牌 EdgeLink 边联，型号 EL-953），硬件为 QCA9531 + AR8229 switch，16M Flash + 128M RAM，**1WAN+1LAN** + USB + TF + miniPCIe + SIM，4G 模块 **Quectel EC200T**。

**本仓库已完全自包含**：主源码（Y0518/immortalwrt fork）+ 5 个 feeds（packages/luci/routing/telephony + Y0518/modemfeed）已 vendor 进仓库，build.yml 不再 clone 任何外部仓库，feeds 用 `src-link` 本地引用。

## 仓库结构（vendor 后）

```
<仓库根>
├── Makefile, scripts/, target/, package/        ← immortalwrt 主源码（vendor 平铺）
├── feeds-src/                                   ← 5 个 feed 本地副本
│   ├── packages/  luci/  routing/  telephony/  modemfeed/
├── feeds.conf                                   ← src-link feeds-src/*（本地引用）
├── .config                                      ← 构建配置
├── .github/workflows/
│   ├── build.yml                                 ← 构建固件（不动外部）
│   └── vendor.yml                                ← 一键重新 vendor（首次或升级时）
├── patches/                                     ← 设备 dts（vendor 阶段 baked 进源码）
└── README.md
```

## vendor 版本锁定

| 源 | commit | 用途 |
|---|---|---|
| Y0518/immortalwrt | `0f93ee65` | 主源码 |
| immortalwrt/packages | `e09f3c7d` | luci/argon/frpc/... |
| immortalwrt/luci | `5829eabb` | LuCI 框架 |
| openwrt/routing | `a9e43101` | mwan3 / relayd |
| openwrt/telephony | `920fbc5c` | asterisk 等 |
| Y0518/modemfeed | `609d43d` | luci-app-modeminfo/atinout/mmconfig/qtools |

## 使用

### 重新 vendor（首次或升级依赖时）

1. GitHub 网页 → **Actions** → **Vendor (cloud)** → **Run workflow** → Run
2. 等几分钟，workflow 会自动 clone 6 仓库、合并、应用 edgelink 改动、commit & push 到 main

### 构建 V4 固件

1. **Actions** → **Build ImmortalWrt (EdgeLink EL-953)** → **Run workflow** → Run
2. 约 1 小时，产物 `immortalwrt-edgelink-el-953` 自动上传
3. 解压取 `*-edgelink_el-953-squashfs-sysupgrade.bin`，通过 Breed 刷入

## 4G 说明

- EC200T（CN 固件）USB=`2c7c:6026` **ECM 模式，无 QMI**；模块上电后自动注网并激活 PDP（联通 `3gnet`，电信 `ctnet`，移动 `cmnet` 由模块侧按卡决定）。
- 固件默认 **WAN = `usb0` + `static(192.168.43.100, gw .1, metric 10)`**（dhcp 不可靠，模块不下发租约），开机自动拉起；dnsmasq 静态上游 DNS `223.5.5.5/119.29.29.29`。
- 已内置 `luci-app-modeminfo`（信号/运营商/参数面板）与 `luci-app-atinout`（AT 指令交互）界面。
- 有线 WAN 口（eth1）默认未启用；如需有线接入，在 LuCI 里手动新建接口即可。

## 设备身份

- 对外：**EdgeLink EL-953 4G Router**（品牌 EdgeLink 边联，型号 EL-953）
- 板型定义：`Device/edgelink_el-953`（`target/linux/ath79/image/generic.mk`）
- DTS：`target/linux/ath79/dts/qca9531_edgelink_el-953.dts`
- 编译产物的 board 名称：`edgelink,el-953`（LuCI/SSH/日志均显示此身份）

## 硬件逆向结果

| 项 | 值 |
|---|---|
| SoC | QCA9531（内核识别 QCA9533） |
| 分区 | u-boot(0x0,128K) + firmware(0x20000, tplink LZMA) + art(0xff0000,64K) |
| 网口 | eth0=GMII+AR8229 switch(1×LAN port1), eth1=MII+phy4(1×WAN) |
| LED(blue,低有效) | wifi=gpio12, wan=gpio4, lan=gpio16 |
| Reset | gpio17 |
| MAC | art 0x0 = c8:ee:a6:bb:cc:23(WAN) / :24(LAN) |
| 4G | Quectel EC200T (2c7c:6026, ECM)；4G 供电 GPIO2 (高) |

## 刷机

通过 Breed（已备份编程器固件 full.bin）：
1. 拔电 → 按住 Reset → 上电 → 浏览器进 192.168.1.1
2. 选 `*-edgelink_el-953-squashfs-sysupgrade.bin` 刷入
3. 出问题回滚：Breed 恢复 full.bin 即可
