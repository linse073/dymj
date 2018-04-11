local skynet = require "skynet"

local assert = assert
local pcall = pcall
local string = string
local ipairs = ipairs

local free_list = {}
local club_list = {}

local id_club = {}
local name_club = {}

local club_info_db

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

function CMD.login(id, club)
    local info = {}
    for k, v in ipairs(club) do
        local c = id_club[v]
        if c then
            info[#info+1] = skynet.call(c.address, "lua", "login", id)
        else
            local address = get()
            local i = skynet.call(address, "lua", "open", v, id)
            if i then
                info[#info+1] = i
                c = {address=address, name=name, id=v}
                id_club[v] = c
                name_club[name] = c
            else
                free(address)
            end
        end
    end
end

function CMD.logout(club)
    for k, v in ipairs(club) do
        local c = id_club[v]
        if c then
        else
        end
    end
end

function CMD.get_info(name)
    local club = name_club[name]
    if club then
        return skynet.call(club.address, "lua", "get_info")
    else
        return skynet.call(club_info_db, "lua", "findOne", {name=name})
    end
end

skynet.start(function()
    local master = skynet.queryservice("mongo_master")
    club_info_db = skynet.call(master, "lua", "get", "club_info")
    new_club(100)

	skynet.dispatch("lua", function(session, source, command, ...)
		local f = assert(CMD[command])
        skynet.retpack(f(...))
	end)
end)
