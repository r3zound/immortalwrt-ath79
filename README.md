# ImmortalWrt — EdgeLink EL-953 4G Router (QCA9531) 构建工程

## 背景

**EdgeLink EL-953** 是边缘联网 4G 路由器（品牌 EdgeLink 边联，型号 EL-953），硬件为 QCA9531 + AR8229 switch，16M Flash + 128M RAM，**1WAN+1LAN** + USB + TF + miniPCIe + SIM，4G 模块 **Quectel EC200T**。

OpenWrt 官方与 ImmortalWrt 上游均无本设备定义。**真实编译来源** = 第三方 fork **Y0518/immortalwrt**（`openwrt-21.02` 分支，固定 commit）+ **Y0518/modemfeed**（含 4G 工具链与 vendor 4G 支持包）。

## 仓库结构

```
.config                        # 完整编译配置（来自可用固件的 config.buildinfo）
patches/qca9531_edgelink_el-953.dts   # 设备树
patches/device-add.sh                 # dts + generic.mk + board.d + uci-defaults 自动注入
.github/workflows/build.yml           # GitHub Actions 自动编译
```

## 编译源

- **基础源码**：[Y0518/immortalwrt](https://github.com/Y0518/immortalwrt) `openwrt-21.02` 分支
- **第三方 feed**：[Y0518/modemfeed](https://github.com/Y0518/modemfeed) `609d43d`（提供 `luci-app-modeminfo`、`luci-app-atinout`、`modemmanager` 等 4G 组件）
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

推送到 GitHub → Actions 自动编译（约 1 小时），产物 `immortalwrt-edgelink-el-953`。

刷机走 Breed（先备份编程器固件 full.bin）。

## 4G 说明

- EC200T（CN 固件）USB=`2c7c:6026` **ECM 模式，无 QMI**；模块上电后自动注网并激活 PDP（联通 `3gnet`，电信 `ctnet`，移动 `cmnet` 由模块侧按卡决定），无需 host 侧 APN 脚本。
- 固件默认 **WAN = `usb0` + `dhcp`**（ECM 直连），开机自动拉起；实测外网通（模块内部 NAT 到 PDP）。
- 已内置 `luci-app-modeminfo`（信号/运营商/参数面板）与 `luci-app-atinout`（AT 指令交互）界面。
- 有线 WAN 口（eth1）默认未启用；如需有线接入，在 LuCI 里手动新建接口即可。
