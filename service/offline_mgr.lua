local skynet = require "skynet"

local ipairs = ipairs
local assert = assert
local tonumber = tonumber

local offline_db
local user_db
local role_mgr

local CMD = {}

function CMD.broadcast(module, info)
    local cursor = skynet.call(user_db, "lua", "find", nil, {"id"})
    while cursor:hasNext() do
        local r = cursor:next()
        CMD.add(module, r.id, info)
    end
end

function CMD.add(module, id, info)
    local agent = skynet.call(role_mgr, "lua", "get", id)
    if agent then
        skynet.call(agent, "lua", "action", module, "add", info)
    else
        skynet.call(offline_db, "lua", "update", {id=id}, {["$push"]={data=info}}, true)
    end
end

function CMD.get(id)
    local m = skynet.call(offline_db, "lua", "findOne", {id=id})
    if m then
        skynet.call(offline_db, "lua", "delete", {id=id})
        return m.data
    end
end

skynet.start(function()
    local master = skynet.queryservice("mongo_master")
    offline_db = skynet.call(master, "lua", "get", "offline")
    user_db = skynet.call(master, "lua", "get", "user")
    role_mgr = skynet.queryservice("role_mgr")

	skynet.dispatch("lua", function(session, source, command, ...)
		local f = assert(CMD[command])
        if session == 0 then
            f(...)
        else
            skynet.retpack(f(...))
        end
	end)
end)
