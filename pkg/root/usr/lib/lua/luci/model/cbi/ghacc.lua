-- LuCI CBI model for ghacc-daemon
-- 安装位置: /usr/lib/lua/luci/model/cbi/ghacc.lua
-- 作用: 编辑 UCI 配置 /etc/config/ghacc，保存后生成守护进程读的 shell 配置并重启服务

local sys = require "luci.sys"

m = Map("ghacc", translate("GitHub 加速"),
        translate("常驻守护进程：定期探测 GitHub 各域名的可用 IP，失效时自动热切换。" ..
                  "修改后会自动重启服务。"))

s = m:section(NamedSection, "main", "ghacc", translate("守护进程参数"))
s.anonymous = false
s.addremove = false

-- 数值输入框收窄。
-- LuCI 各主题默认把 .cbi-input-text 设为 100% 宽；option.size 只写 size
-- 属性，会被主题的 CSS 宽度覆盖，所以还要注入一段限宽 CSS。
-- 见 view/ghacc/cbi_style.htm（选择器 #cbi-ghacc-main 只作用于本页）。
m:append(Template("ghacc/cbi_style"))

-- o.size 作为双保险：在不受 CSS 影响的主题里也能收窄。
local function narrow(o, width)
    o.size = width or 6
    return o
end

o = s:option(Flag, "enabled", translate("启用服务"),
             translate("关闭后守护进程停止，hosts 标记块会被清除"))
o.default  = "1"
o.rmempty  = false

o = s:option(Value, "check_interval", translate("健康探测间隔（秒）"),
             translate("越小切换越快，但请求越频繁。默认 15"))
o.datatype = "uinteger"
o.default  = "15"
narrow(o)

o = s:option(Value, "probe_timeout", translate("单 IP 探测超时（秒）"),
             translate("路由器性能弱可调到 4~5。默认 3"))
o.datatype = "uinteger"
o.default  = "3"
narrow(o)

o = s:option(Value, "max_ips", translate("每域名写入 IP 数"),
             translate("建议 1~2。写太多死 IP 会拖慢连接。默认 2"))
o.datatype = "uinteger"
o.default  = "2"
narrow(o)

o = s:option(Value, "cooldown", translate("切换冷却期（秒）"),
             translate("同一域名切换后多久内不再重扫，防抖动风暴。默认 120"))
o.datatype = "uinteger"
o.default  = "120"
narrow(o)

o = s:option(Value, "min_write_interval", translate("hosts 最小写入间隔（秒）"),
             translate("保护路由器闪存，抖动时多次切换会合并成一次写入。默认 60"))
o.datatype = "uinteger"
o.default  = "60"
narrow(o)

o = s:option(Value, "concurrency", translate("并发探测数"),
             translate("硬上限 16。弱路由建议 4。默认 8"))
o.datatype = "uinteger"
o.default  = "8"
narrow(o)

o = s:option(Value, "max_candidates", translate("每域名最多探测候选数"),
             translate("限制单轮 fork 总数。默认 24"))
o.datatype = "uinteger"
o.default  = "24"
narrow(o)

o = s:option(TextValue, "domains", translate("守护域名"),
             translate("空格分隔。删掉你用不到的域名可以显著降低开销"))
o.rows = 4
o.wrap = "soft"

-- ---- v2.4.2 新增：日志自动清理 ----
o = s:option(Flag, "auto_clean_log", translate("自动清理日志"),
             translate("按下面的天数自动删除过期日志行，避免日志无限增长。" ..
                       "关闭后仅按行数上限滚动（最多保留 200 行）。"))
o.default  = "1"
o.rmempty  = false

o = s:option(Value, "log_keep_days", translate("日志保留天数"),
             translate("超过该天数的日志行会被自动删除。默认 3。仅在" ..
                       "「自动清理日志」开启时生效。"))
o.datatype    = "uinteger"
o.default     = "3"
narrow(o)
o:depends("auto_clean_log", "1")

-- 保存后：把 UCI 值写成守护进程实际读取的 shell 配置
function m.on_commit(map)
    local uci = require("luci.model.uci").cursor()

    local function g(k, d)
        local v = uci:get("ghacc", "main", k)
        if v == nil or v == "" then v = d end
        return tostring(v)
    end

    -- 开关关闭时把天数写成 0，守护进程据此跳过按天清理
    local keep_days = "0"
    if g("auto_clean_log", "1") == "1" then
        keep_days = g("log_keep_days", 3)
    end

    local f = io.open("/etc/ghacc/ghacc.conf", "w")
    if f then
        f:write("# 由 LuCI 自动生成，勿手动编辑 —— 改这里请在 Web 界面改\n")
        f:write("DOMAINS=\"" .. g("domains",
            "github.com api.github.com codeload.github.com gist.github.com " ..
            "raw.githubusercontent.com gist.githubusercontent.com " ..
            "objects.githubusercontent.com avatars.githubusercontent.com") .. "\"\n")
        f:write("CHECK_INTERVAL="   .. g("check_interval", 15)   .. "\n")
        f:write("PROBE_TIMEOUT="    .. g("probe_timeout", 3)     .. "\n")
        f:write("MAX_IPS="          .. g("max_ips", 2)           .. "\n")
        f:write("COOLDOWN="         .. g("cooldown", 120)        .. "\n")
        f:write("MIN_WRITE_INTERVAL=" .. g("min_write_interval", 60) .. "\n")
        f:write("CONCURRENCY="      .. g("concurrency", 8)       .. "\n")
        f:write("MAX_CANDIDATES="   .. g("max_candidates", 24)   .. "\n")
        f:write("POOL_REFRESH=600\n")
        f:write("LOG_FILE=/var/log/ghacc.log\n")
        f:write("MAX_LOG=200\n")
        f:write("AUTO_CLEAN_LOG_DAYS=" .. keep_days .. "\n")
        f:write("STATE_DIR=/tmp/ghacc\n")
        f:write("HOSTS=/etc/hosts\n")
        -- 以下为 v2.4 引入的关键项。必须显式写出：守护进程虽有自己的默认值，
        -- 但把生效值落盘可避免「界面保存后行为悄悄变化」的隐患（曾漏写）。
        f:write("ADDN_HOSTS=/tmp/ghacc/hosts.addn\n")
        f:write("DNSMASQ_CONFDIR=/tmp/dnsmasq.d\n")
        f:write("WRITE_ETC_HOSTS=0\n")
        f:write("MIN_BODY_SIZE=5000\n")
        f:write("BODY_MARKER=github\n")
        f:write("SELFCHECK_DOMAIN=github.com\n")
        f:write("SELFCHECK_INTERVAL=300\n")
        f:write("SELFCHECK_DNS=127.0.0.1\n")
        f:close()
    end

    if uci:get("ghacc", "main", "enabled") == "1" then
        sys.call("/etc/init.d/ghacc enable >/dev/null 2>&1")
        sys.call("/etc/init.d/ghacc restart >/dev/null 2>&1")
    else
        sys.call("/etc/init.d/ghacc stop >/dev/null 2>&1")
        sys.call("/etc/init.d/ghacc disable >/dev/null 2>&1")
    end
end

return m
