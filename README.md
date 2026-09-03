# ImmortalWrt — ZBT WE826-Q (QCA9531 4G CPE) 构建工程

## 背景

设备是 **ZBT WE826-Q**（QCA9531 + AR8229 switch，16M Flash + 128M RAM，**1WAN+1LAN** +USB+TF+miniPCIe+SIM），4G 模块 **Quectel EC200T**。

OpenWrt 官方 + immortalwrt 上游都没有 `zbt_we826-q` 设备。**真实来源** = 第三方 fork **Y0518/immortalwrt**（`openwrt-21.02` 分支，含 r20074-a8bbadefaf commit）+ Y0518/modemfeed（含 vendor 私有 `we826q` 包 + 完整 4G 工具链）。

## 仓库结构

```
.config                       # 完整编译配置（来自能用的 r20074 固件 config.buildinfo）
patches/qca9531_zbt_we826-q.dts   # 设备树（逆向自真实 DTB）
patches/device-add.sh             # dts + generic.mk + board.d + feed 自动注入
.github/workflows/build.yml       # GitHub Actions 自动编译
```

## 编译源

- **基础源码**：[Y0518/immortalwrt](https://github.com/Y0518/immortalwrt) `openwrt-21.02` 分支
- **第三方 feed**：[Y0518/modemfeed](https://github.com/Y0518/modemfeed) `609d43d`（含 `we826q` 私有包、`qfirehose` 救砖工具、`luci-app-mmconfig` 4G 配置界面）
- 上游 sources：immortalwrt packages/luci + OpenWrt routing/telephony

## 硬件逆向结果（权威，从设备 DTB 反推）

| 项 | 值 |
|---|---|
| SoC | QCA9531（内核识别 QCA9533） |
| 分区 | u-boot(0x0,128K) + firmware(0x20000, tplink LZMA) + art(0xff0000,64K) |
| 网口 | eth0=GMII+AR8229 switch(1×LAN port1), eth1=MII+phy4(1×WAN) |
| LED(blue,低有效) | wifi=gpio12, wan=gpio4, lan=gpio16 |
| Reset | gpio17 |
| MAC | art 0x0 = c8:ee:a6:bb:cc:23(WAN) / :24(LAN) |

## 编译

推送到 GitHub → Actions 自动编译（约 1 小时），产物 `immortalwrt-zbt-we826-q`。

刷机走 Breed（先备份编程器固件 full.bin）。

## 4G 注意事项

EC200T（CN 固件）USB=6026 ECM 模式，**无 QMI**，出厂 tether APN=ctnet（电信）。联通卡数据面拨不通（疑模块绑电信），换能 auto-tether 的卡（如电信）即用。固件已内置 modemmanager/modeminfo/atinout/cdc_ether 全套 4G 支持（含 vendor 私有 `we826q` 包 + Y0518/modemfeed 完整 4G 工具链）。
