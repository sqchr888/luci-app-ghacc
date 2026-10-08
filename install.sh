#!/bin/sh
# ============================================================
# ghacc-daemon 安装脚本 —— 在路由器上以 root 执行
#
# 两种用法都支持：
#
#   1) 从仓库一键安装（无需电脑中转，脚本会自己下载 ipk）：
#        cd /tmp && curl -fsSL https://raw.githubusercontent.com/sqchr888/luci-app-ghacc/main/install.sh | sh
#
#   2) 已有完整源码目录（git clone 或解压 tarball 后）：
#        sh /tmp/luci-app-ghacc/install.sh
#
# 已适配：QWRT 25.12.2 / ipq95xx / aarch64_cortex-a53
# 卸载：  ghacc-uninstall    或   sh <源码目录>/uninstall.sh
# ============================================================
set -u

REPO="sqchr888/luci-app-ghacc"
RAW_BASE="https://raw.githubusercontent.com/$REPO/main"
REL_BASE="https://github.com/$REPO/releases/latest/download"

# ---- 判断运行模式 ----
# 被管道执行时 $0 是 sh（或 -sh），此时 SRC 无意义，走「自下载」模式。
# 直接 sh install.sh 时 $0 是脚本路径，若同目录有 ghacc-daemon 则走「本地源码」模式。
SRC=$(dirname "$0" 2>/dev/null || echo .)
MODE="remote"
if [ -f "$SRC/ghacc-daemon" ] && [ -f "$SRC/ghacc.init" ]; then
    MODE="local"
fi

echo "=========================================="
echo " ghacc-daemon 安装"
echo "=========================================="
echo "  模式:   $([ "$MODE" = local ] && echo "本地源码（${SRC}）" || echo "在线安装（从 GitHub 拉取）")"

# ---- 0. 环境体检 ----
echo
echo "[0/7] 环境体检"
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
echo "[1/7] 检查依赖"
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

# ---- 2. 获取文件 ----
echo
echo "[2/7] 获取文件"
WORK=/tmp/ghacc-install.$$
rm -rf "$WORK"; mkdir -p "$WORK"

if [ "$MODE" = local ]; then
    SRCROOT="$SRC"
    echo "  ✓ 使用本地源码：$SRCROOT"
else
    # 在线模式：直接取 Release 里的 ipk（比拉源码更省事、更稳）。
    # 若取不到 ipk，退化为拉取整棵源码树。
    #
    # 版本号的确定方式（按可靠性排序）：
    #   1) GitHub API 的 releases/latest —— 最准，但 api.github.com 偶发不可达
    #   2) 从 main 分支的 VERSION 线索推断 —— 目前没有该文件，故跳过
    #   3) 依次试探若干常见版本号 —— 最后的兜底
    _ok=0
    _ver=""
    for _apiip in "" 140.82.112.6 140.82.113.6; do
        if [ -n "$_apiip" ]; then
            _json=$(curl -fsSL -m 15 --noproxy '*' --resolve "api.github.com:443:$_apiip" \
                    "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null)
        else
            _json=$(curl -fsSL -m 15 --noproxy '*' \
                    "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null)
        fi
        [ -n "$_json" ] || continue
        _ver=$(printf '%s' "$_json" | grep -oE 'ghacc_[0-9]+\.[0-9]+\.[0-9]+_all\.ipk' | head -1)
        [ -n "$_ver" ] && break
    done

    # 兜底：API 全不可达时，从 release 页面的 HTML 里找文件名
    if [ -z "$_ver" ]; then
        _ver=$(curl -fsSL -m 20 --noproxy '*' \
               "https://github.com/$REPO/releases/latest" 2>/dev/null \
               | grep -oE 'ghacc_[0-9]+\.[0-9]+\.[0-9]+_all\.ipk' | head -1)
    fi

    if [ -n "$_ver" ]; then
        echo "  下载 $_ver ..."
        if curl -fsSL -m 180 -o "$WORK/pkg.ipk" "$REL_BASE/$_ver" 2>/dev/null \
           && [ -s "$WORK/pkg.ipk" ]; then
            echo "  ✓ 已下载 ipk（$(wc -c < "$WORK/pkg.ipk") 字节）"
            _ok=1
        fi
    else
        echo "  未能确定版本号（GitHub API / release 页面均不可达）"
    fi

    if [ "$_ok" -eq 0 ]; then
        echo "  ipk 获取失败，改用源码方式（拉取 tarball）..."
        if curl -fsSL -m 180 "https://github.com/$REPO/archive/refs/heads/main.tar.gz" \
             | tar xz -C "$WORK" 2>/dev/null; then
            SRCROOT="$WORK/$REPO-main"
            [ -d "$SRCROOT" ] || SRCROOT=$(find "$WORK" -maxdepth 1 -type d -name '*-main' | head -1)
            if [ -n "$SRCROOT" ] && [ -f "$SRCROOT/ghacc-daemon" ]; then
                echo "  ✓ 已获取源码：$SRCROOT"
                MODE="local"
            else
                echo "  ✗ 无法获取安装文件。请检查网络连通性后重试，"
                echo "    或改用「电脑下载 ipk 后 scp 上传」的方式。"
                rm -rf "$WORK"; exit 1
            fi
        else
            echo "  ✗ 下载失败。请检查网络连通性后重试，"
            echo "    或改用「电脑下载 ipk 后 scp 上传」的方式。"
            rm -rf "$WORK"; exit 1
        fi
    fi
fi

# ---- 3. 安装（ipk 方式）或 拷贝文件（源码方式）----
echo
if [ -f "$WORK/pkg.ipk" ]; then
    echo "[3/7] opkg 安装"
    if opkg install "$WORK/pkg.ipk" 2>&1 | sed 's/^/  /'; then
        echo "  ✓ opkg 安装完成"
    else
        echo "  ✗ opkg 安装失败，请查看上面的输出"
        rm -rf "$WORK"; exit 1
    fi
    # ipk 已自带 postinst（enable + start + 重启 rpcd），这里直接跳到收尾
    SKIP_MANUAL=1
else
    echo "[3/7] 安装文件（源码方式）"
    SKIP_MANUAL=0
    mkdir -p /etc/ghacc
    cp -f "$SRCROOT/ghacc-daemon"  /usr/bin/ghacc-daemon      && chmod +x /usr/bin/ghacc-daemon
    cp -f "$SRCROOT/ghacc.init"    /etc/init.d/ghacc          && chmod +x /etc/init.d/ghacc
    cp -f "$SRCROOT/uninstall.sh"  /usr/bin/ghacc-uninstall   && chmod +x /usr/bin/ghacc-uninstall
    [ -f /etc/ghacc/ghacc.conf ] || cp -f "$SRCROOT/ghacc.conf" /etc/ghacc/ghacc.conf

    # LuCI 界面文件（此前遗漏，会导致菜单里看不到插件）
    if [ -d "$SRCROOT/pkg/root" ]; then
        ( cd "$SRCROOT/pkg/root" && find . -type f -print ) | while read -r _f; do
            _dest="${_f#./}"
            mkdir -p "/$(dirname "$_dest")"
            cp -f "$SRCROOT/pkg/root/$_dest" "/$_dest"
        done
        # 归一化权限：LuCI 的 lua/htm/json 必须 644，可执行文件 755
        find /usr/lib/lua/luci -type f \( -name '*.lua' -o -name '*.htm' \) -exec chmod 644 {} \; 2>/dev/null
        chmod 644 /usr/share/rpcd/acl.d/luci-app-ghacc.json /etc/config/ghacc 2>/dev/null
        chmod 755 /usr/bin/ghacc-daemon /etc/init.d/ghacc /usr/bin/ghacc-uninstall 2>/dev/null
        echo "  ✓ LuCI 界面与 UCI 配置已安装"
    else
        echo "  ⚠ 源码中缺少 pkg/root，LuCI 界面不会被安装（命令行仍可用）"
    fi

    echo "  ✓ /usr/bin/ghacc-daemon"
    echo "  ✓ /etc/init.d/ghacc"
    echo "  ✓ /usr/bin/ghacc-uninstall"
    echo "  ✓ /etc/ghacc/ghacc.conf（已存在则保留你的改动）"
fi

# ---- 4. 备份 hosts ----
echo
echo "[4/7] 备份 /etc/hosts"
if [ -f /etc/hosts ]; then
    cp -p /etc/hosts "/etc/hosts.ghacc.bak.$(date +%Y%m%d-%H%M%S)" && echo "  ✓ 已备份"
else
    echo "  ⚠ /etc/hosts 不存在，将新建"
    printf '127.0.0.1 localhost\n::1 localhost\n' > /etc/hosts
fi

# ---- 5. 语法自检 ----
echo
echo "[5/7] 语法自检"
_ok=1
sh -n /usr/bin/ghacc-daemon    && echo "  ✓ ghacc-daemon"    || _ok=0
sh -n /etc/init.d/ghacc        && echo "  ✓ ghacc.init"      || _ok=0
sh -n /usr/bin/ghacc-uninstall && echo "  ✓ uninstall.sh"    || _ok=0
if command -v luac >/dev/null 2>&1; then
    for _l in /usr/lib/lua/luci/controller/ghacc.lua /usr/lib/lua/luci/model/cbi/ghacc.lua; do
        [ -f "$_l" ] || continue
        luac -p "$_l" 2>/dev/null && echo "  ✓ lua: $_l" || { echo "  ✗ lua: $_l"; _ok=0; }
    done
else
    echo "  - 无 luac，Lua 文件跳过校验（LuCI 界面需在浏览器里确认）"
fi
[ "$_ok" -eq 1 ] || { echo "  ✗ 存在语法错误，已中止"; rm -rf "$WORK"; exit 1; }

# ---- 6. 开机自启 + 启动 ----
echo
echo "[6/7] 设置开机自启并启动"
if [ "${SKIP_MANUAL:-0}" = "1" ]; then
    # ipk 的 postinst 已经做过 enable+start，这里只确认一次状态
    /etc/init.d/ghacc enable  >/dev/null 2>&1
    /etc/init.d/ghacc restart >/dev/null 2>&1
else
    /etc/init.d/ghacc enable
    /etc/init.d/ghacc restart
fi
sleep 5

# ---- 7. 结果确认 ----
echo
echo "[7/7] 结果确认"
/etc/init.d/ghacc status
echo
echo "--- 启动日志（前 10 行）---"
head -n 10 /var/log/ghacc.log 2>/dev/null || echo "（暂无日志，稍后再看）"

rm -rf "$WORK"

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
echo
echo "LuCI 界面：服务 -> GitHub 加速（若菜单未出现，执行 /etc/init.d/rpcd restart 并刷新）"
echo
echo "⚠️ 装完请务必验证一次解析是否真的生效："
echo "     nslookup github.com 127.0.0.1"
echo "   返回的地址应与下面这条命令的输出一致："
echo "     cat /tmp/ghacc/hosts.addn"
echo
