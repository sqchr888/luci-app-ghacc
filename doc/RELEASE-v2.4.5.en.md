# ghacc v2.4.5

A real-time GitHub accelerator daemon for OpenWrt, with a LuCI web interface.
Give **every device on your LAN** — phones, computers, TV boxes — access to GitHub
with no client software and no per-device configuration.

> Pure shell + Lua, `Architecture: all` — **works on any architecture**, no cross-compilation.

---

## 📦 Installation

### Install directly on the router (no PC needed)

```sh
cd /tmp && curl -fsSL https://raw.githubusercontent.com/sqchr888/luci-app-ghacc/main/install.sh | sh
```

Or install the `.ipk` from the assets below:

```sh
scp ghacc_2.4.5_all.ipk root@192.168.2.1:/tmp/
ssh root@192.168.2.1 "opkg install /tmp/ghacc_2.4.5_all.ipk"
```

Then open LuCI: **Services → GitHub Accelerator**

**Dependencies**: `curl`, `ca-certificates`, `dnsmasq` (or `dnsmasq-full`)

### Verify your download

```sh
sha256sum ghacc_2.4.5_all.ipk
# Expected:
# cdd426dd8dffb56101bd4f5ea36127f1c6898f33e02459c984d2151a2644a774
```

---

## ✨ Highlights in this release

### Fixed: IPs with a valid certificate but the wrong service were treated as healthy

GitHub's subdomains share a single `*.github.com` wildcard certificate, so "certificate
validates" only proves **the peer is some GitHub server** — it does *not* prove it serves
**the service that subdomain is supposed to provide**.

Real-world case: `api.github.com` was being resolved to an IP whose certificate validated
perfectly (`ssl_verify_result=0`) but which does not serve the API — its root path returns
a 301 redirect to `github.com`. Every tool depending on `api.github.com` (`gh` CLI, CI,
various clients) failed, while the daemon considered that IP healthy.

Domains whose "correct response" can be defined now get an extra service check:
**`api.github.com` must return 200 with a JSON body**. New toggle: `STRICT_API`.

### New: one-command install on the router

```sh
cd /tmp && curl -fsSL https://raw.githubusercontent.com/sqchr888/luci-app-ghacc/main/install.sh | sh
```

The script auto-detects its mode: when piped it performs an online install (preferring the
release `.ipk`, falling back to downloading the source tarball); when a source tree is
present alongside it, it installs from local source.

### Fixed: source installs now include the LuCI interface

Previously the source path installed only the CLI parts, so the LuCI menu never appeared.
It now installs the interface files and UCI config, with permissions normalized
(LuCI resources must be 644).

---

## 🔧 Key features

| Feature | Description |
|---|---|
| **Second-level failover** | Persistent probing (15s default); dead IPs replaced immediately |
| **TLS certificate validation** | Identifies genuine IPs via `ssl_verify_result`, not HTTP status |
| **Per-domain validation tiers** | Main site: body checks; API: JSON check; non-web domains: certificate only |
| **DNS self-healing check** | Periodically verifies the local dnsmasq actually resolves our IPs |
| **Zero flash writes** | Writes to `/tmp` tmpfs — no flash wear |
| **No network interruption** | `SIGHUP` hot reload of dnsmasq |
| **LuCI UI** | Status, entries, live log (1s refresh), action buttons |
| **One-command uninstall** | `ghacc-uninstall`, idempotent |

---

## ⚠️ Architecture compatibility

This package is `Architecture: all` — pure shell + Lua with no precompiled binaries, so it
**should run on any OpenWrt architecture**.

| Platform | Status |
|---|---|
| **QWRT 25.12.2 (ipq95xx / aarch64_cortex-a53)** | ✅ Verified on hardware |
| Official OpenWrt 21.02 – 24.10 | ⚠️ Should work, untested |
| ImmortalWrt / Lean builds | ⚠️ Should work, untested |
| ≤ 19.07 | ❌ Not supported |

> Firmware differs in where dnsmasq keeps its config. This project assumes dnsmasq loads
> `/tmp/dnsmasq.d/*.conf` via `conf-dir` — **please verify once after installing**.

### Three checks after installing

```sh
# 1) Find dnsmasq's real config path
ps w | grep [d]nsmasq

# 2) Confirm the daemon is running and has selected IPs
/etc/init.d/ghacc status
cat /tmp/ghacc/hosts.addn

# 3) [MOST IMPORTANT] Confirm dnsmasq actually returns the IPs we wrote
nslookup github.com 127.0.0.1
```

Step 3 is decisive: **"the file looks right" does not mean "resolution works."**

---

## 📌 Known limitations

1. **It finds "IPs that aren't blocked yet" — it does not circumvent blocking.**
   If all candidates are unreachable, it reports honestly and keeps retrying.
2. Only affects HTTPS that goes through DNS; apps resolving names themselves bypass it.
3. Validation relies on TLS certificates plus per-domain service checks. It catches
   untrusted/mismatched certs and wrong services on checked domains, but not a server
   holding a legitimate certificate for an unchecked domain that returns junk
   (outside the "hijacked IP" threat model).
4. **Browser Secure DNS (DoH) bypasses the router's DNS** and must be disabled.
5. The built-in fallback IP pool will go stale; update it when needed.

---

## 📖 Documentation

- [README (English)](https://github.com/sqchr888/luci-app-ghacc/blob/main/README.en.md)
- [README（中文）](https://github.com/sqchr888/luci-app-ghacc/blob/main/README.md)
- [How it works](https://github.com/sqchr888/luci-app-ghacc/blob/main/doc/ARCHITECTURE.md)
- [Troubleshooting](https://github.com/sqchr888/luci-app-ghacc/blob/main/doc/TROUBLESHOOTING.md)
- [Full changelog](https://github.com/sqchr888/luci-app-ghacc/blob/main/CHANGELOG.md)

---

## 🙏 Credits

Candidate IP data comes primarily from the [GitHub520](https://github.com/521xueweihan/GitHub520)
project — thanks for maintaining it. See [CREDITS](https://github.com/sqchr888/luci-app-ghacc/blob/main/doc/CREDITS.md).

---

**Full changes**: [CHANGELOG.md](https://github.com/sqchr888/luci-app-ghacc/blob/main/CHANGELOG.md)
