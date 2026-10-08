#!/bin/sh
# ============================================================
# ghacc-uninstall —— 彻底清除 ghacc 的一切痕迹
#
# 用法（路由器上以 root 执行）：
#   sh /tmp/openwrt-ghacc/uninstall.sh
# 或（已装进系统后）：
#   ghacc-uninstall
#
# 会依次做 7 件事：
#   1. 停服务 + 取消开机自启 + 杀残留进程
#   2. 从 /etc/hosts 摘掉 GHACC 标记块（改动前自动备份）
#   3. 删除程序与配置文件
#   4. opkg 卸载（如果是通过 ipk 装的）
#   5. 清运行时残留（锁 / pid / 状态目录 / 日志）
#   6. 清 LuCI 缓存并重载 rpcd（让菜单消失）
#   7. 热加载 dnsmasq，使改动立即生效
#
# 幂等：重复执行不会报错，只会报告"未发现"。
# ============================================================

MARK_START="# GHACC-BEGIN"
MARK_END="# GHACC-END"

# ---- 自我复制到 /tmp 后再执行 ----
# 原因：第 4 步 opkg remove 会把本脚本自身删掉，
#       而 sh 是边读边执行的，文件中途消失会导致脚本异常中断，
#       留下"卸载了一半"的烂摊子。所以先搬到 /tmp 再 exec。
case "${0}" in
    /tmp/ghacc-uninstall.sh) ;;
    *)
        if cp -f "${0}" /tmp/ghacc-uninstall.sh 2>/dev/null; then
            exec sh /tmp/ghacc-uninstall.sh "$@"
        fi
        ;;
esac

echo "=========================================="
echo " ghacc 卸载程序"
echo "=========================================="

# ---------- 1. 停服务 ----------
echo
echo "[1/7] 停止服务并取消开机自启"
if [ -x /etc/init.d/ghacc ]; then
    /etc/init.d/ghacc stop    >/dev/null 2>&1
    /etc/init.d/ghacc disable >/dev/null 2>&1
    echo "  ✓ 已停止并取消开机自启"
else
    echo "  - 未发现 /etc/init.d/ghacc（可能已卸载或从未安装）"
fi

# 兜底：杀掉任何残留的守护进程（init 脚本缺失 / 服务停止失败的情况）
_left=""
for _p in $(pgrep -f ghacc-daemon 2>/dev/null); do
    kill -9 "${_p}" 2>/dev/null
    _left="yes"
done
if [ -n "${_left}" ]; then
    echo "  ✓ 已强制结束残留进程"
else
    echo "  ✓ 无残留进程"
fi

# ---------- 2. 清理 hosts ----------
echo
echo "[2/7] 清理 /etc/hosts 中的 GHACC 标记块"
_hosts_cleaned=0
for _f in /etc/hosts /tmp/hosts /tmp/ghacc/hosts.addn; do
    [ -f "${_f}" ] || continue
    if grep -q "^${MARK_START}" "${_f}" 2>/dev/null; then
        cp -p "${_f}" "${_f}.ghacc.bak.$(date +%Y%m%d-%H%M%S)" 2>/dev/null
        _tmp=$(mktemp 2>/dev/null) || _tmp="/tmp/.ghacc.clean.$$"
        awk -v s="${MARK_START}" -v e="${MARK_END}" '
            index($0, s) == 1 { inb = 1; next }
            index($0, e) == 1 { inb = 0; next }
            !inb { print }
        ' "${_f}" > "${_tmp}" 2>/dev/null
        if [ -s "${_tmp}" ]; then
            cp -f "${_tmp}" "${_f}" 2>/dev/null
            echo "  ✓ 已清理 ${_f}（原文件已备份为 ${_f}.ghacc.bak.*）"
        else
            # 整个文件就只有一个标记块（hosts 是专用文件的情况）→ 清空即可
            : > "${_f}" 2>/dev/null
            echo "  ✓ 已清空 ${_f}（该文件原本只有 ghacc 内容）"
        fi
        rm -f "${_tmp}"
        _hosts_cleaned=1
    fi
done
[ "${_hosts_cleaned}" -eq 1 ] || echo "  - /etc/hosts 中没有 GHACC 标记块，无需清理"

# 顺带确认 dnsmasq 的 addnhosts 配置（tmpfs 模式下会用到）
if uci -q get dhcp.@dnsmasq[0].addnhosts 2>/dev/null | grep -q ghacc; then
    echo "  ✓ 发现 dnsmasq 的 addnhosts 里有 ghacc 项，正在移除"
    uci -q del_list dhcp.@dnsmasq[0].addnhosts='/tmp/ghacc/hosts.addn' 2>/dev/null
    uci commit dhcp 2>/dev/null
fi

# 移除 dnsmasq conf-dir 里的 drop-in。
# 注意：删掉它之后必须「重启」而非「热加载」dnsmasq —— conf-dir 只在启动时读取，
# SIGHUP 不会卸载已经加载的 addn-hosts，留着会指向一个已不存在的文件。
_dropin_removed=0
for _d in /tmp/dnsmasq.d /etc/dnsmasq.d; do
    if [ -f "${_d}/ghacc.conf" ]; then
        rm -f "${_d}/ghacc.conf" && echo "  ✓ 已移除 drop-in ${_d}/ghacc.conf"
        _dropin_removed=1
    fi
done

# ---------- 3. 删文件 ----------
echo
echo "[3/7] 删除程序与配置文件"
for _f in \
    /usr/bin/ghacc-daemon \
    /usr/bin/ghacc-uninstall \
    /etc/init.d/ghacc \
    /etc/ghacc/ghacc.conf \
    /etc/config/ghacc \
    /usr/share/rpcd/acl.d/luci-app-ghacc.json \
    /usr/lib/lua/luci/controller/ghacc.lua \
    /usr/lib/lua/luci/model/cbi/ghacc.lua \
    /usr/lib/lua/luci/view/ghacc/status.htm
do
    if [ -e "${_f}" ]; then
        rm -f "${_f}" && echo "  ✓ 已删除 ${_f}"
    fi
done
rmdir /etc/ghacc 2>/dev/null
rm -rf /usr/lib/lua/luci/view/ghacc 2>/dev/null

# ---------- 4. opkg 卸载 ----------
echo
echo "[4/7] 从 opkg 数据库注销"
if opkg list-installed 2>/dev/null | grep -q '^ghacc '; then
    opkg remove ghacc >/dev/null 2>&1
    if opkg list-installed 2>/dev/null | grep -q '^ghacc '; then
        echo "  ⚠ opkg remove 未成功，可手动执行：opkg remove ghacc --force-removal-of-dependent-packages"
    else
        echo "  ✓ 已从 opkg 数据库移除"
    fi
else
    echo "  - opkg 中未登记 ghacc（若当初是手动安装的，属正常）"
fi

# ---------- 5. 清运行时残留 ----------
echo
echo "[5/7] 清理运行时残留"
for _f in \
    /var/run/ghacc.pid \
    /var/log/ghacc.log \
    /tmp/ghacc \
    /var/run/ghacc.lock
do
    if [ -e "${_f}" ]; then
        rm -rf "${_f}" && echo "  ✓ 已删除 ${_f}"
    fi
done
# 注意：这里刻意不删除 /tmp/ghacc-uninstall.sh —— 那正是本脚本自身，
# 边读边执行的 sh 在中途删掉自己会异常中断。/tmp 是内存盘，重启即自动消失。

# ---------- 6. 清 LuCI 缓存 ----------
echo
echo "[6/7] 清理 LuCI 缓存并重载 rpcd"
rm -f /tmp/luci-indexcache*   2>/dev/null
rm -rf /tmp/luci-modulecache  2>/dev/null
rm -f /tmp/.ghacc.clean.*     2>/dev/null
if [ -x /etc/init.d/rpcd ]; then
    /etc/init.d/rpcd restart >/dev/null 2>&1 && echo "  ✓ rpcd 已重载"
else
    echo "  - 未发现 rpcd（可能未装 LuCI）"
fi

# ---------- 7. 热加载 dnsmasq ----------
echo
echo "[7/7] 重载 dnsmasq 使改动立即生效"
_reloaded=0
if [ "${_dropin_removed}" -eq 1 ]; then
    # drop-in 被移除 → 必须完整重启，热加载不会卸载已加载的 addn-hosts
    /etc/init.d/dnsmasq restart >/dev/null 2>&1 && _reloaded=1
fi
killall -HUP dnsmasq 2>/dev/null && _reloaded=1
if [ "${_reloaded}" -eq 0 ] && [ -f /var/run/dnsmasq.pid ]; then
    kill -HUP "$(cat /var/run/dnsmasq.pid)" 2>/dev/null && _reloaded=1
fi
if [ "${_reloaded}" -eq 0 ]; then
    /etc/init.d/dnsmasq reload >/dev/null 2>&1 && _reloaded=1
fi
[ "${_reloaded}" -eq 1 ] && echo "  ✓ dnsmasq 已热加载" || echo "  ⚠ dnsmasq 未响应，建议重启路由器或执行 service dnsmasq restart"

echo
echo "=========================================="
echo " 卸载完成"
echo "=========================================="
echo
echo "验证（应全部无输出）："
echo "  ls /usr/bin/ghacc-daemon /etc/init.d/ghacc 2>&1 | grep -v 'No such'"
echo "  grep -c GHACC /etc/hosts"
echo "  opkg list-installed | grep ghacc"
echo "  pgrep -f ghacc-daemon"
echo
echo "hosts 备份文件（确认网络正常后可自行删除）："
ls -1 /etc/hosts.ghacc.bak.* 2>/dev/null | sed 's/^/  /' || echo "  （无）"
echo
exit 0
