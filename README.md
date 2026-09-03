# ImmortalWrt — ZBT WE826-Q (QCA9531 4G CPE) 构建工程

## 背景

设备是 **ZBT WE826-Q**（QCA9531 + AR8229 switch，16M Flash + 128M RAM，**1WAN+1LAN** +USB+TF+miniPCIe+SIM，实物为 1WAN+1LAN 变体），4G 模块 **Quectel EC200T**。

官方 ImmortalWrt / OpenWrt 都**没有 `zbt_we826-q` 设备**（同门的 `zbtlink_zbt-wd323` 是 ar9344，硬件不匹配）。本工程基于从设备 `/sys/firmware/fdt` 提取的真实 DTB 逆向移植该设备支持。

## 仓库结构

```
.config                    # 完整编译配置（来自能用的 r20074 固件 config.buildinfo）
patches/qca9531_zbt_we826-q.dts   # 设备树（逆向自真实 DTB）
patches/device-add.sh             # 把 dts + generic.mk + board.d 应用进源码
.github/workflows/build.yml       # GitHub Actions 自动编译
```

## 硬件逆向结果（权威）

| 项 | 值 |
|---|---|
| SoC | QCA9531（内核识别 QCA9533） |
| 分区 | u-boot(0x0,128K) + firmware(0x20000, tplink LZMA) + art(0xff0000,64K) |
| 网口 | eth0=GMII+AR8229 switch(1×LAN, port1), eth1=MII+phy4(1×WAN) |
| LED(blue,低有效) | wifi=gpio12, wan=gpio4, lan1=16, lan2=15, lan3=14, lan4=11 |
| Reset | gpio17 |
| MAC | art 0x0 = c8:ee:a6:bb:cc:23(WAN) / :24(LAN) |

## 编译

推送到 GitHub → Actions 自动编译（约 1-2 小时），产物 `immortalwrt-zbt-we826-q`。

刷机走 Breed（先备份编程器固件 full.bin）。

## 4G 注意事项

EC200T（CN 固件）USB=6026 ECM 模式，**无 QMI**，出厂 tether APN=ctnet（电信）。联通卡数据面拨不通（疑模块绑电信），换能 auto-tether 的卡（如电信）即用。固件已内置 modemmanager/modeminfo/atinout/cdc_ether 全套 4G 支持。
