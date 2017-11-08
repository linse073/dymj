local skynet = require "skynet"

local arg = table.pack(...)

skynet.start(function()
    if arg.n == 2 then
        local offline_mgr = skynet.queryservice("offline_mgr")
        skynet.call(offline_mgr, "lua", "add", tonumber(arg[1]), "role", "add_room_card", tonumber(arg[2]))
        skynet.error("add card finish.")
    else
        skynet.error("wrong number arg of add card.")
    end
    skynet.exit()
end)
