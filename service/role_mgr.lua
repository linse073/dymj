local skynet = require "skynet"
local broadcast = require "broadcast"

local assert = assert
local string = string
local pairs = pairs
local type = type

local role_list = {}
local user_db
local info_db

local CMD = {}

local function notify(roleid, agent)
    local pack = {}
    for k, v in pairs(role_list) do
        if k ~= roleid then
            pack[#pack+1] = v
        end
    end
    skynet.send(agent, "lua", "notify", "other_all", {other=pack})
end

function CMD.enter(info, agent)
    local roleid = info.id
    assert(not role_list[roleid], string.format("Role already enter %d.", roleid))
    info.agent = agent
    role_list[roleid] = info
    -- CMD.broadcast("other_info", info, roleid)
    -- notify(roleid, agent, area)
    skynet.error(string.format("Role enter %d.", roleid))
end

function CMD.logout(roleid)
    local role = role_list[roleid]
    if role then
        -- CMD.broadcast("logout", {id=roleid})
        role_list[roleid] = nil
        skynet.error(string.format("Role logout %d.", roleid))
    end
end

function CMD.get(roleid)
    local role = role_list[roleid]
    if role then
        return role.agent
    end
end

function CMD.online(roleid)
    return role_list[roleid] ~= nil
end

function CMD.broadcast(msg, info, exclude)
    broadcast(msg, info, role_list, exclude)
end

function CMD.get_user(roleid)
    local role = role_list[roleid]
    if role then
        return skynet.call(role.agent, "lua", "get_user"), true
    else
        local info = skynet.call(user_db, "lua", "findOne", {id=roleid})
        if info then
            return info, false
        else
            skynet.error(string.format("No user info %d.", roleid))
        end
    end
end

function CMD.get_info(roleid)
    local role = role_list[roleid]
    if role then
        return skynet.call(role.agent, "lua", "get_info"), true
    else
        local info = skynet.call(info_db, "lua", "findOne", {id=roleid})
        if info then
            return info, false
        else
            skynet.error(string.format("No role info %d.", roleid))
        end
    end
end

skynet.start(function()
    local master = skynet.queryservice("mongo_master")
    user_db = skynet.call(master, "lua", "get", "user")
    info_db = skynet.call(master, "lua", "get", "info")

	skynet.dispatch("lua", function(session, source, command, ...)
		local f = assert(CMD[command])
        if session == 0 then
            f(...)
        else
            skynet.retpack(f(...))
        end
	end)
end)
