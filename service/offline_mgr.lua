local skynet = require "skynet"
local queue = require "skynet.queue"

local ipairs = ipairs
local assert = assert
local tonumber = tonumber
local table = table

local offline_db
local user_db
local role_mgr
local cs = queue()

local CMD = {}

local function add(id, ...)
    local agent = skynet.call(role_mgr, "lua", "get", id)
    if agent then
        skynet.call(agent, "lua", "action", ...)
    else
        skynet.call(offline_db, "lua", "update", {id=id}, {["$push"]={data=table.pack(...)}}, true)
    end
end

local function get(id)
    local m = skynet.call(offline_db, "lua", "findOne", {id=id})
    if m then
        skynet.call(offline_db, "lua", "delete", {id=id})
        return m.data
    end
end

function CMD.broadcast(...)
    local cursor = skynet.call(user_db, "lua", "find", nil, {"id"})
    while cursor:hasNext() do
        local r = cursor:next()
        cs(add, r.id, ...)
    end
end

function CMD.add(id, ...)
    cs(add, id, ...)
end

function CMD.get(id)
    return cs(get, id)
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
