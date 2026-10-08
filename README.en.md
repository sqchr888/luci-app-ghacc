<div align="center">

# luci-app-ghacc

**A real-time GitHub accelerator daemon for OpenWrt, with a LuCI web interface**

Give **every device on your LAN** — phones, tablets, computers, TV boxes — access to GitHub
with no client software and no per-device configuration.

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-2.4.5-green.svg)](CHANGELOG.md)
[![Architecture](https://img.shields.io/badge/arch-all-lightgrey.svg)](#4-architecture-compatibility)
[![OpenWrt](https://img.shields.io/badge/OpenWrt-21.02%2B-orange.svg)](#4-architecture-compatibility)

[Features](#2-features) · [Install](#3-installation) · [Compatibility](#4-architecture-compatibility) · [Usage](#5-usage) · [How it works](doc/ARCHITECTURE.md) · [Troubleshooting](doc/TROUBLESHOOTING.md) · [Changelog](CHANGELOG.md) · [Credits](doc/CREDITS.md)

**🌐 English | [简体中文](README.md)**

</div>

---

## 1. What is this?

Accessing GitHub is often unreliable in some regions. The two common workarounds both
have drawbacks:

- **Editing local `hosts` files** — fixes only one machine, and the IPs go stale quickly.
  Constantly hunting for "an IP that isn't blocked yet" is a losing game.
- **Installing an accelerator client** — must be installed and configured on every device,
  which is painful for phones and TV boxes.

**ghacc solves the problem at the LAN level.** It runs persistently on your router:

1. Probes the GitHub IPs currently in use every 15 seconds
2. When one dies, it rescans its candidate pool in parallel and hot-switches within seconds
3. Publishes the result to **every LAN device** through dnsmasq's `addn-hosts`
4. Does all of this via hot reload (SIGHUP) — no network interruption, no service restart

```text
        Phones / Computers / TV boxes
                 │  DNS query
                 ▼
        ┌────────────────────────┐
        │  Router 192.168.x.1    │
        │  ┌──────────────────┐  │
        │  │ dnsmasq          │◄─┼── written by ghacc
        │  │  addn-hosts      │  │    /tmp/ghacc/hosts.addn
        │  └────────┬─────────┘  │
        │           │ SIGHUP     │
        │  ┌────────▼─────────┐  │
        │  │ ghacc-daemon     │  │  probe every 15s
        │  │ health + switch  │  │  rescan when dead
        │  └──────────────────┘  │
        └────────┬───────────────┘
                 ▼
          Working GitHub IPs
```

> **What it does NOT do**: no proxy, no TLS interception, no traffic relaying,
> no telemetry. It simply picks an IP that currently works and tells your LAN about it.
> If every candidate is unreachable, it honestly reports "no available IP" and keeps
> retrying rather than pretending to succeed.

---

## 2. Features

| Feature | Description |
|---|---|
| **Second-level failover** | Persistent probing (15s by default); a dead IP is replaced immediately instead of waiting for the next cron cycle |
| **TLS certificate validation** | Identifies genuine IPs via `ssl_verify_result`, not HTTP status codes — catches fake servers that return `200` with a bogus body |
| **Per-domain validation tiers** | Strict body checks for the `github.com` main site; certificate-only checks for non-web domains (`objects`/`api`/`avatars`), avoiding false negatives |
| **DNS self-healing check** | Periodically queries the local dnsmasq to confirm it actually resolves the IPs we wrote — catches "config present but not loaded" silently broken states |
| **Zero flash writes** | Writes to `/tmp` (tmpfs) instead of `/etc/hosts` — no flash wear over long uptimes |
| **No network interruption** | Hot-reloads dnsmasq with `SIGHUP`; existing connections are not dropped |
| **LuCI web UI** | Under *Services → GitHub Accelerator*: status, entries, live log (refreshed every second), and action buttons |
| **One-command uninstall** | `ghacc-uninstall` — idempotent, seven-step cleanup |
| **Pure script** | Daemon is busybox `ash`, UI is Lua — **no cross-compilation needed**, `Architecture: all` |

---

## 3. Installation

### Option A: prebuilt package (recommended)

Download `ghacc_x.y.z_all.ipk` from [Releases](../../releases):

```sh
scp ghacc_2.4.5_all.ipk root@192.168.2.1:/tmp/
ssh root@192.168.2.1 "opkg install /tmp/ghacc_2.4.5_all.ipk"
```

> Replace `192.168.2.1` with your router's address.

Then open LuCI: **Services → GitHub Accelerator**.

### Option B: install directly on the router (no PC needed)

SSH into your router and paste **any one** of the following.

#### B-a. One-liner, latest version (recommended)

```sh
cd /tmp && curl -fsSL https://raw.githubusercontent.com/sqchr888/luci-app-ghacc/main/install.sh | sh
```

> This fetches the installer from the repository and runs it. The script performs a
> pre-flight check, then downloads and installs the latest release automatically.

#### B-b. Specific version / straight from Releases

```sh
cd /tmp && curl -fsSL -o ghacc.ipk \
  https://github.com/sqchr888/luci-app-ghacc/releases/latest/download/ghacc_2.4.5_all.ipk \
  && opkg install ghacc.ipk
```

#### B-c. Fetch the full source tree, then install

```sh
cd /tmp && rm -rf luci-app-ghacc
curl -fsSL https://github.com/sqchr888/luci-app-ghacc/archive/refs/heads/main.tar.gz \
  | tar xz && mv luci-app-ghacc-main luci-app-ghacc
sh /tmp/luci-app-ghacc/install.sh
```

> If your router has `git` installed, you can also use:
> ```sh
> cd /tmp && git clone --depth 1 https://github.com/sqchr888/luci-app-ghacc.git
> sh /tmp/luci-app-ghacc/install.sh
> ```

The install script runs a pre-flight check (firmware / architecture / curl version /
dnsmasq instances / free overlay space) before installing, syntax-checking, and starting.

> **Note**: if `raw.githubusercontent.com` or `github.com` is unreachable on your line,
> you're in a block window — retry later, or use Option A to upload the `.ipk` from your
> computer (which may have a proxy available).

### Dependencies

| Dependency | Notes |
|---|---|
| `curl` | **Required.** Must support `--resolve` and `-w '%{ssl_verify_result}'` (any 7.5x+ build works) |
| `ca-certificates` | **Required** for certificate verification |
| `dnsmasq` / `dnsmasq-full` | **Required** as the DNS server |
| `luci-base` / `rpcd` | Only for the web UI; the CLI works without them |

---

## 4. Architecture compatibility

**This package is `Architecture: all`** — the daemon is pure shell (busybox `ash`) and the
UI is pure Lua, with **no precompiled binaries**. It should therefore install and run on
**any** OpenWrt architecture:

`x86_64` · `aarch64_cortex-a53/a72` · `arm_cortex-a7/a9` · `mips_24kc` · `mipsel_24kc` ·
`mips64el` · `riscv64` · `i386_pentium4` …

### But please read this table honestly

| Platform | Status | Notes |
|---|---|---|
| **QWRT 25.12.2 (ipq95xx / aarch64_cortex-a53)** | ✅ **Verified on hardware** | The maintainer's own environment. Includes QSDK multi-instance dnsmasq, dnsmasq-full 2.92 |
| Official OpenWrt 21.02 / 22.03 / 23.05 / 24.10 | ⚠️ Should work, **untested** | Uses the standard `addn-hosts` mechanism |
| ImmortalWrt / Lean builds / other third-party | ⚠️ Should work, **untested** | If the firmware relocates dnsmasq's config path, adjust `DNSMASQ_CONFDIR` |
| Very old releases (≤ 19.07) | ❌ Not supported | `procd` and LuCI differ significantly |

> **Why can't we promise universal compatibility?** Because firmware differs in how it
> launches dnsmasq. The core assumption here is "dnsmasq loads `/tmp/dnsmasq.d/*.conf`
> via `conf-dir`". You must verify this once (see below). **If your firmware differs,
> just point the config at the right path — no code changes required.**
>
> Issues reporting your firmware and architecture are very welcome; verified results
> get added to the table above.

### Three things to check after installing

```sh
# 1) Find dnsmasq's real config file and its conf-dir
ps w | grep [d]nsmasq
#    Look at the path after -C (e.g. /var/etc/dnsmasq.conf.cfg01411c),
#    then grep for conf-dir and addn-hosts to see which directories it loads

# 2) Confirm the daemon is running and has selected IPs
/etc/init.d/ghacc status
cat /tmp/ghacc/hosts.addn

# 3) [MOST IMPORTANT] Confirm dnsmasq actually returns the IPs we wrote
nslookup github.com 127.0.0.1
#    The answer should match the contents of hosts.addn —
#    not whatever your ISP's DNS would say
```

Step 3 is the decisive one. **"The file looks right" does not mean "resolution works."**
See the [Changelog](CHANGELOG.md) entry for v2.3.0 for why this distinction matters.

---

## 5. Usage

### LuCI web interface

Menu: **Services → GitHub Accelerator**

- **Status page**
  - Daemon state, autostart, number of active IPs
  - Start / Stop / Restart / Force rescan IPs / Clear log
    (buttons grey out automatically based on daemon state)
  - Table of currently active entries
  - Last 200 log lines, **auto-refreshed every second** (dark theme; scrolling up to
    read history won't yank you back to the bottom)
- **Settings page**
  - Probe interval, timeout, IPs per domain, cooldown, concurrency, managed domains
  - Automatic log cleanup toggle + retention days (default: 3)

### Command line

```sh
/etc/init.d/ghacc status      # state + currently active IPs
/etc/init.d/ghacc restart
/etc/init.d/ghacc stop        # stops and removes the marker block
/etc/init.d/ghacc disable

tail -f /var/log/ghacc.log    # live log
logread | grep ghacc
```

The first log lines are an **environment self-check** — read them first when debugging:

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

> Log messages are in Chinese. The key ones:
> `切换 <domain> → <ip>` = switched to a new IP;
> `已更新 ... 并热加载 dnsmasq` = file updated and dnsmasq hot-reloaded;
> `无可用 IP` = no reachable candidate right now (normal during a full block window).

### Uninstalling

```sh
ghacc-uninstall              # recommended: seven-step cleanup, idempotent
```

Manual fallback procedures are in [doc/TROUBLESHOOTING.md](doc/TROUBLESHOOTING.md).

---

## 6. Configuration

Config file: `/etc/ghacc/ghacc.conf` (or edit via LuCI, which regenerates it on save)

### Probing and switching

| Option | Default | Description |
|---|---|---|
| `CHECK_INTERVAL` | 15 | Health probe interval (seconds) |
| `PROBE_TIMEOUT` | 3 | Per-IP probe timeout; use 4–5 on weak routers |
| `MAX_IPS` | 2 | IPs written per domain; 1–2 recommended |
| `FAIL_THRESHOLD` | 2 | Consecutive failures before declaring an IP dead |
| `COOLDOWN` | 120 | Cooldown after a switch (seconds), prevents flapping storms |
| `CONCURRENCY` | 8 | Parallel probes, hard cap 16 |
| `MAX_CANDIDATES` | 24 | Max candidates probed per domain |

### Health validation

| Option | Default | Description |
|---|---|---|
| `STRICT_MAIN_SITE` | 1 | Extra body validation for the `github.com` main site |
| `STRICT_API` | 1 | **v2.4.5** Validate that `api.github.com` returns JSON — catches IPs with a valid cert but the wrong service |
| `MIN_BODY_SIZE` | 5000 | Minimum body size for the main site (bytes) |
| `BODY_MARKER` | github | Required substring in the main site's body |

### DNS and output

| Option | Default | Description |
|---|---|---|
| `ADDN_HOSTS` | `/tmp/ghacc/hosts.addn` | **The file dnsmasq actually reads** |
| `DNSMASQ_CONFDIR` | `/tmp/dnsmasq.d` | Directory for the drop-in config |
| `WRITE_ETC_HOSTS` | 0 | Also write `/etc/hosts` (for older firmware) |
| `DNSMASQ_PID` | empty | dnsmasq pid path; empty = auto-detect |
| `DNS_RELOAD_CMD` | empty | Custom reload command; empty = auto |

### Resource protection

| Option | Default | Description |
|---|---|---|
| `MIN_WRITE_INTERVAL` | 60 | Minimum interval between writes (seconds), **protects flash** |
| `SELFCHECK_INTERVAL` | 300 | Minimum interval for DNS self-healing check (seconds) |
| `AUTO_CLEAN_LOG_DAYS` | 3 | Log retention in days; `0` disables age-based cleanup |
| `MAX_LOG` | 200 | Maximum log lines |
| `CYCLE_GUARD` | 300 | Slow-cycle warning threshold (seconds) |

Fully commented version: [`ghacc.conf`](ghacc.conf) (Chinese comments).

---

## 7. FAQ

<details>
<summary><b>How is this different from a cron job that refreshes hosts?</b></summary>

| | cron refresh | ghacc |
|---|---|---|
| Trigger | Only on schedule | Always running, probes every 15s |
| After an IP dies | Waits for the next cycle | Replaced within seconds |
| Scope of probing | Full rescan | Only checks what's in use |
| How it takes effect | Restarts dnsmasq (drops connections) | `SIGHUP` hot reload (no interruption) |

</details>

<details>
<summary><b>Will it crash my router or wear out the flash?</b></summary>

**It cannot crash the kernel** — a userspace shell loop can't panic a kernel. But there are
four real risks, all mitigated:

| Risk | Mitigation |
|---|---|
| Flash wear (the real one) | `MIN_WRITE_INTERVAL=60` + dirty-flag coalescing; writes go to `/tmp` tmpfs, so **actual flash writes are zero** |
| Flapping storms | An IP is only declared dead after `FAIL_THRESHOLD` consecutive failures; `COOLDOWN` suppresses rescans after a switch |
| Runaway processes | Concurrency capped at 16, candidate list truncated, `ulimit -c 0 -f 4096` |
| Concurrent writes | Atomic `mkdir` lock with PID liveness check (stale locks are taken over in place) |

Writes use "write temp file → atomic `mv`", so being killed mid-write never leaves a
partial file. `procd respawn` has a retry cap, so there's no infinite restart storm.

</details>

<details>
<summary><b>The log keeps saying "no available IP" — what now?</b></summary>

**This is usually not a malfunction.** If every candidate is unreachable at that moment
(a "full block window"), the daemon can't do anything but report honestly and keep
retrying until the network changes.

**How to judge correctly**: don't ask "can I open GitHub?", ask
**"is the IP it wrote being returned correctly by dnsmasq?"**

```sh
cat /tmp/ghacc/hosts.addn        # what it selected
nslookup github.com 127.0.0.1    # what dnsmasq actually returns
```

If they match, it's working (the failure is a block window). If they differ, that's a real
problem worth investigating.

</details>

<details>
<summary><b>The browser still can't open it, or reports a certificate error?</b></summary>

Check these in order:

1. **Browser Secure DNS (DoH) bypasses your router's DNS** — it must be disabled.
   (Chrome/Brave: `Settings → Privacy and security → Security → Use secure DNS` → off)
2. **Never put `router-ip domain` in `/etc/hosts`** — that means "this domain's IP *is*
   the router", which makes the browser connect to the router and fail certificate
   validation. Keep `hosts` clean and point your system DNS at the router instead.
3. **Proxy tools conflict** — tools that perform MITM (Steam++, Clash, AdGuard, …)
   install their own root CA and will hijack the same domains. Don't run them at the
   same time as ghacc.

See [doc/TROUBLESHOOTING.md](doc/TROUBLESHOOTING.md) for the full guide (Chinese).

</details>

<details>
<summary><b>Where do the candidate IPs come from? Is anyone maintaining them?</b></summary>

Four sources, **only the first is actively maintained**:

| Source | Maintenance |
|---|---|
| [`raw.hellogithub.com/hosts`](https://github.com/521xueweihan/GitHub520) | ✅ Actively maintained by the **GitHub520** project |
| Alibaba / Tencent DoH | ✅ Live resolution, but only returns whatever upstream DNS says |
| Built-in `GH_POOL` / `FASTLY_POOL` | ❌ **Hardcoded static snapshot, unmaintained — fallback only** |

Fresh sources get priority for the `MAX_CANDIDATES` slots; the fallback pool only fills
what's left. See [doc/CREDITS.md](doc/CREDITS.md).

</details>

---

## 8. Known limitations

1. **It finds "IPs that aren't blocked yet" — it does not circumvent blocking.**
   If every candidate is unreachable, it can't help; it retries until the network changes.
2. **Only affects HTTPS that goes through DNS** — apps that resolve names themselves will
   bypass it.
3. **The health check is heuristic, not cryptographic.** It relies on TLS certificate
   validation, which catches IPs with untrusted certificates or mismatched names. It
   cannot catch a server holding a *legitimate* certificate for that domain that returns
   junk (that would require the attacker to obtain a CA-signed cert for the domain —
   outside the "hijacked IP" threat model).
4. **The built-in fallback IP pool will go stale** — update it or point `POOL_URL` at a mirror.
5. **Only verified on QWRT.** For other firmware, run the "three things to check" above.

---

## 9. Development and packaging

The project is pure shell + Lua — **no cross-compilation required**.

```sh
# Option 1: build the ipk locally (macOS / Linux)
sh build_ipk.sh
#   → dist/ghacc_<version>_all.ipk

# Option 2: OpenWrt SDK / buildroot
#   Place this directory under package/, then:
make package/luci-app-ghacc/compile V=s
```

> **Two packaging pitfalls** (both handled by the scripts):
> 1. OpenWrt's `.ipk` is **not** the Debian `ar` format. It is
>    `gzip(tar(./debian-binary, ./control.tar.gz, ./data.tar.gz))`.
>    Building it with the system `ar` produces `Malformed package file`.
> 2. macOS `bsdtar` injects `._xxx` / `.DS_Store` entries; use `COPYFILE_DISABLE=1`.

### Project layout

```text
luci-app-ghacc/
├── ghacc-daemon            Main daemon (busybox ash)  → /usr/bin/ghacc-daemon
├── ghacc.init              procd init script          → /etc/init.d/ghacc
├── ghacc.conf              Daemon config (commented)  → /etc/ghacc/ghacc.conf
├── install.sh              Source install script
├── uninstall.sh            One-command uninstall      → /usr/bin/ghacc-uninstall
├── build_ipk.sh            Packaging script
├── mkipk.py                OpenWrt-native ipk builder (not Debian ar)
├── Makefile                OpenWrt SDK build file
├── doc/
│   ├── ARCHITECTURE.md     Design and data flow
│   ├── TROUBLESHOOTING.md  Troubleshooting guide
│   └── CREDITS.md          Third-party resources and acknowledgements
├── pkg/
│   ├── control/            control / conffiles / postinst / prerm / postrm
│   └── root/               LuCI UI + UCI config (target rootfs layout)
└── dist/                   Build output
```

> Note: the source code and in-code comments are in Chinese, as the project originated in
> a Chinese-speaking context. Contributions translating comments are welcome.

---

## 10. Contributing

Issues and pull requests are welcome — especially:

- **Reporting whether it works on your firmware and architecture** — results get added to
  the [compatibility table](#4-architecture-compatibility)
- Reporting firmware where dnsmasq's config path differs (include the output of
  `ps w | grep [d]nsmasq`)
- Improving the health validation logic or adding candidate IP sources

When filing an issue, please include:

```sh
cat /etc/openwrt_release                          # firmware and version
uname -m                                           # architecture
ps w | grep [d]nsmasq                              # dnsmasq launch arguments
/etc/init.d/ghacc status                           # service state
tail -30 /var/log/ghacc.log                        # log
```

---

## 11. License

[MIT](LICENSE)

This project references third-party resources (GitHub520 and others); copyright belongs to
their respective authors. See [doc/CREDITS.md](doc/CREDITS.md).

> **Disclaimer**: This software is provided "as is", without warranty of any kind.
> Evaluate the risks yourself and test on a non-critical device first. The authors are not
> liable for any damage caused by using this software.
