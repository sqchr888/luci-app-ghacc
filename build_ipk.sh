#!/bin/sh
# ============================================================
# 把本项目打包成 OpenWrt 的 .ipk
#
# 在 macOS / Linux 上直接跑：  sh build_ipk.sh
# 产物： dist/ghacc_<版本>_all.ipk
#
# 说明：.ipk 本质是 ar 归档，内含三件套
#   debian-binary  control.tar.gz(控制信息+安装脚本)  data.tar.gz(实际文件)
# 本项目是纯 shell + lua，无需交叉编译，所以 Architecture: all，
# 任何架构的 OpenWrt 都能装。
# ============================================================
set -eu
cd "$(dirname "$0")"

VERSION=$(grep -m1 '^Version:' pkg/control/control | awk '{print $2}')
DIST=dist
IPK="$DIST/ghacc_${VERSION}_all.ipk"

echo "==== 打包 ghacc v$VERSION ===="

# ---- 1. 把主文件放进包目录 ----
echo "[1/4] 收集文件"
mkdir -p pkg/root/usr/bin pkg/root/etc/init.d pkg/root/etc/ghacc
cp -f ghacc-daemon    pkg/root/usr/bin/ghacc-daemon
cp -f ghacc.init      pkg/root/etc/init.d/ghacc
cp -f ghacc.conf      pkg/root/etc/ghacc/ghacc.conf
cp -f uninstall.sh    pkg/root/usr/bin/ghacc-uninstall
chmod 755 pkg/root/usr/bin/ghacc-daemon pkg/root/etc/init.d/ghacc \
          pkg/root/usr/bin/ghacc-uninstall
chmod 644 pkg/root/etc/ghacc/ghacc.conf

# ---- 1a. LuCI 资源文件权限归一化 ----
# 用 Write 工具新建的文件是 600，而 LuCI 的 .htm/.lua/json 必须是 644 才能
# 被 uhttpd / rpcd 正常读取（部分固件会降权运行）。踩过一次：新增的
# view/ghacc/cbi_style.htm 是 600，装到路由器后只有 root 可读，
# 结果是样式静默不生效、很难查。这里统一归一化，杜绝复发。
find pkg/root/usr/lib/lua -type f \( -name '*.lua' -o -name '*.htm' \) \
    -exec chmod 644 {} \; 2>/dev/null
[ -d pkg/root/usr/share/rpcd/acl.d ] && chmod 644 pkg/root/usr/share/rpcd/acl.d/*.json 2>/dev/null
[ -f pkg/root/etc/config/ghacc ] && chmod 644 pkg/root/etc/config/ghacc
echo "  ✓ LuCI 资源权限归一化为 644"

find pkg/root -type f | sort | sed 's/^/  /'

# ---- 1b. 控制脚本必须可执行 ----
# opkg 会直接 exec 这些脚本；权限位不是 755 时会在安装/升级阶段报
# "Permission denied ... returned status 126" 并中断，且这个错误发生在
# 解包之后，会把包留在半安装状态 —— 很难查。这里强制设位并校验。
chmod 755 pkg/control/postinst pkg/control/prerm pkg/control/postrm
chmod 644 pkg/control/control pkg/control/conffiles
for ctlscript in pkg/control/postinst pkg/control/prerm pkg/control/postrm; do
    [ -x "${ctlscript}" ] || { echo "控制脚本缺执行位: ${ctlscript}"; exit 1; }
done
echo "  ✓ 控制脚本权限 755"

# ---- 2. 语法自检（打包前拦住低级错误）----
echo "[2/4] 语法自检"
sh -n pkg/root/usr/bin/ghacc-daemon || { echo "守护进程语法错误"; exit 1; }
sh -n pkg/root/etc/init.d/ghacc     || { echo "init 脚本语法错误"; exit 1; }
# 注意：变量名一律用 ${} 包裹——后面紧跟中文标点时会被当成变量名的一部分
if command -v luac >/dev/null 2>&1; then
    for luafile in $(find pkg/root -name '*.lua'); do
        if luac -p "${luafile}"; then
            echo "  ✓ lua: ${luafile}"
        else
            echo "  ✗ lua 语法错误: ${luafile}"
            exit 1
        fi
    done
else
    echo "  - 本机无 luac，跳过 lua 校验"
fi
echo "  ✓ shell 语法通过"

# ---- 3. 构建三件套 ----
echo "[3/4] 构建归档"
rm -rf "$DIST" .build && mkdir -p "$DIST" .build

printf '2.0\n' > .build/debian-binary

# COPYFILE_DISABLE=1：禁止 macOS bsdtar 往包里塞 ._xxx（AppleDouble 扩展属性垃圾）
COPYFILE_DISABLE=1 tar -czf .build/control.tar.gz -C pkg/control ./control ./conffiles ./postinst ./prerm ./postrm
COPYFILE_DISABLE=1 tar -czf .build/data.tar.gz    -C pkg/root    .

# ---- 4. 打 ar 包 ----
# 不用系统 ar：macOS 的 BSD ar 会丢弃非 Mach-O 成员，产物只有 96 字节。
# 统一走 mkipk.py 手写 ar 格式，跨平台可靠。
echo "[4/4] 生成 .ipk"
PY=$(command -v python3 || command -v python || true)
if [ -z "$PY" ]; then
    echo "  ✗ 未找到 python3，无法打包"
    exit 1
fi
"$PY" mkipk.py .build "$IPK" "$VERSION" || exit 1

# ---- 4b. 回读产物，确认控制脚本在包里确实带了执行位 ----
"$PY" - "$IPK" <<'PYEOF' || exit 1
import gzip, tarfile, io, sys
outer = tarfile.open(fileobj=io.BytesIO(gzip.decompress(open(sys.argv[1], 'rb').read())))
for m in outer.getmembers():
    nm = m.name[2:] if m.name.startswith('./') else m.name
    if nm != 'control.tar.gz':
        continue
    inner = tarfile.open(fileobj=io.BytesIO(outer.extractfile(m).read()))
    bad = [j.name for j in inner.getmembers()
           if j.name.endswith(('/postinst', '/prerm', '/postrm')) and not (j.mode & 0o111)]
    if bad:
        print('  ✗ 包内控制脚本缺执行位:', bad)
        sys.exit(1)
    print('  ✓ 包内控制脚本权限正常')
PYEOF

rm -rf .build
echo
echo "==== 完成 ===="
ls -lh "$IPK"
echo
echo "安装到路由器："
echo "  scp $IPK root@192.168.2.1:/tmp/"
echo "  ssh root@192.168.2.1 'opkg install /tmp/ghacc_${VERSION}_all.ipk'"
