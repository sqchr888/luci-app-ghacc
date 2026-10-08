<div align="center">

# luci-app-ghacc

**OpenWrt 上的 GitHub 实时加速守护进程（带 LuCI 管理界面）**

让**整个局域网**——手机、平板、电脑、电视盒子——无需安装任何客户端即可访问 GitHub

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-2.4.4-green.svg)](CHANGELOG.md)
[![Architecture](https://img.shields.io/badge/arch-all-lightgrey.svg)](#四架构兼容性)
[![OpenWrt](https://img.shields.io/badge/OpenWrt-21.02%2B-orange.svg)](#四架构兼容性)

[功能特性](#二功能特性) · [安装](#三安装) · [架构兼容](#四架构兼容性) · [使用](#五使用) · [原理](doc/ARCHITECTURE.md) · [排错](doc/TROUBLESHOOTING.md) · [更新记录](CHANGELOG.md) · [致谢](doc/CREDITS.md)

**🌐 [English](README.en.md) | 简体中文**

</div>

---

## 一、这是什么

在国内访问 GitHub 经常不稳定。常见做法有两种：

- **改本机 hosts**：只能修一台设备，IP 一失效就得重新找，而且要找"还没被封的 IP"这件事本身就是碰运气
- **装加速客户端**：每台设备都要装、要配置，电视盒子和手机很难处理

**ghacc 解决的是"整个局域网"这一层的问题。** 它在路由器上常驻运行：

1. 每 15 秒探测一次当前在用的 GitHub IP 是否还活着
2. 一旦失效，立刻从候选池并行重扫，秒级热切换到可用 IP
3. 通过 dnsmasq 的 `addn-hosts` 把结果推给**所有**局域网设备
4. 全程热加载（SIGHUP），不断网、不重启服务

```text
        手机 / 电脑 / 电视盒子
                 │  DNS 查询
                 ▼
        ┌────────────────────┐
        │  路由器 192.168.x.1 │
        │  ┌──────────────┐  │
        │  │ dnsmasq      │◄─┼── ghacc 写入
        │  │  addn-hosts  │  │    /tmp/ghacc/hosts.addn
        │  └──────┬───────┘  │
        │         │ SIGHUP   │
        │  ┌──────▼───────┐  │
        │  │ ghacc-daemon │  │  每 15s 探测
        │  │  健康探测+切换│  │  失效则重扫候选池
        │  └──────────────┘  │
        └────────┬───────────┘
                 ▼
            可用的 GitHub IP
```

> **它不做的事**：不搭代理、不做 TLS 中间人、不中转你的流量、不上传任何数据。
> 只是"帮你挑一个当前能用的 IP 并告诉局域网"。若某时刻全部 IP 都不可达，
> 它会老实地报"无可用 IP"并持续重试，而不是假装成功。

---

## 二、功能特性

| 特性 | 说明 |
|---|---|
| **秒级自动切换** | 常驻探测（默认 15s 一轮），IP 失效立即换掉，不必等定时任务的下一个周期 |
| **TLS 证书校验** | 用 `ssl_verify_result` 判断 IP 真伪，而不是看 HTTP 状态码——能识别"返回 200 但其实是冒牌服务器"的假 IP |
| **按域名分级校验** | 主站 `github.com` 做严格正文校验；`objects`/`api`/`avatars` 等非网页域名只验证书，避免误杀 |
| **DNS 自愈校验** | 定期反问本机 dnsmasq 确认真解析到了写入的 IP，能发现"文件在但没加载"的静默失效 |
| **闪存零写入** | 写入 `/tmp`（内存盘）而非 `/etc/hosts`，长期运行不磨损闪存 |
| **不断网** | `SIGHUP` 热加载 dnsmasq，切换过程不中断现有连接 |
| **LuCI 界面** | 「服务 → GitHub 加速」：状态、条目、日志（每秒自动刷新）、四个操作按钮 |
| **一键卸载** | `ghacc-uninstall`，幂等可重复执行，七步清理干净 |
| **纯脚本实现** | 守护进程是 busybox ash，界面是 Lua，**无需交叉编译**，`Architecture: all` |

---

## 三、安装

### 方式 1：ipk 安装包（推荐）

从 [Releases](../../releases) 下载 `ghacc_x.y.z_all.ipk`：

```sh
scp ghacc_2.4.4_all.ipk root@192.168.2.1:/tmp/
ssh root@192.168.2.1 "opkg install /tmp/ghacc_2.4.4_all.ipk"
```

> 把 `192.168.2.1` 换成你路由器的地址。

装完打开 LuCI：**服务 → GitHub 加速**。

### 方式 2：源码安装

```sh
scp -r . root@192.168.2.1:/tmp/luci-app-ghacc
ssh root@192.168.2.1 "sh /tmp/luci-app-ghacc/install.sh"
```

安装脚本会先做环境体检（固件 / 架构 / curl 版本 / dnsmasq 实例 / overlay 剩余空间），
再装文件、语法自检、启动。

### 依赖

| 依赖 | 说明 |
|---|---|
| `curl` | **必需**，且需支持 `--resolve` 与 `-w '%{ssl_verify_result}'`（7.5x+ 均可） |
| `ca-certificates` | **必需**，否则无法校验证书 |
| `dnsmasq` / `dnsmasq-full` | **必需**，作为 DNS 服务端 |
| `luci-base` / `rpcd` | 仅 LuCI 界面需要；不装也能用命令行运维 |

---

## 四、架构兼容性

**本包是 `Architecture: all`** —— 守护进程是纯 shell（busybox ash），界面是纯 Lua，
**不含任何预编译二进制**。因此理论上可在**任意架构**的 OpenWrt 上安装：

`x86_64` · `aarch64_cortex-a53/a72` · `arm_cortex-a7/a9` · `mips_24kc` · `mipsel_24kc` ·
`mips64el` · `riscv64` · `i386_pentium4` …

### 但请如实看待下面这张表

| 平台 | 状态 | 说明 |
|---|---|---|
| **QWRT 25.12.2（ipq95xx / aarch64_cortex-a53）** | ✅ **实机验证** | 开发者本人的环境。含 QSDK 多实例 dnsmasq、dnsmasq-full 2.92 |
| 官方 OpenWrt 21.02 / 22.03 / 23.05 / 24.10 | ⚠️ 理论可用，**未实测** | 走的是标准 `addn-hosts` 机制，预期可用 |
| ImmortalWrt / Lean 版 / 其他第三方 | ⚠️ 理论可用，**未实测** | 若固件改动 dnsmasq 配置路径，可能需要调整 `DNSMASQ_CONFDIR` |
| 极老版本（≤19.07） | ❌ 不建议 | `procd` 与 LuCI 差异较大，未适配 |

> **为什么不能拍胸脯保证全部可用？** 因为不同固件的 dnsmasq 启动参数不同。
> 本项目的核心假设是「dnsmasq 通过 `conf-dir` 加载 `/tmp/dnsmasq.d/*.conf`」，
> 这需要你实际验证一次（见下方"装完必做的三件事"）。**如果你的固件不满足，
> 换个配置路径即可，无需改代码。**
>
> 欢迎提交 Issue 告知你的固件与架构，我会把验证结果补进上表。

### 装完必做的三件事

```sh
# 1) 确认 dnsmasq 的真实配置文件路径与 conf-dir
ps w | grep [d]nsmasq
#    看 -C 后面的路径，例如 /var/etc/dnsmasq.conf.cfg01411c
#    再 grep conf-dir 与 addn-hosts 看它加载哪些目录

# 2) 确认守护进程在跑、且选出了 IP
/etc/init.d/ghacc status
cat /tmp/ghacc/hosts.addn

# 3) 【最关键】确认 dnsmasq 真的返回了我们写入的 IP
nslookup github.com 127.0.0.1
#    返回的地址应该与 hosts.addn 里的一致，而不是运营商 DNS 的答案
```

第 3 步是判别性的。**"文件写对了"不等于"解析生效了"** —— 这个项目早期
就栽在这上面（见 [CHANGELOG](CHANGELOG.md) 的 v2.3 条目）。

---

## 五、使用

### LuCI 界面

菜单：**服务 → GitHub 加速**

- **运行状态**页
  - 守护进程状态、开机自启、当前生效 IP 数
  - 启动 / 停止 / 重启 / 强制重扫 IP / 清理日志
    （按钮会随运行状态自动置灰——运行中时"启动"不可点，反之亦然）
  - 当前生效条目表
  - 最近 200 行日志，**每秒自动滚动刷新**（深色底，上翻查看时不会被拽回底部）
- **参数设置**页
  - 探测间隔、超时、每域名 IP 数、冷却期、并发数、守护域名
  - 日志自动清理开关 + 保留天数（默认 3 天）

### 命令行运维

```sh
/etc/init.d/ghacc status      # 运行状态 + 当前生效 IP
/etc/init.d/ghacc restart
/etc/init.d/ghacc stop        # 停止并清理标记块
/etc/init.d/ghacc disable

tail -f /var/log/ghacc.log    # 实时日志
logread | grep ghacc
```

启动后日志前几行是**环境自检**，排错时先看它：

```text
2026-10-08 01:21:03 ghacc-daemon v2 启动 (interval=15s, cooldown=120s, max_ips=2, 并发=8)
2026-10-08 01:21:03 hosts 文件: /etc/hosts （普通文件）
2026-10-08 01:21:03 curl: 7.83.1
2026-10-08 01:21:03 addn-hosts: /tmp/ghacc/hosts.addn（dnsmasq 实际读取的文件）
2026-10-08 01:21:03 dnsmasq 进程: 17386
2026-10-08 01:21:04 候选池已加载
2026-10-08 01:21:28 切换 github.com → 140.82.116.3
2026-10-08 01:21:59 已更新 /tmp/ghacc/hosts.addn 并热加载 dnsmasq
```

### 卸载

```sh
ghacc-uninstall              # 推荐：七步清理，幂等
```

手动兜底方案见 [doc/TROUBLESHOOTING.md](doc/TROUBLESHOOTING.md#卸载不干净时手动兜底)。

---

## 六、配置参数

配置文件：`/etc/ghacc/ghacc.conf`（或用 LuCI 界面改，保存后自动生成）

### 探测与切换

| 参数 | 默认 | 说明 |
|---|---|---|
| `CHECK_INTERVAL` | 15 | 健康探测间隔（秒） |
| `PROBE_TIMEOUT` | 3 | 单 IP 探测超时，弱路由可调 4~5 |
| `MAX_IPS` | 2 | 每域名写入 IP 数，建议 1~2 |
| `FAIL_THRESHOLD` | 2 | 连续失败几次才判定死亡（抗抖动） |
| `COOLDOWN` | 120 | 切换后冷却期（秒），防抖动风暴 |
| `CONCURRENCY` | 8 | 并发探测数，硬上限 16 |
| `MAX_CANDIDATES` | 24 | 每域名最多探测数，限制单轮 fork 总数 |

### 健康判据

| 参数 | 默认 | 说明 |
|---|---|---|
| `STRICT_MAIN_SITE` | 1 | 对 `github.com` 主站额外做正文校验 |
| `MIN_BODY_SIZE` | 5000 | 主站正文体积下限（字节） |
| `BODY_MARKER` | github | 主站正文必须含有的特征串 |

### DNS 与输出

| 参数 | 默认 | 说明 |
|---|---|---|
| `ADDN_HOSTS` | `/tmp/ghacc/hosts.addn` | **dnsmasq 真正读取的文件** |
| `DNSMASQ_CONFDIR` | `/tmp/dnsmasq.d` | 放 drop-in 配置的目录 |
| `WRITE_ETC_HOSTS` | 0 | 是否额外写 `/etc/hosts`（兼容老固件） |
| `DNSMASQ_PID` | 空 | dnsmasq pid 路径，空 = 自动探测 |
| `DNS_RELOAD_CMD` | 空 | 自定义重载命令，空 = 自动 |

### 资源保护

| 参数 | 默认 | 说明 |
|---|---|---|
| `MIN_WRITE_INTERVAL` | 60 | 最小写入间隔（秒），**保护闪存** |
| `SELFCHECK_INTERVAL` | 300 | DNS 自愈校验最小间隔（秒） |
| `AUTO_CLEAN_LOG_DAYS` | 3 | 日志保留天数，`0` = 关闭按天清理 |
| `MAX_LOG` | 200 | 日志行数上限 |
| `CYCLE_GUARD` | 300 | 单轮耗时告警阈值（秒） |

完整注释版见源码 [`ghacc.conf`](ghacc.conf)。

---

## 七、常见问题

<details>
<summary><b>和「定时 cron 刷 hosts」有什么区别？</b></summary>

| | cron 定时刷新 | ghacc |
|---|---|---|
| 触发 | 到点才跑 | 常驻，每 15 秒探一次 |
| IP 被封后 | 干等下一周期 | 秒级自动换掉 |
| 探测范围 | 全量重扫 | 只查在用的，不通才重扫 |
| 生效方式 | 重启 dnsmasq（断网） | SIGHUP 热加载（不断网） |

</details>

<details>
<summary><b>会不会把路由器搞崩 / 写坏闪存？</b></summary>

**不会导致内核崩溃**——用户态 shell 循环不可能让内核崩溃。但确实有 4 个真实风险，
项目已全部设防：

| 风险 | 防护 |
|---|---|
| Flash 磨损（最真实） | `MIN_WRITE_INTERVAL=60` + 脏标记合并；且写入 `/tmp` 内存盘，**实际闪存零写入** |
| 抖动风暴 | 连续 `FAIL_THRESHOLD` 次失败才判定死亡；切换后 `COOLDOWN` 秒不再重扫 |
| 进程/内存失控 | 并发封顶 16、候选池截断、`ulimit -c 0 -f 4096` |
| 并发写文件 | `mkdir` 原子锁 + PID 存活检测（僵尸锁原地接管） |

另外写入是「写临时文件 → 原子 `mv` 替换」，中途被杀不会留下半个文件；
`procd respawn` 有重启次数上限，不会无限重启风暴。

</details>

<details>
<summary><b>日志一直报「无可用 IP」怎么办？</b></summary>

**这通常不是故障。** 若某时刻该线路对 GitHub 全部候选 IP 都不可达（俗称"全封窗口"），
守护进程无能为力，只能老实报告并持续重试，等网络环境变化后自动恢复。

**正确的判断方法**：不要看"能不能打开 GitHub"，而要看
**"它写的 IP 是否被 dnsmasq 正确返回"**：

```sh
cat /tmp/ghacc/hosts.addn        # 看它选了什么
nslookup github.com 127.0.0.1    # 看 dnsmasq 是否照实返回
```

两者一致 = 工作正常（打不开是全封所致）；不一致 = 才是真故障。

</details>

<details>
<summary><b>浏览器仍打不开 / 报证书错误？</b></summary>

按顺序排查：

1. **浏览器的 Secure DNS（DoH）会绕过路由器 DNS** —— 必须关掉
   （Brave/Chrome：`设置 → 隐私和安全 → 安全 → 使用安全 DNS` 关闭）
2. **不要在 `/etc/hosts` 里写 `路由器IP 域名`** —— 那是"直接指定该域名为路由器 IP"，
   会导致浏览器去连路由器并报证书错误。正确做法是保持 hosts 干净、把 DNS 指向路由器
3. **代理工具会打架** —— 若同时开着 Steam++、Clash 等会做 MITM 的工具，
   它们会替换证书、抢占同一域名，两者不要同时使用

详见 [doc/TROUBLESHOOTING.md](doc/TROUBLESHOOTING.md)。

</details>

<details>
<summary><b>它找的 IP 从哪来？有人维护吗？</b></summary>

四个来源，**只有第一个是持续维护的**：

| 来源 | 维护情况 |
|---|---|
| [`raw.hellogithub.com/hosts`](https://github.com/521xueweihan/GitHub520) | ✅ **GitHub520 项目**持续维护 |
| 阿里 / 腾讯 DoH | ✅ 实时解析，但只是上游 DNS 的答案 |
| 代码内置 `GH_POOL` / `FASTLY_POOL` | ❌ **写死的静态快照，无人维护，仅作兜底** |

新鲜来源优先占用 `MAX_CANDIDATES` 名额，兜底池只补剩余位置。
详见 [doc/CREDITS.md](doc/CREDITS.md)。

</details>

---

## 八、已知限制

1. **它找的是「还没被封的 IP」，不是绕过封锁。** 若某时刻全部 IP 都不可达，
   它无能为力，会持续重试直到环境变化。
2. **只对走 DNS 的 HTTPS 生效** —— 自解析域名的 App 会绕开。
3. **健康判据是启发式的**，不是密码学证明。它依赖 TLS 证书校验，能挡掉证书不可信
   或域名不匹配的假 IP；但挡不住"持有该域名合法证书却返回垃圾内容"的服务器
   （那需要攻击者先从公共 CA 拿到该域名证书，已超出"IP 被劫持"的威胁模型）。
4. **内置兜底 IP 池会过期**，需要时请自行更新或改用镜像上游。
5. **仅 QWRT 实机验证过**，其他固件请按"装完必做的三件事"自行确认。

---

## 九、开发与打包

本项目是纯 shell + Lua，**无需交叉编译**。

```sh
# 方式 1：本机直出 ipk（macOS / Linux 均可）
sh build_ipk.sh
#   → dist/ghacc_<版本>_all.ipk

# 方式 2：OpenWrt SDK / 构建系统
#   把本目录放进 package/，然后：
make package/luci-app-ghacc/compile V=s
```

> **打包时注意两个坑**（已在脚本里处理）：
> 1. OpenWrt 的 `.ipk` **不是** Debian 的 `ar` 格式，而是
>    `gzip(tar(./debian-binary, ./control.tar.gz, ./data.tar.gz))`。
>    用系统 `ar` 打出来的包会报 `Malformed package file`。
> 2. macOS 的 `bsdtar` 会往包里塞 `._xxx` / `.DS_Store`，需 `COPYFILE_DISABLE=1`。

### 文件结构

```text
luci-app-ghacc/
├── ghacc-daemon            守护进程主程序（busybox ash）→ /usr/bin/ghacc-daemon
├── ghacc.init              procd 启动脚本             → /etc/init.d/ghacc
├── ghacc.conf              守护进程配置（带完整注释） → /etc/ghacc/ghacc.conf
├── install.sh              源码安装脚本
├── uninstall.sh            一键卸载脚本               → /usr/bin/ghacc-uninstall
├── build_ipk.sh            打包脚本
├── mkipk.py                OpenWrt 原生格式打包器（非 Debian ar 格式）
├── Makefile                OpenWrt SDK 构建文件
├── doc/
│   ├── ARCHITECTURE.md     原理与数据流
│   ├── TROUBLESHOOTING.md  排错手册
│   └── CREDITS.md          引用资源与致谢
├── pkg/
│   ├── control/            control / conffiles / postinst / prerm / postrm
│   └── root/               LuCI 界面 + UCI 配置（按根文件系统布局）
└── dist/                   打包产物
```

---

## 十、参与贡献

欢迎提交 Issue 与 PR，特别是：

- **告知你的固件与架构**是否可用 —— 我会补进[架构兼容表](#四架构兼容性)
- 报告某固件下 dnsmasq 配置路径不同（附 `ps w | grep [d]nsmasq` 输出）
- 改进健康判据、补充候选 IP 来源

提交 Issue 时请附上：

```sh
cat /etc/openwrt_release                          # 固件与版本
uname -m                                           # 架构
ps w | grep [d]nsmasq                              # dnsmasq 启动参数
/etc/init.d/ghacc status                           # 服务状态
tail -30 /var/log/ghacc.log                        # 日志
```

---

## 十一、许可证

[MIT](LICENSE)

本项目引用了第三方资源（GitHub520 等），版权归原作者所有，详见 [doc/CREDITS.md](doc/CREDITS.md)。

> **免责声明**：本软件按"现状"提供，不附带任何担保。使用前请自行评估风险，
> 建议先在非关键设备上测试。作者不对因使用本软件造成的任何损失负责。
