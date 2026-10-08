-- LuCI controller for ghacc-daemon
-- 安装位置: /usr/lib/lua/luci/controller/ghacc.lua
module("luci.controller.ghacc", package.seeall)

function index()
    entry({"admin", "services", "ghacc"},
          alias("admin", "services", "ghacc", "status"),
          _("GitHub 加速"), 60)
    entry({"admin", "services", "ghacc", "status"},
          call("action_status"), _("运行状态"), 10)
    -- 日志轮询端点（页面每秒拉一次，走独立 URL，避免整页刷新）
    entry({"admin", "services", "ghacc", "log"}, call("action_log"))
    entry({"admin", "services", "ghacc", "config"},
          cbi("ghacc"), _("参数设置"), 20)
end

local function read_file(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local d = f:read("*a")
    f:close()
    return d
end

-- 读取守护进程真正写入的条目文件。
--
-- 注意（v2.4.1 修复）：v2.3 起守护进程不再写 /etc/hosts，改为写
-- ADDN_HOSTS=/tmp/ghacc/hosts.addn（dnsmasq 的 addn-hosts）。
-- 旧版这里读 /etc/hosts，于是界面永远显示"暂无条目"——与实际运行状态无关，
-- 纯属读错了文件。现在优先读 addn 文件，回退 /etc/hosts 以兼容老配置。
function entries_path()
    for _, p in ipairs({"/tmp/ghacc/hosts.addn", "/etc/hosts"}) do
        local f = io.open(p, "r")
        if f then f:close() return p end
    end
    return "/tmp/ghacc/hosts.addn"
end

-- 从标记块中解析 IP/域名
local function parse_entries(path)
    local txt = read_file(path or entries_path()) or ""
    local out = {}
    local inb = false
    for line in txt:gmatch("[^\r\n]+") do
        if line:find("# GHACC-BEGIN", 1, true) then
            inb = true
        elseif line:find("# GHACC-END", 1, true) then
            inb = false
        elseif inb and line:match("%S") and not line:match("^%s*#") then
            local ip, dom = line:match("^%s*(%S+)%s+(%S+)")
            if ip and dom then
                out[#out + 1] = { ip = ip, domain = dom }
            end
        end
    end
    return out
end

-- 读取日志（供页面与轮询端点共用）
local function current_log()
    local sys = require "luci.sys"
    local out = sys.exec("tail -n 200 /var/log/ghacc.log 2>/dev/null")
    if not out or out == "" then
        -- 注意：这里**不能**用 _()。LuCI 只为 index() 注入翻译函数 _，
        -- 在普通函数里 _ 是 nil，调用会抛
        -- "attempt to call global '_' (a nil value)"，导致整页 500。
        -- 这正是「清理日志后日志为空 → 页面报 Runtime error」的原因：
        -- 清空后 current_log() 命中此分支。要用翻译就显式 require
        -- luci.i18n 后调 i18n.translate(...)；此处直接给中文即可。
        out = "(暂无日志：守护进程可能尚未产生输出)"
    end
    return out
end

-- 日志轮询端点：纯文本返回，供页面 setInterval 每秒调用
function action_log()
    local http = require "luci.http"
    -- 禁用缓存，保证每秒拿到的都是最新内容
    http.header("Content-Type", "text/plain; charset=utf-8")
    http.header("Cache-Control", "no-store, no-cache, must-revalidate")
    http.header("Pragma", "no-cache")
    http.write(current_log())
end

function action_status()
    local http = require "luci.http"
    local disp = require "luci.dispatcher"
    local sys  = require "luci.sys"
    local tpl  = require "luci.template"

    -- 按钮动作
    local act = http.formvalue("action")
    if act == "start" then
        sys.call("/etc/init.d/ghacc start >/dev/null 2>&1")
    elseif act == "stop" then
        sys.call("/etc/init.d/ghacc stop >/dev/null 2>&1")
    elseif act == "restart" then
        sys.call("/etc/init.d/ghacc restart >/dev/null 2>&1")
    elseif act == "rescan" then
        -- 清空已缓存的 IP，强制下一轮全量重扫
        sys.call("rm -f /tmp/ghacc/ip.* /tmp/ghacc/last.* /tmp/ghacc/fail.* 2>/dev/null; " ..
                 "/etc/init.d/ghacc restart >/dev/null 2>&1")
    elseif act == "clearlog" then
        -- 清空日志。用 : > 而非 rm，避免守护进程手里的 fd 失效
        -- （日志是每行 >> 追加打开的，rm 后会写到已删除的 inode 上，
        --  导致「清了但日志还在涨、且再也读不到」的假象）
        sys.call(": > /var/log/ghacc.log 2>/dev/null")
        sys.call("logger -t ghacc '日志已通过 LuCI 界面清空' 2>/dev/null")
    end
    if act then
        http.redirect(disp.build_url("admin", "services", "ghacc", "status"))
        return
    end

    local running = (sys.call("pgrep -f ghacc-daemon >/dev/null 2>&1") == 0)
    local enabled = (sys.call("/etc/init.d/ghacc enabled >/dev/null 2>&1") == 0)
    local epath   = entries_path()

    tpl.render("ghacc/status", {
        running      = running,
        enabled      = enabled,
        entries      = parse_entries(epath),
        entries_file = epath,
        log          = current_log(),
        log_url      = disp.build_url("admin", "services", "ghacc", "log"),
    })
end
