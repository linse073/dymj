local skynet = require "skynet"

local function mongo_find(db, ...)
    local key = skynet.call(db, "lua", "find", ...)
    return function()
        return skynet.call(db, "lua", "get_next", key)
    end
end

return mongo_find
