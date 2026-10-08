# ghacc v2.4.4

A real-time GitHub accelerator daemon for OpenWrt, with a LuCI web interface.
Give **every device on your LAN** — phones, computers, TV boxes — access to GitHub
with no client software and no per-device configuration.

> Pure shell + Lua, `Architecture: all` — **works on any architecture**, no cross-compilation.

---

## 📦 Installation

```sh
# After downloading the .ipk from the assets below
scp ghacc_2.4.4_all.ipk root@192.168.2.1:/tmp/
ssh root@192.168.2.1 "opkg install /tmp/ghacc_2.4.4_all.ipk"
```

Then open LuCI: **Services → GitHub Accelerator**

**Dependencies**: `curl`, `ca-certificates`, `dnsmasq` (or `dnsmasq-full`)

### Verify your download

```sh
sha256sum ghacc_2.4.4_all.ipk
# Expected:
# f50274b4e762c41da061a9cd8a84ea15184975747ca22fe9cbd26bfdff149ee2
```

---

## ✨ Highlights in this release

### Fixed: health check was rejecting non-web domains

Some managed domains (`objects.githubusercontent.com`, `avatars.githubusercontent.com`,
`api.github.com`) always return 404 or a tiny body on their root path — that has nothing
to do with the IP being good, but the old check kept marking them unusable and the log
filled with "no available IP".

**Now validation is based on the TLS certificate**:

```
curl exit code == 0  AND  ssl_verify_result == 0  →  pass
```

Genuine GitHub IPs present a CA-signed certificate matching the domain; fake IPs either
have an untrusted chain or a mismatched name. **404 / 302 / empty bodies all happen
after TLS completes, so they no longer affect the verdict.**

### Fixed: probe request method

Some domains (e.g. `objects.githubusercontent.com`) **do not answer `HEAD` requests**
and hang until timeout. Switched to `curl -r 0-0` (GET, first byte only) to avoid
discarding perfectly good IPs.

### Improved: candidate pool priority

Among the candidate sources, GitHub520 and DoH are actively maintained/live, while the
built-in IP pools are static snapshots. Previously all three were merged and truncated
lexicographically, letting stale IPs crowd out fresh ones. Now **fresh sources get
priority**, and the built-in pools only fill the remaining slots.

---

## 🔧 Key features

| Feature | Description |
|---|---|
| **Second-level failover** | Persistent probing (15s default); dead IPs replaced immediately |
| **TLS certificate validation** | Identifies genuine IPs via `ssl_verify_result`, not HTTP status |
| **Per-domain validation tiers** | Strict body checks for the main site; certificate-only for non-web domains |
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
3. Validation relies on TLS certificates — it catches untrusted/mismatched certs, but not
   a server holding a *legitimate* certificate for the domain that returns junk
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
