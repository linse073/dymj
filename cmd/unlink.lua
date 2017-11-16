local skynet = require "skynet"

local arg = table.pack(...)

skynet.start(function()
    if arg.n == 1 then
        local offline_mgr = skynet.queryservice("offline_mgr")
        skynet.call(offline_mgr, "lua", "add", tonumber(arg[1]), "role", "unlink")
        skynet.error("unlink finish.")
    else
        skynet.error("wrong number arg of unlink.")
    end
    skynet.exit()
end)
