# WE826-Q 固件（内置 frpc 插件）云端构建

本仓库提供一条 **GitHub Actions** 流水线，把官方基线 WE826-Q 固件重新封装成
**内置 frpc + LuCI frpc 插件** 的版本，产物可直接用 SSH + `mtd write` 刷机。

## 为什么是"重封装"而不是"从源码编译"

`zbt_we826-q` 这个设备定义**不在**公开的 ImmortalWrt 上游，也不在本仓库的 ath79 目标里：

- 上游 `immortalwrt/immortalwrt` 的 `target/linux/ath79/image/` 只有
  `generic-tp-link.mk` / `generic-ubnt.mk`，全树检索 `we826` 无命中；
- 基线固件内部**没有 DTB**（设备树由原厂 u-boot 提供），内核与分区布局由 u-boot 约定；
- 基线固件里的 `we826q` 板级包（`we826q - 1.000-1`）来自构建者自定义的树。

因此"从源码编译 WE826-Q"在公开环境下无法复现。改 rootfs 再按原厂 ZBT 镜像头重封装，
是既保留原厂标准、又能加插件、且不改变内核/分区布局的做法。

## 流水线

`.github/workflows/build-we826q-frpc.yml`（手动触发 `workflow_dispatch`）：

1. 安装 `squashfs-tools` / `xz-utils` / `python3`；
2. 从 `base_url` 下载基线 `zbt_we826-q` 固件；
3. 从 ImmortalWrt 21.02.7 官方源下载
   `frpc_0.51.2-1_mips_24kc.ipk`、`luci-app-frpc`、`luci-i18n-frpc-zh-cn`；
4. 运行 `scripts/we826q/build_frpc_firmware.py`：
   解出 squashfs → 注入三个包 → 写 `/etc/config/frpc` → 建 `frpc` 系统账号 →
   建 `/etc/rc.d/S99frpc` 自启链接 → `mksquashfs`(xz, 256K 块) →
   改写 512B 头的 `rootfs_size` → 拼回 kernel 区；
5. 校验镜像头、分区预算与 sha256；
6. 上传 artifact（可选创建草稿 Release）。

## 使用

在 Actions 页面点 **Run workflow**，填 `base_url`（基线固件直链）以及 frp 服务端地址/端口/
token。token 留空则固件里不带凭据，刷机后到 **服务 → frpc** 里填。

> 基线固件没有放在本仓库里（二进制不适合进 git），请把它放到任意可直链的位置
> （GitHub Release 资产、对象存储、自己的服务器都行）后把直链填进 `base_url`。

## 刷机（与已验证方式一致）

不要用网页 sysupgrade，也不要碰 u-boot / art 分区：

```bash
scp -O -o BindAddress=<你的LAN IP> immortalwrt-ath79-generic-zbt_we826-q-squashfs-sysupgrade.bin root@192.168.2.1:/tmp/
ssh -o BindAddress=<你的LAN IP> root@192.168.2.1
# 设备上执行
md5sum /tmp/*.bin          # 与产物 .sha256 核对
mtd erase firmware         # 0x20000-0xff0000
mtd write /tmp/immortalwrt-ath79-generic-zbt_we826-q-squashfs-sysupgrade.bin firmware
reboot
```

刷机后自检：

```bash
frpc -v                      # 0.51.2
ls /etc/init.d/frpc /usr/lib/lua/luci/i18n/frpc.zh-cn.lmo
logread -e frpc | tail -20  # 应出现 login to server success
```

LuCI 里 **服务 → frpc** 可改服务端地址、端口、token 与通道；本固件默认已预置
`we826q-luci`(远程 20061 → 本地 192.168.2.1:80) 与
`we826q-ssh`(远程 20062 → 本地 192.168.2.1:22) 两个通道。

## 注意

- 注入 frpc 后 rootfs 增大约 3.6MB，overlay(rootfs_data) 会从约 5.3MB 降到约 1.6MB，
  属于正常现象，仍够放配置与状态文件；脚本每次都会打印分区预算校验。
- WE826-Q 的上网口是 4G(ModemManager PPP)，frpc 依赖 ppp0 出网，
  配置里已设 `login_fail_exit 0`，4G 还没拨通时会持续重试而不是退出。
- 本仓库的 `.config` 保持 **EdgeLink EL-953** 原样，避免影响原有的源码编译流程；
  WE826-Q 固件走上面这条重封装流水线。
