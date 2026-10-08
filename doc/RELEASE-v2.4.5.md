# ghacc v2.4.5

OpenWrt 上的 GitHub 实时加速守护进程（带 LuCI 管理界面）。
让**整个局域网**——手机、电脑、电视盒子——无需安装任何客户端即可访问 GitHub。

> 纯 shell + Lua 实现，`Architecture: all`，**适用于任意架构**，无需交叉编译。

---

## 📦 安装

```sh
# 下载附件中的 ipk 后传到路由器
scp ghacc_2.4.5_all.ipk root@192.168.2.1:/tmp/
ssh root@192.168.2.1 "opkg install /tmp/ghacc_2.4.5_all.ipk"
```

装完打开 LuCI：**服务 → GitHub 加速**

**依赖**：`curl`、`ca-certificates`、`dnsmasq`（或 `dnsmasq-full`）

### 校验下载文件

```sh
sha256sum ghacc_2.4.5_all.ipk
# 应输出：
# cdd426dd8dffb56101bd4f5ea36127f1c6898f33e02459c984d2151a2644a774
```

---

## ✨ 本次更新要点

### 修复：证书合法但服务不对的 IP 会被误判为可用

GitHub 多个子域共用 `*.github.com` 通配证书，所以「证书校验通过」只证明
对面是 GitHub 的某台服务器，**不证明它提供的是该子域应有的服务**。

实测案例：`api.github.com` 被解析到一个证书完全合法（`ssl_verify_result=0`）
但不提供 API 服务的 IP —— 访问根路径返回 301 跳转到 `github.com`。
这会让所有依赖 `api.github.com` 的工具（`gh` CLI、CI、各类客户端）失败，
而守护进程却认为该 IP 健康。

现在对能定义「正确响应」的域名追加服务特征校验：
**`api.github.com` 根路径必须返回 200 且正文为 JSON**。新增开关 `STRICT_API`。

### 新增：无需电脑中转，路由器上一条命令安装

```sh
cd /tmp && curl -fsSL https://raw.githubusercontent.com/sqchr888/luci-app-ghacc/main/install.sh | sh
```

脚本会自动判断运行模式：管道执行时走「在线安装」（优先取 Release 的 ipk，
失败则回退到拉取源码 tarball）；检测到同目录有源码时走「本地源码」安装。

### 修复：源码安装现在会一并装 LuCI 界面

此前源码方式只装了命令行部分，导致 LuCI 菜单不出现。现在会一并安装
界面文件与 UCI 配置，并归一化权限（LuCI 资源必须 644）。

---


## 🔧 主要特性

| 特性 | 说明 |
|---|---|
| **秒级自动切换** | 常驻探测（默认 15s），IP 失效立即换掉，不等定时任务周期 |
| **TLS 证书校验** | 用 `ssl_verify_result` 识别假 IP，而非 HTTP 状态码 |
| **按域名分级校验** | 主站严格校验正文；非网页域名只验证书，避免误杀 |
| **DNS 自愈校验** | 定期反问本机 dnsmasq，发现"配置在但没加载"的静默失效 |
| **闪存零写入** | 写入 `/tmp` 内存盘，长期运行不磨损闪存 |
| **不断网** | `SIGHUP` 热加载 dnsmasq，切换过程不中断连接 |
| **LuCI 界面** | 状态、条目、日志（每秒刷新）、操作按钮 |
| **一键卸载** | `ghacc-uninstall`，幂等可重复执行 |

---

## ⚠️ 架构兼容性说明

本包为 `Architecture: all` —— 纯 shell + Lua，无预编译二进制，
**理论上有任意架构的 OpenWrt 都可用**。

| 平台 | 状态 |
|---|---|
| **QWRT 25.12.2（ipq95xx / aarch64_cortex-a53）** | ✅ 实机验证 |
| 官方 OpenWrt 21.02 ~ 24.10 | ⚠️ 理论可用，未实测 |
| ImmortalWrt / Lean 版等第三方 | ⚠️ 理论可用，未实测 |
| ≤ 19.07 | ❌ 未适配 |

> 不同固件的 dnsmasq 配置路径可能不同。本项目假设 dnsmasq 通过
> `conf-dir` 加载 `/tmp/dnsmasq.d/*.conf`，**装完请验证一次**（见下）。

### 装完必做的三件事

```sh
# 1) 看 dnsmasq 的真实配置路径
ps w | grep [d]nsmasq

# 2) 确认守护进程在跑且选出了 IP
/etc/init.d/ghacc status
cat /tmp/ghacc/hosts.addn

# 3) 【最关键】确认 dnsmasq 真的返回了我们写入的 IP
nslookup github.com 127.0.0.1
```

第 3 步是判别性的：**"文件写对了"不等于"解析生效了"**。

---

## 📌 已知限制

1. **它找的是"还没被封的 IP"，不是绕过封锁。** 若某时刻全部候选都不可达，
   它会如实报告并持续重试，等网络恢复后自动生效。
2. 只对走 DNS 的 HTTPS 生效；自解析域名的 App 会绕开。
3. 判据依赖 TLS 证书校验，能挡掉证书不可信/域名不匹配的假 IP，
   但挡不住"持有合法证书却返回垃圾内容"的服务器（超出"IP 被劫持"的威胁模型）。
4. **浏览器若开了 Secure DNS（DoH）会绕过路由器 DNS**，需要关闭。
5. 内置兜底 IP 池会过期，需要时请自行更新。

---

## 📖 文档

- [README（中文）](https://github.com/sqchr888/luci-app-ghacc/blob/main/README.md)
- [README (English)](https://github.com/sqchr888/luci-app-ghacc/blob/main/README.en.md)
- [原理解析](https://github.com/sqchr888/luci-app-ghacc/blob/main/doc/ARCHITECTURE.md)
- [排错手册](https://github.com/sqchr888/luci-app-ghacc/blob/main/doc/TROUBLESHOOTING.md)
- [完整更新记录](https://github.com/sqchr888/luci-app-ghacc/blob/main/CHANGELOG.md)

---

## 🙏 致谢

候选 IP 数据主要来自 [GitHub520](https://github.com/521xueweihan/GitHub520) 项目，
感谢其持续维护。详见 [CREDITS](https://github.com/sqchr888/luci-app-ghacc/blob/main/doc/CREDITS.md)。

---

**完整变更**：[CHANGELOG.md](https://github.com/sqchr888/luci-app-ghacc/blob/main/CHANGELOG.md)
