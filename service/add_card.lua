local skynet = require "skynet"

local floor = math.floor

local arg = table.pack(...)

skynet.start(function()
    for k, v in pairs(arg) do
        print(v)
    end
    -- local offline_mgr = skynet.queryservice("offline_mgr")
    -- skynet.call(offline_mgr, "lua", "add", id, "role", "add_room_card", tonumber(q.card))

    skynet.error("add card finish.")
    skynet.exit()
end)
