module("luci.controller.speedtestpp", package.seeall)

function index()
	if not nixio.fs.access("/usr/bin/speedtestpp") then
		return
	end

	entry({"admin", "network", "speedtestpp"}, template("speedtestpp/status"), _("Speedtest"), 90).dependent = true
	entry({"admin", "network", "speedtestpp", "start"}, call("act_start")).leaf = true
	entry({"admin", "network", "speedtestpp", "status"}, call("act_status")).leaf = true
	entry({"admin", "network", "speedtestpp", "result"}, call("act_result")).leaf = true
end

local function run(args)
	local r = luci.sys.exec("speedtestpp-run.sh " .. args .. " 2>&1")
	return (r or ""):gsub("\n$", "")
end

function act_start()
	luci.http.prepare_content("text/plain")
	luci.http.write(run("start"))
end

function act_status()
	luci.http.prepare_content("text/plain")
	luci.http.write(run("status"))
end

function act_result()
	local out = run("result")
	luci.http.prepare_content("text/plain; charset=utf-8")
	luci.http.write(out)
end
