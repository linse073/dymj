local skynet = require "skynet"
local queue = require "skynet.queue"
local util = require "util"

local assert = assert
local pcall = pcall
local string = string
local ipairs = ipairs

local free_list = {}
local club_list = {}

local id_club = {}
local key_club = {}
local server_list
local club_info_db
local cs = queue()

local function new_club(num)
    local t = {}
    for i = 1, num do
        t[i] = skynet.newservice("club") 
    end
    local l = #free_list
    for k, v in ipairs(t) do
        l = l + 1
        free_list[l] = v
        club_list[v] = l
    end
end

local function del_club(num)
    local l = #free_list
    if num > l then
        num = l
    end
    local t = {}
    for i = 1, num do
        local club = free_list[l]
        t[i] = club
        free_list[l] = nil
        club_list[club] = nil
        l = l - 1
    end
    for k, v in ipairs(t) do
        -- NOTICE: logout may call skynet.exit, so you should use pcall.
        pcall(skynet.call, v, "lua", "exit")
    end
end

local function get()
    local l = #free_list
    local club
    if l > 0 then
        club = free_list[l]
        free_list[l] = nil
        club_list[club] = 0
        if l <= 10 then
            skynet.fork(new_club, 10)
        end
    else
        club = skynet.newservice("club")
        club_list[club] = 0
    end
    return club
end

local function free(club)
    if club_list[club] == 0 then
        local l = #free_list + 1
        free_list[l] = club
        club_list[club] = l
        if l >= 150 then
            skynet.fork(del_club, 50)
        end
    end
end

local CMD = {}

function CMD.login(roleid, clubid)
    local c = id_club[clubid]
    if c then
        local club = skynet.call(c.address, "lua", "login", roleid)
        club.address = c.address
        return club
    else
        local address = get()
        local club = skynet.call(address, "lua", "open", clubid, roleid)
        if club then
            club.address = address
            local key = club.key
            c = {
                address = address,
                key = key,
                id = clubid,
            }
            id_club[clubid] = c
            key_club[key] = c
            return club
        else
            free(address)
        end
    end
end

function CMD.logout(roleid, clubid)
    local c = id_club[clubid]
    if c then
        if skynet.call(c.address, "lua", "logout", roleid) then
            free(c.address)
            id_club[clubid] = nil
            key_club[c.key] = nil
        end
    end
end

function CMD.create(club)
    local address = get()
    local key = club.key
    local c = {
        address = address,
        key = key,
        id = club.id,
    }
    id_club[clubid] = c
    key_club[key] = c
    return address
end

function CMD.disband(clubid)
    local c = id_club[clubid]
    if c then
        free(c.address)
        id_club[clubid] = nil
        key_club[c.key] = nil
        return true
    end
end

function CMD.get_info(name)
    for k, v in pairs(server_list) do
        local key = util.gen_key(k, name)
        local c = key_club[key]
        if c then
            return skynet.call(c.address, "lua", "get_info")
        else
            local club = skynet.call(club_info_db, "lua", "findOne", {key=key})
            if club then
                return club
            end
        end
    end
end

skynet.start(function()
    local master = skynet.queryservice("mongo_master")
    club_info_db = skynet.call(master, "lua", "get", "club_info")
    local server_mgr = skynet.queryservice("server_mgr")
    server_list = skynet.call(server_mgr, "lua", "get_all")
    new_club(100)

	skynet.dispatch("lua", function(session, source, command, ...)
		local f = assert(CMD[command])
        skynet.retpack(cs(f, ...))
	end)
end)
