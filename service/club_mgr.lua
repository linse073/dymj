local skynet = require "skynet"
local util = require "util"
local random = require "random"
local sharedata = require "skynet.sharedata"

local assert = assert
local pcall = pcall
local string = string
local ipairs = ipairs
local floor = math.floor

local free_list = {}
local club_list = {}

local id_club = {}
local key_club = {}
local server_list
local club_db
local rand

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
        if l <= 2 then
            skynet.fork(new_club, 2)
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
        if l >= 15 then
            skynet.fork(del_club, 5)
        end
    end
end

local CMD = {}

function CMD.add(name, serverid)
    local key = util.gen_key(serverid, name)
    if not key_club[key] then
        -- NOTICE: set key_club first
        local c = {key=key}
        key_club[key] = c
        local id = skynet.call(server_list[serverid], "lua", "gen_club")
        c.id = id
        local addr = get()
        c.addr = addr
        id_club[id] = c
        return c
    end
end

function CMD.delete(id)
    local c = id_club[id]
    if c then
        id_club[id] = nil
        key_club[c.key] = nil
        free(c.addr)
    else
        skynet.error(string.format("Delete club %d error.", id))
    end
end

function CMD.change_name(id, name, serverid)
    local c = id_club[id]
    if c then
        local key = util.gen_key(serverid, name)
        if not key_club[key] then
            key_club[c.key] = nil
            c.key = key
            key_club[key] = c
            return key
        end
    else
        skynet.error(string.format("Change club %d name error.", id))
    end
end

function CMD.get_by_id(id)
    local c = id_club[id]
    if c then
        return c.addr
    end
end

function CMD.get_by_name(name)
    for k, v in pairs(server_list) do
        local key = util.gen_key(k, name)
        local c = key_club[key]
        if c then
            return c.addr
        end
    end
end

function CMD.shutdown()
    for k, v in pairs(id_club) do
        skynet.call(v.addr, "lua", "shutdown")
    end
end

function CMD.open()
    rand = random()
    rand.init(floor(skynet.time()))
    local master = skynet.queryservice("mongo_master")
    club_db = skynet.call(master, "lua", "get", "club")
    local club_role = skynet.queryservice("club_role")
    local base = sharedata.query("base")
    util.mongo_find(club_db, function(r)
        -- NOTICE: repair
        local extra = {
            online_count = 0,
            admin_count = 0,
            admin = {},
            member = {},
            apply = {},
        }
        local m = {}
        local member = r.member
        for k, v in pairs(member) do
            v.online = false
            -- NOTICE: repair member
            if not v.day_card then
                v.day_card = 0
            end
            extra.member[v.id] = v
            m[#m+1] = v.id
            if v.pos == base.CLUB_POS_ADMIN then
                extra.admin[v.id] = v
                extra.admin_count = extra.admin_count + 1
            end
        end
        extra.member_count = #m
        local a = {}
        for k, v in pairs(r.apply) do
            if not member[v.id] then
                a[k] = v
                extra.apply[v.id] = v
            else
                skynet.error(string.format("Apply role %d already in club %d.", v.id, r.id))
            end
        end
        r.apply = a
        local club = skynet.newservice("club")
        skynet.call(club, "lua", "open", r, extra, rand.randi(1, 300))
        local c = {
            id = r.id,
            key = r.key,
            addr = club,
        }
        id_club[r.id] = c
        key_club[r.key] = c
        skynet.call(club_role, "lua", "batch_add", m, r.id, club)
    end, nil, {_id=false})
    local server_mgr = skynet.queryservice("server_mgr")
    server_list = skynet.call(server_mgr, "lua", "get_all")
    new_club(10)
end

skynet.start(function()
	skynet.dispatch("lua", function(session, source, command, ...)
		local f = assert(CMD[command])
        if session == 0 then
            f(...)
        else
            skynet.retpack(f(...))
        end
	end)
end)
