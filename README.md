# ImmortalWrt — EdgeLink EL-953 4G Router (QCA9531) Self-contained Build

## Hardware

| Category | Item | Value |
|---|---|---|
| Form | Device type | **Industrial 4G module** (not a consumer router) |
| SoC | Chip / kernel name | QCA9531 (kernel reports QCA9533) |
| Memory | Flash / RAM | 16 MB SPI NOR / 128 MB DDR2 |
| Network | Wired | 1WAN (eth1, MII + phy4) + 1LAN (eth0, GMII + AR8229 switch) |
| Cellular | 4G module / USB ID | Quectel EC200T (CN firmware) — USB `2c7c:6026` (CDC-ECM) |
| SIM | Slot | 1x standard SIM (inserted = LED off / ejected = LED blink) |
| Expansion | USB / TF / miniPCIe | **None** (not wired on PCB) |
| Wireless | WiFi | 2.4 GHz b/g/n (ath9k-phy0) |
| Boot | Bootloader | Breed (full.bin programmer backup saved) |
| Flash | u-boot / firmware / art | 0x000000 (128K) / 0x020000 (tplink LZMA) / 0xff0000 (64K) |
| MAC | art 0x0 | WAN `c8:ee:a6:bb:cc:23` / LAN `:24` / WiFi `c2:ee:a6:0c:38:07` |
| Reset | Button | GPIO 17 (ACTIVE LOW, 60ms debounce) |
| LEDs (4 controllable, ACTIVE LOW) | yellow LAN link = gpio4 · green 4G status = gpio15 · yellow SIM status = gpio14 · red WiFi status = gpio12 · blue power = hardware-driven, not controllable |

## Build System Versions

| Component | Source / Version | Commit / Note |
|---|---|---|
| OpenWrt base | Y0518/immortalwrt | `0f93ee65` (openwrt-21.02 branch) |
| Kernel | Linux | 5.4.266 |
| Userland | OpenWrt | 21.02-SNAPSHOT |
| Target | ath79 / generic | `ath79_generic_DEVICE_edgelink_el-953` |
| LuCI | immortalwrt/luci | `5829eabb` (openwrt-21.02) |
| Packages | immortalwrt/packages | `e09f3c7d` (openwrt-21.02) |
| Routing | openwrt/routing | `a9e43101` (openwrt-21.02) |
| Telephony | openwrt/telephony | `920fbc5c` (openwrt-21.02) |
| 4G extras | Y0518/modemfeed | `609d43d` (modeminfo/atinout/qtools/mmconfig/frpc/speedtestpp) |
| Board name (runtime) | OpenWrt board | `edgelink,el-953` (exposed as "EdgeLink EL-953 4G Router") |

## Repository Layout (after vendor)

```
<root>
├── Makefile, scripts/, target/, package/        <- immortalwrt main source (flattened by vendor)
├── feeds-src/                                   <- 5 feeds as local copies
│   ├── packages/  luci/  routing/  telephony/  modemfeed/
├── feeds.conf                                   <- src-link feeds-src/* (local reference)
├── .config                                      <- build config (incl. speedtestpp + luci-app-speedtestpp)
├── .github/workflows/
│   ├── build.yml                                <- build firmware (no network calls)
│   └── vendor.yml                               <- one-click re-vendor
├── patches/                                     <- device dts (baked into source by vendor)
└── README.md
```

**Fully self-contained**: CI never clones any external repository; feeds are referenced via `src-link`.

## Usage

### Re-vendor (first time or upgrading dependencies)

1. GitHub web -> **Actions** -> **Vendor (cloud)** -> **Run workflow** -> Run
2. The workflow clones 6 repos -> merges -> applies edgelink changes -> commits & pushes to main
3. To bump versions, edit the commit constants at the top of `.github/workflows/vendor.yml` and re-run

### Build V4 firmware

1. **Actions** -> **Build EdgeLink EL-953** -> **Run workflow** -> Run
2. About 1 hour; artifact `immortalwrt-edgelink-el-953` is uploaded automatically
3. Extract `*-edgelink_el-953-squashfs-sysupgrade.bin` and flash via Breed

## 4G Notes

- **Module**: EC200T (CN firmware) USB=`2c7c:6026` **ECM routed mode** (no QMI). The module auto-registers and activates PDP on power-up (China Unicom `3gnet`, China Telecom `ctnet`, China Mobile `cmnet` decided by module/SIM).
- **Network attach**: Default WAN is `usb0` with `static(192.168.43.100, gw .1, metric 10)` (dhcp is unreliable since module does not lease); dnsmasq uses static upstream DNS `223.5.5.5 / 119.29.29.29`. Wired WAN (eth1) is disabled by default; create a new interface in LuCI to use it.
- **Pre-installed packages**:
  - `luci-app-modeminfo` (signal / carrier / parameters panel)
  - `luci-app-atinout` (AT command tool)
  - `luci-app-mmconfig` (band lock)
  - `qtools` / `modeminfo` with Quectel submodule
  - `luci-app-frpc` (server info **left blank**; plugin installed, not pre-configured)
  - `luci-app-speedtestpp` (self-written; runs `speedtestpp` CLI for speedtest.net)

## Device Identity

- **Public**: EdgeLink EL-953 4G Router (brand EdgeLink, model EL-953)
- **Board definition**: `Device/edgelink_el-953` in `target/linux/ath79/image/generic.mk`
- **DTS**: `target/linux/ath79/dts/qca9531_edgelink_el-953.dts`
- **Compiled board name**: `edgelink,el-953` (shown in LuCI / SSH / logs)

## Flashing

Via Breed (full.bin programmer backup already saved):
1. Power off -> hold Reset -> power on -> browse 192.168.1.1
2. Choose `*-edgelink_el-953-squashfs-sysupgrade.bin` and flash
3. Rollback if needed: restore full.bin from Breed
