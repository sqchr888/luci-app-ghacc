#!/bin/sh
# ============================================================
# ghacc-daemon 安装脚本 —— 在路由器上以 root 执行
#   sh /tmp/openwrt-ghacc/install.sh
#
# 已适配：QWRT 25.12.2 / ipq95xx / aarch64_cortex-a53
# 卸载：  sh /tmp/openwrt-ghacc/uninstall.sh    或   ghacc-uninstall
# ============================================================
set -u
SRC=$(dirname "$0")

echo "=========================================="
echo " ghacc-daemon 安装"
echo "=========================================="

# ---- 0. 环境体检 ----
echo
echo "[0/6] 环境体检"
echo "  固件:   $(grep -s DISTRIB_DESCRIPTION /etc/openwrt_release 2>/dev/null | cut -d"'" -f2) $(grep -s DISTRIB_RELEASE /etc/openwrt_release 2>/dev/null | cut -d"'" -f2)"
echo "  架构:   $(uname -m)"
echo "  curl:   $(curl --version 2>/dev/null | head -n 1 | cut -d' ' -f2)"
echo "  dnsmasq: $(ls /etc/init.d/ 2>/dev/null | grep -E '^dnsmasq' | tr '\n' ' ')"

# overlay 剩余空间检查（小于 3M 就警告）
_avail=$(df -k /overlay 2>/dev/null | awk 'NR==2 {print $4}')
if [ -n "${_avail:-}" ] && [ "${_avail}" -lt 3072 ]; then
    echo "  ⚠ overlay 仅剩约 ${_avail}KB，空间紧张（本包只占约 15KB，但请确保有余量）"
else
    echo "  空间:   overlay 可用 ${_avail:-未知}KB"
fi

# ---- 1. 依赖检查 ----
echo
echo "[1/6] 检查依赖"
if ! command -v curl >/dev/null 2>&1; then
    echo "  未找到 curl，尝试安装..."
    opkg update >/dev/null 2>&1
    opkg install curl ca-certificates >/dev/null 2>&1
    if ! command -v curl >/dev/null 2>&1; then
        echo "  ✗ curl 安装失败。请手动执行："
        echo "      opkg update && opkg install curl ca-certificates"
        exit 1
    fi
    echo "  ✓ curl 已安装"
else
    echo "  ✓ curl 已存在"
fi

# 确认 curl 支持 --resolve（钉 IP 实测全靠它）
if curl --noproxy '*' -s -m 5 -o /dev/null --resolve "github.com:443:127.0.0.1" https://github.com/ 2>/dev/null; then
    echo "  ✓ curl 支持 --resolve"
else
    echo "  ✓ curl 已接受 --resolve 参数（上面连 127.0.0.1 失败属预期）"
fi

# ---- 2. 备份 hosts ----
echo
echo "[2/6] 备份 /etc/hosts"
if [ -f /etc/hosts ]; then
    cp -p /etc/hosts "/etc/hosts.ghacc.bak.$(date +%Y%m%d-%H%M%S)" && echo "  ✓ 已备份"
else
    echo "  ⚠ /etc/hosts 不存在，将新建"
    printf '127.0.0.1 localhost\n::1 localhost\n' > /etc/hosts
fi

# ---- 3. 安装文件 ----
echo
echo "[3/6] 安装文件"
mkdir -p /etc/ghacc
cp -f "$SRC/ghacc-daemon"  /usr/bin/ghacc-daemon  && chmod +x /usr/bin/ghacc-daemon
cp -f "$SRC/ghacc.init"    /etc/init.d/ghacc      && chmod +x /etc/init.d/ghacc
cp -f "$SRC/uninstall.sh"  /usr/bin/ghacc-uninstall && chmod +x /usr/bin/ghacc-uninstall
[ -f /etc/ghacc/ghacc.conf ] || cp -f "$SRC/ghacc.conf" /etc/ghacc/ghacc.conf
echo "  ✓ /usr/bin/ghacc-daemon"
echo "  ✓ /etc/init.d/ghacc"
echo "  ✓ /usr/bin/ghacc-uninstall"
echo "  ✓ /etc/ghacc/ghacc.conf（已存在则保留你的改动）"

# ---- 4. 语法自检 ----
echo
echo "[4/6] 语法自检"
_ok=1
sh -n /usr/bin/ghacc-daemon  && echo "  ✓ ghacc-daemon"  || _ok=0
sh -n /etc/init.d/ghacc      && echo "  ✓ ghacc.init"    || _ok=0
sh -n /usr/bin/ghacc-uninstall && echo "  ✓ uninstall.sh" || _ok=0
if command -v luac >/dev/null 2>&1; then
    for _l in "$SRC"/pkg/root/usr/lib/lua/luci/*/ghacc.lua; do
        [ -f "$_l" ] || continue
        luac -p "$_l" 2>/dev/null && echo "  ✓ lua: $(basename $(dirname "$_l"))/ghacc.lua" \
                                  || { echo "  ✗ lua: $_l"; _ok=0; }
    done
else
    echo "  - 无 luac，Lua 文件跳过校验（LuCI 界面需在浏览器里确认）"
fi
[ "$_ok" -eq 1 ] || { echo "  ✗ 存在语法错误，已中止"; exit 1; }

# ---- 5. 开机自启 + 启动 ----
echo
echo "[5/6] 设置开机自启并启动"
/etc/init.d/ghacc enable
/etc/init.d/ghacc restart
sleep 5

# ---- 6. 结果确认 ----
echo
echo "[6/6] 结果确认"
/etc/init.d/ghacc status
echo
echo "--- 启动日志（前 10 行）---"
head -n 10 /var/log/ghacc.log 2>/dev/null || echo "（暂无日志，稍后再看）"

echo
echo "=========================================="
echo " 安装完成"
echo "=========================================="
echo
echo "常用命令："
echo "  查看状态    /etc/init.d/ghacc status"
echo "  查看日志    tail -f /var/log/ghacc.log"
echo "  停止服务    /etc/init.d/ghacc stop（会一并清理 hosts 标记块）"
echo "  彻底卸载    ghacc-uninstall"
echo "             或 sh $SRC/uninstall.sh"
echo
echo "LuCI 界面：服务 -> GitHub 加速（若菜单未出现，执行 /etc/init.d/rpcd restart 并刷新）"
echo
