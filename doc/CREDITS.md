# 引用资源与致谢

本项目站在他人的肩膀上。以下资源**不是**本项目的成果，版权归原作者所有。

---

## 一、候选 IP 来源

### GitHub520 —— 核心上游

| | |
|---|---|
| **地址** | <https://github.com/521xueweihan/GitHub520> |
| **数据端点** | <https://raw.hellogithub.com/hosts> |
| **作者** | [@521xueweihan](https://github.com/521xueweihan) |
| **用途** | 本项目**最重要的候选 IP 来源**（`POOL_URL`） |
| **获取方式** | 每 `POOL_REFRESH`（默认 600 秒）拉取一次，解析出各域名对应的 IP |

**它是怎么工作的**：该项目通过 DNS 查询 + 实际连通性测试，
持续生成一份「当前可用的 GitHub 相关域名 IP」的 hosts 文件。
文件每次请求都是最新的（响应头带 `Last-Modified`，文件尾也自带 `Update time`）。

**注意**：本项目**不复制、不重新分发**该项目的数据，而是运行时按需拉取。
因此你使用本项目时，也在依赖该项目的可用性。

> 如果你觉得它有价值，**请去给原项目点个 Star** —— 这是对它最好的支持。

### 公共 DNS-over-HTTPS 接口

| 服务商 | 端点 | 用途 |
|---|---|---|
| 阿里云公共 DNS | `https://223.5.5.5/resolve` | 实时解析候选域名（`DOH_LIST`） |
| 腾讯公共 DNS | `https://1.12.12.12/resolve` | 同上，作为第二个来源 |

这两者只是**通用的 DNS 解析服务**，本项目用它们做实时解析兜底。
它们**不含**可用性筛选 —— 返回的只是上游 DNS 的答案。

> ⚠️ 使用这些公共服务请遵守各自的服务条款。

---

## 二、技术参考

### opkg-lede —— ipk 格式的权威依据

| | |
|---|---|
| **地址** | <https://git.openwrt.org/project/opkg-lede.git> |
| **镜像** | <https://github.com/openwrt/opkg-lede> |
| **用途** | 确认 OpenWrt 的 `.ipk` 真实格式 |

**关键证据**（`libbb/unarchive.c`）：

```c
deb_extract() {
    gzip_exec(...)        // 外层是 gzip
    get_header_tar(...)   // 内层是 tar，校验 "ustar" magic
}
```

全仓库**没有** `!<arch>` 解析代码 —— 这证明 OpenWrt ipk 不是 Debian 的 `ar` 格式，
而是 `gzip(tar(...))`。没有这个发现，本项目的打包会一直失败。

### OpenWrt 官方文档

| 资源 | 地址 | 用途 |
|---|---|---|
| OpenWrt 官网 | <https://openwrt.org/> | 固件、包管理的基础文档 |
| 官方包索引 | <https://downloads.openwrt.org/> | 下载官方 ipk 用于格式对照 |
| LuCI 文档 | <https://github.com/openwrt/luci/wiki> | 界面开发参考 |
| procd 文档 | <https://openwrt.org/docs/guide-developer/procd-init-scripts> | 启动脚本写法 |

---

## 三、运行时依赖

本项目**不打包**这些组件，仅依赖系统已安装的版本：

| 组件 | 许可 | 用途 |
|---|---|---|
| `curl` | MIT-like | 所有 HTTP/TLS 探测 |
| `ca-certificates` | MPL-2.0 | TLS 证书链校验（健康判据的基础） |
| `dnsmasq` / `dnsmasq-full` | GPL-2.0 / GPL-3.0 | DNS 服务端，通过 `addn-hosts` 生效 |
| `busybox` | GPL-2.0 | 提供 `ash` 与基础命令 |
| `luci-base` / `rpcd` | Apache-2.0 | Web 管理界面 |

---

## 四、概念与思路上受到的启发

### hosts 类加速方案的社区实践

本项目在方案选型时参考了社区大量"定时任务刷 hosts"的实现
（如各类 `GitHub520` 的 cron 用法、`hosts` 自动更新脚本等）。

**本项目与它们的关键区别**在于：

| | 定时 cron 刷 hosts | ghacc |
|---|---|---|
| 触发 | 到点才跑 | 常驻，每 15 秒探一次 |
| IP 被封后 | 干等下一周期 | 秒级自动换掉 |
| 生效方式 | 重启 dnsmasq（断网） | SIGHUP 热加载（不断网） |

这些社区实践验证了"改 hosts"这条路是可行的，本项目做的是把它自动化到极致，
并覆盖整个局域网。

### 对 Steam++ (Watt Toolkit) 的逆向分析

为了更好地理解"为什么有些工具比 hosts 稳"，本项目逆向分析了
[Steam++](https://steampp.net/)（Watt Toolkit）的加速机制：

- 包结构：MonoBundle（约 552MB .NET 程序集）+ 单 GUI 二进制，**无 CLI**
- 代理实现：**Titanium.Web.Proxy**（.NET 的 HTTPS MITM 库）+ 自带 SOCKS5 服务端
- 服务端依赖：`IAccelerateClient`、**`IAcceleratorRechargeClient`（加速充值）**

**结论**：它之所以稳，是因为**不靠"找没被封的 IP"，而是把流量中转到自有服务端**。
这部分是私有协议 + 账号体系，**无法也不应在路由器上复刻**。

这个结论直接决定了本项目的定位：**不绕过封锁，只把"找可用 IP + 通知全网"自动化**。
（本次分析仅用于理解机制与方案选型，未复制其任何代码。）

---

## 五、许可声明

- 本项目自身代码：[MIT License](../LICENSE)
- 引用的第三方资源：版权归各自作者所有，遵循各自许可
- 本项目**不重新分发**任何第三方数据或二进制

如果你认为本项目的内容侵犯了你的权益，请提 Issue，我会立即处理。

---

## 六、特别感谢

- **[@521xueweihan](https://github.com/521xueweihan)** 与 GitHub520 项目 ——
  没有它持续维护的 IP 数据，本项目就失去了最主要的候选来源
- **OpenWrt 社区** —— 提供了稳定、可移植的路由器系统与完善的文档
- 所有在真实设备上验证并反馈问题的用户 —— 架构兼容表里的每一条都来自你们

---

## 如何贡献你的资源

如果你维护着类似的 IP 数据源（例如自建镜像），欢迎提 Issue 告知。
本项目支持通过配置覆盖上游：

```sh
# /etc/ghacc/ghacc.conf
POOL_URL=https://你的镜像/hosts
GH_POOL="1.2.3.4 5.6.7.8"          # 覆盖内置兜底池
DOH_LIST="https://你的DoH/resolve"
```
