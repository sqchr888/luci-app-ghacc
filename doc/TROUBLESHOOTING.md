# 排错手册

排错前请先记住一条最重要的原则：

> **判断 ghacc 有没有工作，要看「它写的 IP 是否被 dnsmasq 正确返回」，
> 而不是看「现在能不能打开 GitHub」。**
>
> 后者可能只是撞上了"全封窗口"—— 那种情况下重装、改配置都是白费力气。

---

## 一、五步标准排查流程

```sh
# ① 先看其他网站通不通 —— 区分"断网"与"GitHub 被封锁"
curl -sS -m 6 -o /dev/null -w '%{http_code}\n' https://www.baidu.com
#    baidu 也不通 → 是网络问题，与 ghacc 无关

# ② 守护进程是否在跑
/etc/init.d/ghacc status
pgrep -f ghacc-daemon

# ③ 它选出了什么 IP
cat /tmp/ghacc/hosts.addn
#    日志若报"无可用 IP"，说明此刻候选全部不可达（属正常，会自动重试）

# ④ 【关键】dnsmasq 是否照实返回 —— 在路由器上执行
nslookup github.com 127.0.0.1
#    应与 ③ 的内容一致。若返回别的 IP → 才是真故障

# ⑤ 最后才怀疑客户端
#    浏览器里看 brave://net-internals/#dns （Chrome 系）确认它解析到什么
```

**③ 与 ④ 一致 = 工作正常。** 打不开只是全封所致，等网络恢复会自动生效。

---

## 二、按现象查

### 日志一直报「无可用 IP（已连续失败 N 次）」

**先判断是全封还是误杀**：

```sh
# 看是"某个域名"失败还是"全部域名"失败
tail -30 /var/log/ghacc.log
```

| 情况 | 含义 | 处理 |
|---|---|---|
| 全部域名都失败 | 大概率是全封窗口 | **正常现象**，等它自动重试。可换时间再看 |
| 只有个别域名反复失败 | 可能是判据误杀（见下） | 检查该域名的根路径行为 |

**误杀的识别方法**：有些域名不是网页，根路径必然返回 404 或极短正文。
从 v2.4.4 起判据已改为 TLS 证书校验，不再受此影响。若你用的是旧版本，
请先升级。

临时减少开销：把用不到的域名从 `DOMAINS` 里删掉。

---

### 装完没生效 / 局域网设备打不开

```sh
# 1) 设备 DNS 是否指向这台路由器
# 2) 设备是否开了自己的 DoH（见下方"浏览器问题"）
# 3) dnsmasq 是否真的加载了我们的配置
ps w | grep [d]nsmasq          # 看 -C 后面的真实配置路径
cat /var/etc/dnsmasq.conf.cfg01411c 2>/dev/null | grep -E 'addn-hosts|conf-dir'
ls -la /tmp/dnsmasq.d/

# 4) 决定性验证
nslookup github.com 127.0.0.1
```

若 `conf-dir` 不是 `/tmp/dnsmasq.d`，在配置里改成你的实际路径：

```sh
DNSMASQ_CONFDIR=/你的/实际/路径
```

---

### 日志说写入成功，但 nslookup 返回的还是旧 IP

**根因**：固件出厂预置了同名 hosts 条目（如 `20.205.243.166 github.com`），
且排在标记块**之前**。dnsmasq 对重名条目只保留**文件中靠前的**那条。

v2.2 起会自动摘除块外同名条目。若仍异常：

```sh
cat -n /etc/hosts          # 看有没有块外的 github 条目
```

---

### 日志报「dnsmasq 热加载失败」

QSDK / 多实例环境下 pid 路径可能非标准。三级兜底已内置
（`killall -HUP` → 逐个试 pid 路径 → `/etc/init.d/dnsmasq reload`）。

仍失败时在配置里显式指定：

```sh
DNSMASQ_PID=/var/run/dnsmasq/dnsmasq.cfg01411c.pid
# 或直接给命令
DNS_RELOAD_CMD="/etc/init.d/dnsmasq reload"
```

---

### 日志报「DNS 自愈校验失败」

含义：文件在，但 dnsmasq 没真加载它。检查：

```sh
ps w | grep [d]nsmasq
# 确认 -C 的配置里 conf-dir 是否含 /tmp/dnsmasq.d
# 改对后：
/etc/init.d/dnsmasq restart     # 注意：改 conf-dir 必须 restart，不是 HUP
```

---

### 报 `postrm ... Permission denied / status 126`

早期版本控制脚本权限位不对。先解除僵局再重装：

```sh
chmod 755 /usr/lib/opkg/info/ghacc.postrm
opkg install /tmp/ghacc_x.y.z_all.ipk
```

---

### 报 `Malformed package file`

自己打包时用了 `ar`（Debian 格式）。OpenWrt 的 ipk 是
`gzip(tar(...))`，请用本项目的 `build_ipk.sh`（内部走 `mkipk.py`）。
详见 [ARCHITECTURE.md](ARCHITECTURE.md#九openwrt-ipk-格式打包必读)。

---

## 三、浏览器问题（最容易被误判的一类）

### 现象：Safari 正常，Brave / Chrome 打不开或报证书错误

**这是判别性线索**：两个浏览器走同一套系统解析和网络栈，
所以问题**在浏览器侧**，不在路由器或 hosts。

按顺序检查：

#### 1. 浏览器的 Secure DNS（DoH）会绕过路由器 DNS

必须关掉：

- Brave / Chrome：`设置 → 隐私和安全 → 安全 → 使用安全 DNS` → **关闭**
- Edge：`设置 → 隐私、搜索和服务 → 安全性 → 使用安全 DNS` → **关闭**

验证方法：地址栏进 `brave://net-internals/#dns` 看 github.com 的解析结果，
**应该与系统解析一致**。若显示的是别的东西，说明走了 DoH 或缓存。

#### 2. 清掉浏览器的 DNS 缓存

改了配置后浏览器不会自动跟上：

1. `brave://net-internals/#dns` → **Clear host cache**
2. `brave://net-internals/#sockets` → **Flush socket pools**
3. **完全退出浏览器再重开**（Cmd+Q，不是关窗口）—— 这一步最有效

#### 3. ⚠️ 绝对不要在 `/etc/hosts` 里写 `路由器IP 域名`

这是一个**很容易犯的错**：

```
192.168.2.1    github.com      ← 错误！
```

它的含义不是"把 github.com 交给路由器解析"，而是
**"github.com 的 IP 就是 192.168.2.1"**。

后果：浏览器会去连路由器的 443 端口，拿到路由器自己的
自签证书（如 `CN=QWRT`），于是报 **`ERR_CERT_AUTHORITY_INVALID`**。

**正确做法**：保持 `/etc/hosts` 干净，把**系统 DNS 指向路由器**（通常是默认值）。

#### 4. 代理工具会打架

若同时开着 **Steam++（Watt Toolkit）**、Clash、AdGuard 等会做 MITM 的工具：

- 它们会安装自己的根证书并**替换目标证书**
- 与 ghacc 抢占同一域名，互相干扰
- 表现可能是证书错误、时好时坏、或页面空白

**建议二选一，不要同时启用。**

检查是否装了 MITM 根证书：

```sh
security find-certificate -a -Z /Library/Keychains/System.keychain 2>/dev/null \
  | grep -A1 '"labl"' | grep '"labl"'
# 关注：SteamTools Certificate / Adguard Personal CA 之类
```

---

### 现象：浏览器打开 github.com 只显示一个 `OK`

**这是判据太弱导致的**：某个 IP 上挂着返回 `200` 但正文仅 4 字节 `OK`
的冒牌服务器，被当成可用 IP 写进了 hosts。

v2.4 起已加正文校验、v2.4.4 起改为证书校验，均能挡住。

**应急验证某个 IP 是不是真的**：

```sh
curl --resolve github.com:443:<IP> -o /tmp/x \
     -w '%{http_code} %{size_download} %{ssl_verify_result}\n' https://github.com/
#    size 只有 4（OK）或 1440（Bad request）→ 假的
#    ssl_verify_result 非 0 → 证书不可信，假的
```

---

## 四、卸载

### 一键卸载（推荐）

```sh
ghacc-uninstall
```

七步清理，**幂等，可重复执行**。

### 卸载不干净时（手动兜底）

整段粘到路由器 SSH：

```sh
/etc/init.d/ghacc stop 2>/dev/null; /etc/init.d/ghacc disable 2>/dev/null
for p in $(pgrep -f ghacc-daemon); do kill -9 $p; done

# 摘掉 addn-hosts 文件与 drop-in
rm -f /tmp/ghacc/hosts.addn
rm -f /tmp/dnsmasq.d/ghacc.conf /etc/dnsmasq.d/ghacc.conf

# 摘掉 /etc/hosts 里的标记块（如果写过）
cp -p /etc/hosts /etc/hosts.ghacc.bak.$(date +%Y%m%d-%H%M%S)
awk '/^# GHACC-BEGIN/{f=1;next} /^# GHACC-END/{f=0;next} !f' /etc/hosts > /tmp/h \
  && cp -f /tmp/h /etc/hosts && rm -f /tmp/h

rm -f  /usr/bin/ghacc-daemon /usr/bin/ghacc-uninstall /etc/init.d/ghacc /etc/config/ghacc
rm -rf /etc/ghacc /tmp/ghacc /var/run/ghacc.pid /var/run/ghacc.lock /var/log/ghacc.log
rm -f  /usr/share/rpcd/acl.d/luci-app-ghacc.json
rm -f  /usr/lib/lua/luci/controller/ghacc.lua /usr/lib/lua/luci/model/cbi/ghacc.lua
rm -rf /usr/lib/lua/luci/view/ghacc
rm -f  /tmp/luci-indexcache*; rm -rf /tmp/luci-modulecache

opkg remove ghacc 2>/dev/null
/etc/init.d/rpcd restart 2>/dev/null
# 删了 drop-in 必须 restart（HUP 不会卸载已加载的 addn-hosts）
/etc/init.d/dnsmasq restart 2>/dev/null

echo "--- 验证（应全部无输出）---"
ls /usr/bin/ghacc-daemon /etc/init.d/ghacc 2>&1 | grep -v 'No such'
grep GHACC /etc/hosts; opkg list-installed | grep ghacc; pgrep -f ghacc-daemon
```

### 最坏情况：路由器起不来 / 网络全挂

ghacc **不碰内核、不改防火墙、不改 DHCP**，理论上不可能让路由器起不来。
万一遇到，进 failsafe 模式或 SSH 后执行：

```sh
mount_root
rm -f /tmp/dnsmasq.d/ghacc.conf          # 摘掉 drop-in
awk '/^# GHACC-BEGIN/{f=1;next} /^# GHACC-END/{f=0;next} !f' /etc/hosts > /tmp/h \
  && cp -f /tmp/h /etc/hosts
reboot
```

---

## 五、收集信息提交 Issue

```sh
cat /etc/openwrt_release                          # 固件与版本
uname -m                                           # 架构
ps w | grep [d]nsmasq                              # dnsmasq 启动参数
/etc/init.d/ghacc status                           # 服务状态
cat /tmp/ghacc/hosts.addn                          # 当前条目
nslookup github.com 127.0.0.1                      # dnsmasq 实际返回
tail -30 /var/log/ghacc.log                        # 日志
```

---

## 六、设计上的已知限制

1. **只对走 DNS 的 HTTPS 生效** —— 自解析域名的 App 会绕开。
2. **全部 IP 被封时无能为力** —— 本项目不绕过封锁，只做自动化。
3. **客户端 DoH 必须关闭** —— 否则绕过路由器。
4. **判据是启发式的** —— 挡得住证书不可信/域名不匹配的假 IP，
   挡不住"持有合法证书却返回垃圾内容"的服务器（超出威胁模型）。
5. **内置兜底 IP 池会过期** —— 需自行更新或改用镜像上游。
