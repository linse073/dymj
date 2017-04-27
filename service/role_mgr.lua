local skynet = require "skynet"
local sharedata = require "sharedata"
local sprotoloader = require "sprotoloader"

local assert = assert
local string = string
local ipairs = ipairs
local pairs = pairs
local type = type

local role_list = {}
local sproto
local name_msg
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
    role_list[roleid] = agent
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

local function pack_msg(msg, info)
    if sproto:exist_type(msg) then
        info = sproto:pencode(msg, info)
    end
    local id = assert(name_msg[msg], string.format("No protocol %s.", msg))
    return string.pack(">s2", string.pack(">I2", id) .. info)
end

function CMD.broadcast(msg, info, exclude)
    local c = pack_msg(msg, info)
    for k, v in pairs(role_list) do
        if k ~= exclude then
            skynet.send(v.agent, "lua", "notify", c)
        end
    end
end

function CMD.broadcast_range(msg, info, range)
    local c = pack_msg(msg, info)
    for k, v in ipairs(range) do
        local role = role_list[v]
        if role then
            skynet.send(role.agent, "lua", "notify", c)
        end
    end
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
            skynet.error(string.format("No role info %d.", roleid))
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
            skynet.error(string.format("No role rank info %d.", roleid))
        end
    end
end

skynet.start(function()
    sproto = sprotoloader.load(1)
    name_msg = sharedata.query("name_msg")
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
