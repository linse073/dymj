local skynet = require "skynet"

local floor = math.floor

skynet.start(function()
    local server_mgr = skynet.queryservice("server_mgr")
    skynet.call(server_mgr, "lua", "shutdown")
    local master = skynet.queryservice("mongo_master")
    local status_db = skynet.call(master, "lua", "get", "status")
    skynet.call(status_db, "lua", "update", {key="shutdown_time"}, {["$set"]={time=floor(skynet.time())}}, true)
    -- TODO: save server shutdown time
    skynet.error("shutdown finish.")
    skynet.exit()
end)
