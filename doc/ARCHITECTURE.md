# 原理与架构

本文说明 ghacc 是怎么工作的，以及**为什么这么设计**。
理解这些之后，排错会快很多。

---

## 一、整体数据流

```text
┌─────────────────────────────────────────────────────────────┐
│                        路由器                                │
│                                                             │
│  ┌──────────────────┐        每 15 秒                        │
│  │  ghacc-daemon    │◄──────────────── 定时唤醒              │
│  │  (常驻 shell)    │                                       │
│  └────────┬─────────┘                                       │
│           │                                                 │
│           │ ① 探测在用 IP（TLS 证书校验）                     │
│           │    不通？→ ② 并行重扫候选池                       │
│           │                                                 │
│           │ ③ 写入 /tmp/ghacc/hosts.addn（内存盘）            │
│           │                                                 │
│           │ ④ kill -HUP dnsmasq（热加载，不断网）             │
│           ▼                                                 │
│  ┌──────────────────┐                                       │
│  │    dnsmasq       │  conf-dir=/tmp/dnsmasq.d              │
│  │                  │   └── ghacc.conf: addn-hosts=...      │
│  └────────┬─────────┘                                       │
│           │ ⑤ 局域网设备查询时返回我们写入的 IP                │
└───────────┼─────────────────────────────────────────────────┘
            │
            ▼
   手机 / 电脑 / 电视盒子 / 路由器自身
```

**关键点**：设备端**什么都不用配**（除了把 DNS 指向这台路由器，而这通常是默认值）。

---

## 二、候选 IP 从哪来

`candidates()` 函数按**优先级**返回候选列表，因为最终会按
`MAX_CANDIDATES` 截断 —— **顺序即优先级**。

| 优先级 | 来源 | 维护情况 |
|---|---|---|
| 1 | `POOL_CACHE` —— 抓自 [`raw.hellogithub.com/hosts`](https://github.com/521xueweihan/GitHub520) | ✅ **GitHub520 项目持续维护**，主要来源 |
| 2 | 阿里 / 腾讯 DoH 接口实时解析 | ✅ 实时，但只是上游 DNS 的答案，不含可用性筛选 |
| 3 | `FASTLY_POOL` / `GH_POOL`（代码内置） | ❌ **写死的静态快照，无人维护，仅作兜底** |

### 为什么优先级很重要（曾经的缺陷）

早期写法是把三个来源合并后 `sort -u | head -24`。但 **`sort` 是字典序，
不是新鲜度** —— 实测 21 个陈旧硬编码 IP 会挤占 24 个名额的绝大部分：

```
旧逻辑(MAX=5): 140.82.112.17 140.82.112.18 140.82.112.22 140.82.112.26 140.82.112.3   ← 全是兜底池
新逻辑(MAX=5): 198.51.100.10 198.51.100.11 140.82.112.3 140.82.112.4 140.82.113.3      ← 新鲜优先
```

现在改为：**新鲜来源优先占名额，兜底池只补剩余位置**（且不与新鲜集合重复）。

---

## 三、健康判据的演进（本项目最曲折的部分）

判断"一个 IP 是否真的能用"这件事，被改过三次，每次都在修正上一次的错误。

### v1 ~ v2.3：只看状态码

```sh
[ "$_code" != "000" ] && 健康
```

**问题**：任何返回非 000 的服务器都被视为可用。实测存在**冒牌 IP**
返回 `200` 但正文只有 4 字节 `OK`（`content-type: text/plain`）。
它被写进 hosts 后，浏览器打开 github.com **只显示一个 OK**。

> 用户当时看到的正是这个现象。最初的判断是"浏览器 DoH 绕过 hosts"，
> 那是错的 —— **DoH 绕过应该表现为打不开，而不是显示一个 OK**。

### v2.4：加正文校验

```sh
状态码 2xx/3xx  +  正文 ≥ 5000 字节  +  正文含 "github"
```

**成功**：挡住了冒牌 IP 与 400 报错页。

**但引入了大面积误杀**：很多受管域名**根本不是网页**：

| 域名 | 根路径真实响应 |
|---|---|
| `objects.githubusercontent.com` | 404（只服务 `/github-production-*` 对象路径） |
| `avatars.githubusercontent.com` | 302 + 41 字节 |
| `api.github.com` | 200 但正文仅 2KB（REST JSON） |

这些域名访问根路径必然是 404 或极短正文，**与 IP 好坏无关**——
于是它们被判"永久无可用 IP"，日志反复刷"已连续失败 N 次"。

### v2.4.4：以 TLS 证书为准（当前）

```sh
curl 退出码 == 0   且   ssl_verify_result == 0   →   通过
```

**为什么这样对**：

- 真实 GitHub 的证书由公共 CA（Sectigo 等）签发，且 SAN 含该域名
- 冒牌 IP 要么**证书链不可信**，要么**域名不匹配**
- **404 / 302 / 空正文都发生在 TLS 握手之后，不再影响判定**

对 `github.com` 主站**额外保留**正文校验（`STRICT_MAIN_SITE=1`）作为双保险，
因为主站确实是网页，且它正是当初"只显示 OK"的受害者。

### 实测证据

| 目标 | curl 退出码 | ssl_verify_result | 判定 |
|---|---|---|---|
| 真实 GitHub IP | 0 | 0 | ✅ 通过 |
| 路由器（自签 `CN=QWRT`） | 60 | 18 | ❌ 拒绝 |
| 不可达 IP | 28（超时） | — | ❌ 拒绝 |

### ⚠️ 一个必须避开的陷阱：不能用 HEAD

实测 `objects.githubusercontent.com` **不响应 HEAD 请求**（挂起直到超时），
而 GET 0.4 秒就返回 404 —— **同一 IP、同一时刻**。

用 `curl -I` 会把好 IP 判死。所以改用 `curl -r 0-0`（GET 只取第 1 字节），
既走 GET 语义，又不下载整个正文。

### 这个判据挡不住什么

**挡不住"持有该域名合法证书却返回垃圾内容"的服务器。**
但那需要攻击者先从公共 CA 拿到该域名的证书，
已超出"IP 被劫持"的威胁模型。真实世界的假 IP 是前者（证书不可信/域名不匹配）。

---

## 四、为什么写 `/tmp/ghacc/hosts.addn` 而不是 `/etc/hosts`

这是项目早期最大的一次认知修正。

**假设**：dnsmasq 会读 `/etc/hosts`。
**实验**：往 `/etc/hosts` 追加 `1.2.3.4 ghacctest999.xyz`，
然后 `killall -HUP dnsmasq` 或完整 `restart`。
**结果**：`nslookup` **都返回 NXDOMAIN**。

再看 dnsmasq 的真实启动参数：

```
/usr/sbin/dnsmasq -C /var/etc/dnsmasq.conf.cfg01411c    ← 不是 /etc/dnsmasq.conf
```

该配置里写的是 `addn-hosts=/tmp/hosts` 与 `conf-dir=/tmp/dnsmasq.d`。
**QWRT/QSDK 这类固件的 dnsmasq 根本不读 `/etc/hosts`。**

**所以现在的做法**：

1. 写到 `ADDN_HOSTS=/tmp/ghacc/hosts.addn` —— 这才是 dnsmasq 真正读的文件
2. 在 `DNSMASQ_CONFDIR=/tmp/dnsmasq.d` 放一个 drop-in，
   内容一行 `addn-hosts=/tmp/ghacc/hosts.addn`，完成注册
3. `WRITE_ETC_HOSTS=0` —— 既然证明不读，就不再写 `/etc/hosts`

**附带好处：闪存零写入。** `/tmp` 是内存盘，长期运行不磨损闪存。

### 之前的误判是怎么发生的

`api`/`codeload`/`raw` 这些域名返回的"我们的 IP"，其实只是**上游 DNS 的正常答案**，
恰好和候选池重合，于是看起来"像是生效了"。

> **教训**：不能用连通性反推 hosts 是否生效。
> 必须用**不存在的测试域名**做决定性实验。

### 通用排错口诀

> 查 dnsmasq 行为，先 `ps w | grep dnsmasq` 拿到真实 `-C` 配置路径，
> 再看里面的 `no-hosts` / `addn-hosts` / `conf-dir`。
> **不要想当然认为它读 `/etc/hosts`。**

---

## 五、为什么 drop-in 变更后必须 restart 而不是 HUP

`conf-dir` 只在 dnsmasq **启动时**读取。所以：

| 操作 | 正确方式 |
|---|---|
| 新增/修改 drop-in | `/etc/init.d/dnsmasq restart`（完整重启一次） |
| 只改了 addn-hosts 文件内容 | `killall -HUP dnsmasq`（热加载，不断网） |
| **删除** drop-in | **restart** —— SIGHUP 不会卸载已加载的 addn-hosts |

这个区分很重要：**用错会导致"改了但没生效"或"删了但还在用"**。

---

## 六、DNS 自愈校验（v2.4 新增）

### 为什么需要

`hosts_in_sync()` 原本只检查两个文件**存不存在**。但：

> **文件齐全 ≠ 解析生效。**

如果固件改了 `conf-dir` 的加载规则、drop-in 被其他程序覆盖、
或 dnsmasq 重启后没再读该文件 —— **文件依然齐全，而解析早已失效**，
日志里一切正常。

这正是本项目历史上反复踩的同一类坑。

### 做法

定期（`SELFCHECK_INTERVAL`，默认 300 秒）反问本机 dnsmasq 一个探针域名，
确认返回的地址里**包含我们写入的 IP**；不符则记日志并自动重建 + 重载。

实现上要注意兼容两种 `nslookup` 输出格式：

```
BSD:      Address: 140.82.114.4
busybox:  Address 1: 140.82.112.26
```

且首部的 `Address: 192.168.2.1#53` 是**服务器地址**（带 `#53`），必须排除。
统一用严格点分四段正则过滤即可一并处理。

---

## 七、资源保护设计

用户态 shell 循环**不可能搞崩内核**，但有 4 个真实风险：

| 风险 | 防护措施 |
|---|---|
| **Flash 磨损**（最真实） | 写入 `/tmp` 内存盘（零闪存写入）+ `MIN_WRITE_INTERVAL` 节流 + 脏标记合并 |
| **抖动风暴** | `FAIL_THRESHOLD` 连续失败才判定死亡；切换后 `COOLDOWN` 秒不再重扫 |
| **进程/内存失控** | 并发封顶 16、`MAX_CANDIDATES` 截断、`ulimit -c 0 -f 4096` |
| **并发写文件** | `mkdir` 原子锁 + PID 存活检测（僵尸锁原地接管，不删目录） |

另外：

- 写入是「写临时文件 → 原子 `mv` 替换」，**中途被杀不会留下半个文件**
- `procd respawn` 有重启次数上限，不会无限重启风暴
- 主循环拆成 1 秒粒度 sleep，**SIGTERM 能在 1 秒内被响应**
  （整段 sleep 时信号要等它跑完才处理，会导致 stop 时锁来不及清理）

---

## 八、opkg 升级顺序（写维护脚本必读）

```
旧 prerm upgrade  →  解包  →  旧 postrm upgrade  →  新 postinst
```

**这个顺序有个陷阱**：如果 `prerm` 里做了 `stop` + `disable` + 摘 hosts 块，
而失败发生在之后的 `postrm`，那么包会留在半安装态：
**服务已停 + 已禁用 + hosts 块已摘**，用户看到的就是"完全没生效"。

**当前的应对**：`prerm` 读 `$1` 判断动作，升级时**只 stop 不 disable**，
这样中途失败也能在下次开机或手动 start 时恢复。

> **教训**：写维护脚本时必须考虑"中途失败"的残留状态，
> `disable`/`stop` 这类破坏性动作要区分 upgrade 与 remove。

---

## 九、OpenWrt ipk 格式（打包必读）

**OpenWrt 的 `.ipk` 不是 Debian 的 `ar` 格式**，而是：

```
gzip( tar( ./debian-binary, ./control.tar.gz, ./data.tar.gz ) )
```

源码证据（`opkg-lede` 的 `libbb/unarchive.c`）：`deb_extract()` 用的是
`gzip_exec` + `get_header_tar`（校验 `ustar` magic），
**全仓库没有 `!<arch>` 解析代码**。

用 `ar` 打出来的包会报 `pkg_init_from_file: Malformed package file`，
原因链是：ar 文件 gzip 解不开 → 一个成员都读不到 → control 为空 →
解析不到 `Package:` 行 → 报格式错误。

**两个 macOS 相关的坑**：

1. **BSD `ar` 会丢成员** —— `ar rc x.ipk ...` 只产出 96 字节的符号表，
   产物是坏的**且不报错**。本项目改用 `mkipk.py` 手写。
2. **`bsdtar` 会自动塞 `._xxx` / `.DS_Store`** —— 需 `COPYFILE_DISABLE=1`
   并在打包器里按 basename 过滤。

> **通用教训**：「Malformed package file」这类报错**别猜打包器 bug**，
> 直接下载一个官方包验证格式。

---

## 十、为什么在路由器上复刻不了 Steam++

这个项目开始前逆向过 Steam++（Watt Toolkit）：

- 包结构是 MonoBundle（552MB .NET 程序集）+ 单 GUI 二进制，**无 CLI**
- 代理实现基于 **Titanium.Web.Proxy**（.NET 的 HTTPS MITM 库）+ 自带 SOCKS5
- 服务端依赖包含 `IAcceleratorRechargeClient`（加速充值）

**结论**：它之所以稳，是因为**不靠"找没被封的 IP"，而是把流量中转到自有服务端**。
这部分是私有协议 + 账号体系，无法也不应在路由器上复刻。

所以本项目选择另一条路：**不绕过封锁，只把"找可用 IP + 通知全网"自动化到极致。**
它注定解决不了"全部 IP 都被封"，但它诚实、透明、零依赖、不需要账号。
