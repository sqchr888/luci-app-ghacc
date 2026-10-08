# OpenWrt package Makefile for luci-app-ghacc
#
# 两种构建方式：
#
#   1) 本机直出（推荐，无需 SDK / 交叉编译）
#        sh build_ipk.sh
#        → dist/ghacc_<版本>_all.ipk
#
#   2) OpenWrt SDK / 构建系统
#        把仓库根目录软链到 package/luci-app-ghacc，然后：
#        make package/luci-app-ghacc/compile V=s
#
# 说明：本包是纯 shell + Lua，`Architecture: all`，不含预编译二进制，
# 因此任何架构通用，也不需要 toolchain。
#
# 目录约定：pkg/root/ 下已经是**按目标根文件系统布局**的完整文件树，
# 安装阶段直接拷贝即可（与 build_ipk.sh 保持同一份来源，避免两边不一致）。

include $(TOPDIR)/rules.mk

PKG_NAME:=ghacc
PKG_VERSION:=2.4.5
PKG_RELEASE:=1
PKG_LICENSE:=MIT
PKG_MAINTAINER:=sqchr888 <sqchr888@users.noreply.github.com>
PKGARCH:=all

include $(INCLUDE_DIR)/package.mk

define Package/ghacc
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=Web Servers/Proxies
  TITLE:=GitHub Accelerator Daemon (with LuCI)
  URL:=https://github.com/sqchr888/luci-app-ghacc
  DEPENDS:=+curl +ca-certificates
  PKGARCH:=all
endef

define Package/ghacc/description
  常驻守护进程：持续探测 GitHub 各域名的可用 IP（TLS 证书校验识别假 IP），
  失效时秒级热切换并 SIGHUP 热加载 dnsmasq，使整个局域网无需安装客户端即可
  访问 GitHub。写入 tmpfs 不磨损闪存。含 LuCI 管理界面与一键卸载。
  纯 shell + Lua 实现，Architecture: all，适用于任意架构。
endef

define Build/Compile
	# 纯脚本包，无需编译
endef

# pkg/root/ 已是完整的根文件系统布局，逐个安装以保留各自的权限位。
define Package/ghacc/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN)  ./pkg/root/usr/bin/ghacc-daemon     $(1)/usr/bin/ghacc-daemon
	$(INSTALL_BIN)  ./pkg/root/usr/bin/ghacc-uninstall  $(1)/usr/bin/ghacc-uninstall

	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN)  ./pkg/root/etc/init.d/ghacc         $(1)/etc/init.d/ghacc

	$(INSTALL_DIR) $(1)/etc/ghacc
	$(INSTALL_CONF) ./pkg/root/etc/ghacc/ghacc.conf     $(1)/etc/ghacc/ghacc.conf

	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./pkg/root/etc/config/ghacc         $(1)/etc/config/ghacc

	$(INSTALL_DIR) $(1)/usr/share/rpcd/acl.d
	$(INSTALL_DATA) ./pkg/root/usr/share/rpcd/acl.d/luci-app-ghacc.json \
	                $(1)/usr/share/rpcd/acl.d/luci-app-ghacc.json

	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/controller
	$(INSTALL_DATA) ./pkg/root/usr/lib/lua/luci/controller/ghacc.lua \
	                $(1)/usr/lib/lua/luci/controller/ghacc.lua

	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/model/cbi
	$(INSTALL_DATA) ./pkg/root/usr/lib/lua/luci/model/cbi/ghacc.lua \
	                $(1)/usr/lib/lua/luci/model/cbi/ghacc.lua

	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/view/ghacc
	$(INSTALL_DATA) ./pkg/root/usr/lib/lua/luci/view/ghacc/status.htm \
	                $(1)/usr/lib/lua/luci/view/ghacc/status.htm
	$(INSTALL_DATA) ./pkg/root/usr/lib/lua/luci/view/ghacc/cbi_style.htm \
	                $(1)/usr/lib/lua/luci/view/ghacc/cbi_style.htm
endef

define Package/ghacc/conffiles
/etc/config/ghacc
/etc/ghacc/ghacc.conf
endef

# 注意：opkg 升级顺序是「旧 prerm upgrade → 解包 → 旧 postrm → 新 postinst」。
# 若 prerm 在升级时执行 disable，而失败发生在 postrm，会留下
# 「服务已停 + 已禁用 + hosts 块已摘」的半安装态。故升级时只 stop 不 disable。
# （用 ipk 安装时以 pkg/control/prerm 为准，此段供 SDK 构建使用。）
define Package/ghacc/prerm
#!/bin/sh
if [ "$${1}" = "upgrade" ]; then
	/etc/init.d/ghacc stop >/dev/null 2>&1
else
	/etc/init.d/ghacc stop >/dev/null 2>&1
	/etc/init.d/ghacc disable >/dev/null 2>&1
fi
exit 0
endef

define Package/ghacc/postinst
#!/bin/sh
chmod +x /usr/bin/ghacc-daemon /etc/init.d/ghacc 2>/dev/null
mkdir -p /etc/ghacc 2>/dev/null
/etc/init.d/ghacc enable >/dev/null 2>&1
/etc/init.d/ghacc start >/dev/null 2>&1
/etc/init.d/rpcd restart >/dev/null 2>&1
exit 0
endef

$(eval $(call BuildPackage,ghacc))
