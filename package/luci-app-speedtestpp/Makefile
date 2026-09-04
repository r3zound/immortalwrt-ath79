# ============================================================================
# luci-app-speedtestpp — 调用系统 speedtestpp 命令行，在 LuCI 显示测速结果
# 自写自包含包（方案 A），不依赖外部 luci feed
# 依赖: speedtestpp（modemfeed 提供）+ libcurl/libxml2/libopenssl/libstdcpp
# ============================================================================

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-speedtestpp
PKG_VERSION:=1.0
PKG_RELEASE:=1

LUCI_TITLE:=Speedtest (speedtestpp) Web UI
LUCI_DEPENDS:=+speedtestpp +luci-base
LUCI_PKGARCH:=all
LUCI_DESCRIPTION:=Run speedtestpp CLI from LuCI and show download/upload/ping results.

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
