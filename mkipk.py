#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
生成 OpenWrt 原生格式的 .ipk

关键事实（2026-10-07 用官方包 + opkg 源码验证，别再改回 ar 格式！）：
  OpenWrt 的 opkg（git.openwrt.org/project/opkg-lede）的 deb_extract()
  是「gzip -d 之后直接按 tar 头解析」，libbb 里没有任何 ar 解析代码
  （全仓库 grep 不到 "!<arch>"）。它期望的 ipk 结构是：

      package.ipk  =  gzip( tar( ./debian-binary   内容 "2.0"
                                 ./control.tar.gz
                                 ./data.tar.gz ) )

  内层 control.tar.gz / data.tar.gz 也是 tar.gz，成员名带 "./" 前缀。
  这与 Debian 的 ar 格式 ipk（!<arch> + debian-binary + ...）完全不兼容，
  用 ar 格式打出来的包装不上，报 "Malformed package file"。

为什么不用系统 tar/ar：
  macOS 的 tar 是 bsdtar（默认 pax 格式，uid/gid 是当前用户），
  BSD ar 还有丢成员的历史坑。这里全部用 Python 的 tarfile 显式按
  USTAR 格式重写，uid/gid/mtime 归一化，macOS / Linux 产物逐字节一致。

用法: mkipk.py <build目录> <输出ipk> <版本>
  build 目录里要有 build_ipk.sh 先生成好的 control.tar.gz 与 data.tar.gz
"""
import gzip
import io
import os
import sys
import tarfile
import time


def normalize_tgz(src_bytes: bytes, mtime: int) -> bytes:
    """把 tar.gz 解开后按 USTAR 规范重写一遍，再 gzip 回去。

    归一化：uid/gid=0、uname/gname 置空、mtime 统一。
    这一步保证 opkg 的 get_header_tar（要求 ustar magic + 校验和正确）一定能读。

    同时过滤 macOS 垃圾：bsdtar 会把扩展属性打成 ._xxx（AppleDouble）
    和 .DS_Store 塞进包里，装到路由器上会污染文件系统，必须剔除。
    """
    src = tarfile.open(fileobj=io.BytesIO(src_bytes))
    buf = io.BytesIO()
    out = tarfile.open(fileobj=buf, mode="w", format=tarfile.USTAR_FORMAT)
    for m in src.getmembers():
        base = os.path.basename(m.name)
        if base.startswith("._") or base == ".DS_Store":
            continue
        data = b""
        if m.isfile():
            data = src.extractfile(m).read()
        ti = tarfile.TarInfo(m.name)
        ti.type = tarfile.DIRTYPE if m.isdir() else m.type
        ti.size = 0 if m.isdir() else len(data)
        ti.mode = m.mode
        ti.mtime = mtime
        ti.uid = 0
        ti.gid = 0
        ti.uname = ""
        ti.gname = ""
        out.addfile(ti, io.BytesIO(data) if ti.size else None)
    out.close()
    return gzip.compress(buf.getvalue(), mtime=mtime)


def main():
    if len(sys.argv) != 4:
        print("用法: mkipk.py <build目录> <输出ipk> <版本>")
        sys.exit(2)
    build_dir, out_path, version = sys.argv[1], sys.argv[2], sys.argv[3]
    mtime = int(time.time())

    # ---- 读入 build_ipk.sh 生成的两个内层包 ----
    paths = {}
    for name in ("control.tar.gz", "data.tar.gz"):
        p = os.path.join(build_dir, name)
        if not os.path.isfile(p):
            print("缺失内层包: %s" % p)
            sys.exit(1)
        with open(p, "rb") as f:
            paths[name] = f.read()

    # ---- 内层按 USTAR 规范重写 ----
    control_tgz = normalize_tgz(paths["control.tar.gz"], mtime)
    data_tgz = normalize_tgz(paths["data.tar.gz"], mtime)

    # ---- 外层：tar( ./debian-binary, ./control.tar.gz, ./data.tar.gz ) 再 gzip ----
    outer_members = [
        ("./debian-binary", b"2.0\n", 0o644),
        ("./control.tar.gz", control_tgz, 0o644),
        ("./data.tar.gz", data_tgz, 0o644),
    ]
    buf = io.BytesIO()
    tf = tarfile.open(fileobj=buf, mode="w", format=tarfile.USTAR_FORMAT)
    for name, data, mode in outer_members:
        ti = tarfile.TarInfo(name)
        ti.size = len(data)
        ti.mode = mode
        ti.mtime = mtime
        ti.uid = 0
        ti.gid = 0
        ti.uname = ""
        ti.gname = ""
        tf.addfile(ti, io.BytesIO(data))
    tf.close()

    os.makedirs(os.path.dirname(os.path.abspath(out_path)) or ".", exist_ok=True)
    with open(out_path, "wb") as f:
        f.write(gzip.compress(buf.getvalue(), mtime=mtime))

    print("已生成: %s (%d 字节, 版本 %s)" % (out_path, os.path.getsize(out_path), version))


if __name__ == "__main__":
    main()
