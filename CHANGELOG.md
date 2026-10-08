# 更新记录

本项目遵循[语义化版本](https://semver.org/lang/zh-CN/)。

---

## [2.4.4] - 2026-10-08

### 修复

- **健康判据误杀非网页域名**：部分受管域名（如 `objects.githubusercontent.com`、
  `avatars.githubusercontent.com`、`api.github.com`）访问根路径必然返回 404 或
  极短正文，导致被旧判据持续判为不可用。
  现改为**以 TLS 证书为准**（`curl` 退出码为 0 且 `ssl_verify_result` 为 0），
  不再依赖 HTTP 状态码与正文长度。
- **探测请求方式**：部分域名不响应 `HEAD` 请求，改用 `curl -r 0-0`
  （GET 且只取首个字节），避免误判。

### 改进

- **候选池优先级**：新鲜来源（GitHub520 / DoH）优先占用 `MAX_CANDIDATES` 名额，
  内置兜底池仅补足剩余位置，不再因字典序截断而挤掉新鲜 IP。
- 对 `github.com` 主站保留正文校验（`STRICT_MAIN_SITE`）作为双保险。

---

## [2.4.3] - 2026-10-08

### 修复

- **清理日志后页面报错**：日志为空时触发了未定义的翻译函数调用，
  导致页面返回 `Runtime error`。已移除该调用。

---

## [2.4.2] - 2026-10-08

### 新增

- **清理日志按钮**：位于「强制重扫 IP」右侧，带二次确认。
- **日志自动清理开关**（参数设置页）：按天数自动删除过期日志行，默认保留 3 天。

### 修复

- **条目表格对齐**：表头与单元格统一左对齐。
- **输入框宽度**：数值输入框收窄并与左侧标签左对齐。
- **配置保存完整性**：在 LuCI 界面保存后，生成的配置不再丢失
  `ADDN_HOSTS`、`WRITE_ETC_HOSTS`、`SELFCHECK_*` 等关键项。
- **资源文件权限**：打包时强制归一化 LuCI 资源文件权限为 644，
  避免部分固件下界面样式不生效。

---

## [2.4.1] - 2026-10-08

### 修复

- **操作按钮未反映运行状态**：现按状态自动置灰/高亮
  （运行中时「启动」不可点，「停止」可用；已停止时相反）。
- **条目不显示**：界面改为读取守护进程实际写入的
  `/tmp/ghacc/hosts.addn`（此前读的是 `/etc/hosts`），并区分
  「未运行」与「运行中但当前无可用 IP」两种状态。
- **日志区域可读性与刷新**：修正配色（深底浅字），
  新增独立轮询端点，日志每秒自动刷新。

---

## [2.4.0] - 2026-10-08

### 新增

- **DNS 自愈校验**：定期反问本机 dnsmasq 一个探针域名，确认返回的地址
  包含我们写入的 IP。用于发现「配置存在但未实际加载」的情况，
  不符时自动重建并重载。兼容 busybox 与 BSD 两种 `nslookup` 输出格式。

### 修复

- **健康判据加强**：由「HTTP 状态码非 000」升级为
  「状态码 2xx/3xx + 正文体积下限 + 正文特征串」三重校验，
  可识别返回 200 但正文异常的无效节点。
  `probe()` 与 `current_ok()` 共用同一判据。

---

## [2.3.0] - 2026-10-07

### 变更（重要）

- **改用 dnsmasq 的 `addn-hosts` 机制输出**：
  QWRT / QSDK 等固件的 dnsmasq 实际并不读取 `/etc/hosts`，
  而是通过 `conf-dir` 加载配置。现在写入
  `ADDN_HOSTS=/tmp/ghacc/hosts.addn`，并在 `DNSMASQ_CONFDIR`
  放置 drop-in 完成注册。
- **闪存零写入**：输出文件位于 `/tmp`（内存盘），
  默认不再写入 `/etc/hosts`（`WRITE_ETC_HOSTS=0`）。
- drop-in 新建或变更后需完整 `restart` dnsmasq（`conf-dir` 仅在启动时读取），
  日常更新走 SIGHUP 热加载。

---

## [2.2.2] - 2026-10-07

### 修复

- **升级失败导致服务停用**：`prerm` 现在区分 upgrade 与 remove，
  升级时只停止服务、不取消开机自启，避免升级中断后服务永久失效。

---

## [2.2.1] - 2026-10-07

### 修复

- **控制脚本权限位**：打包前强制为 `postinst`/`prerm`/`postrm` 设置执行权限，
  并在打包后回读 ipk 校验，避免安装时报 `status 126`。

---

## [2.2.0] - 2026-10-07

### 修复

- **固件预置条目的干扰**：部分固件出厂在 hosts 中预置了同名条目且位置靠前，
  会覆盖我们写入的 IP。现会自动摘除标记块之外的同名条目。
- **新增每轮一致性校验**：配置被外部改写时自动补回。

---

## [2.1.0] - 2026-10-07

### 新增

- **QWRT / QSDK 适配**：`reload_dns()` 优先使用 `killall -HUP dnsmasq`
  以覆盖多实例环境，并提供 pid 文件与 init 脚本两级兜底。
- **一键卸载**：新增 `ghacc-uninstall`，七步清理，幂等可重复执行。
- 写入与热加载解耦：热加载失败不再反复重写输出文件。

---

## [2.0.0] - 2026-10-07

### 新增

- **资源保护机制**（四项）：

  | 风险 | 防护 |
  |---|---|
  | 闪存磨损 | `MIN_WRITE_INTERVAL` 节流 + 脏标记合并写入 |
  | 抖动风暴 | 连续失败阈值判定 + 切换冷却期 |
  | 进程失控 | 并发上限、候选池截断、`ulimit` 限制 |
  | 并发写入 | `mkdir` 原子锁 + PID 存活检测 |

- **LuCI 管理界面**：运行状态页（状态、条目、日志、四个操作按钮）与参数设置页。
- **ipk 打包**：`build_ipk.sh` + `mkipk.py`
  （输出 OpenWrt 原生格式：`gzip(tar(debian-binary, control.tar.gz, data.tar.gz))`）。

---

## [1.0.0] - 2026-10-07

### 新增

- 首个版本。`ghacc-daemon` 守护进程（busybox ash，仅依赖 `curl --resolve`）
  与 procd 启动脚本。
- 核心机制：常驻循环探测在用 IP，失效时并行重扫候选池，
  重写输出文件后 SIGHUP 热加载 dnsmasq。

---

## 项目定位

本项目**不绕过网络封锁**，而是把「持续发现可用 IP 并同步给整个局域网」这件事
自动化到极致：常驻探测、秒级切换、热加载不断网、零闪存写入。

若某时刻所有候选 IP 均不可达，守护进程会如实报告并持续重试，
待网络环境变化后自动恢复。

---

[2.4.4]: https://github.com/sqchr888/luci-app-ghacc/releases/tag/v2.4.4
[2.4.3]: https://github.com/sqchr888/luci-app-ghacc/releases/tag/v2.4.3
[2.4.2]: https://github.com/sqchr888/luci-app-ghacc/releases/tag/v2.4.2
[2.4.1]: https://github.com/sqchr888/luci-app-ghacc/releases/tag/v2.4.1
[2.4.0]: https://github.com/sqchr888/luci-app-ghacc/releases/tag/v2.4.0
[2.3.0]: https://github.com/sqchr888/luci-app-ghacc/releases/tag/v2.3.0
[2.2.2]: https://github.com/sqchr888/luci-app-ghacc/releases/tag/v2.2.2
[2.2.1]: https://github.com/sqchr888/luci-app-ghacc/releases/tag/v2.2.1
[2.2.0]: https://github.com/sqchr888/luci-app-ghacc/releases/tag/v2.2.0
[2.1.0]: https://github.com/sqchr888/luci-app-ghacc/releases/tag/v2.1.0
[2.0.0]: https://github.com/sqchr888/luci-app-ghacc/releases/tag/v2.0.0
[1.0.0]: https://github.com/sqchr888/luci-app-ghacc/releases/tag/v1.0.0
