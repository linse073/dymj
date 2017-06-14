local skynet = require "skynet"
local util = require "util"

local string = string
local ipairs = ipairs
local floor = math.floor
local tonumber = tonumber

skynet.start(function()
	skynet.error("Server start")

    local t = util.parse_time(skynet.getenv("start_time"))
    skynet.setenv("start_utc_time", t)
    skynet.setenv("start_routine_time", util.day_time(t))

    -- debug service
    if not skynet.getenv("daemon") then
        skynet.newservice("console")
    end
	skynet.newservice("debug_console", skynet.getenv("debug_console"))

    -- service
    local config = require(skynet.getenv("config"))
    local mongo_master = skynet.uniqueservice("mongo_master")
    skynet.call(mongo_master, "lua", "open", config.mongo)
    local redis_master = skynet.uniqueservice("redis_master")
    skynet.call(redis_master, "lua", "open", config.redis)

    local status_db = skynet.call(mongo_master, "lua", "get", "status")
    local open_time = skynet.call(status_db, "lua", "findOne", {key="open_time"})
    local now = floor(skynet.time())
    if not open_time then
        open_time = {time = now}
    end
    skynet.call(status_db, "lua", "update", {key="last_open_time"}, {["$set"]={time=open_time.time}}, true)
    skynet.setenv("last_open_time", open_time.time)
    skynet.call(status_db, "lua", "update", {key="open_time"}, {["$set"]={time=now}}, true)
    skynet.setenv("open_time", now)
    local shutdown_time = skynet.call(status_db, "lua", "findOne", {key="shutdown_time"})
    if not shutdown_time then
        shutdown_time = {time = now}
    end
    skynet.setenv("shutdown_time", shutdown_time.time)

    skynet.uniqueservice("webclient")
	skynet.uniqueservice("cache")
    skynet.uniqueservice("server_mgr")
    skynet.uniqueservice("chess_mgr")
    skynet.uniqueservice("routine")
    skynet.uniqueservice("role_mgr")
    skynet.uniqueservice("offline_mgr")
    -- TODO: server shutdown time
    local table_mgr = skynet.uniqueservice("table_mgr")
    skynet.call(table_mgr, "lua", "open")
    skynet.uniqueservice("agent_mgr")
    skynet.uniqueservice("webd", skynet.getenv("web"))

	local loginserver = skynet.newservice("logind")
    local gate = skynet.newservice("gated", loginserver)
    skynet.call(gate, "lua", "open", config.gate)
    for k, v in ipairs(config.server) do
        local server = skynet.newservice("server", loginserver)
        skynet.call(server, "lua", "open", v, config.gate.servername)
    end
    
    skynet.exit()
end)
