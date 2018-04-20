local skynet = require "skynet"
local share = require "share"
local util = require "util"
local notify = require "notify"

local floor = math.floor
local table = table

local role
local game

local update_user = util.update_user
local base
local error_code
local cz
local rand
local club_mgr
local club_role

local proc = {}
local club = {proc = proc}

skynet.init(function()
    base = share.base
    error_code = share.error_code
    cz = share.cz
    rand = share.rand
    club_mgr = skynet.queryservice("club_mgr")
    club_role = skynet.queryservice("club_role")
end)

function club.init_module()
	game = require "game"
    role = require "game.role"
end

local function join(info)
    local data = game.data
    local club_info = data.club_info
    if #club_info < base.MAX_CLUB then
        info.pos = base.CLUB_POS_NONE
        local index = #club_info + 1
        info.index = index
        club_info[index] = info
        data.id_club[info.id] = info
        data.user.club[index] = info.id
        skynet.call(club_role, "lua", "add", data.id, info.id, info.addr)
        notify.add("update_user", {update={club={info}}})
        return true
    end
end
function club.join(info)
    cz.start()
    local r = join(info)
    cz.finish()
    return r
end

local function leave(clubid)
    local data = game.data
    local info = data.id_club[clubid]
    if info then
        local index = info.index
        local club_info = data.club_info
        table.remove(club_info, index)
        table.remove(data.user.club, index)
        for i = index, #club_info do
            club_info[i].index = i
        end
        data.id_club[clubid] = nil
        skynet.call(club_role, "lua", "del", data.id, clubid)
        local u = {id=clubid, leave=true}
        notify.add("update_user", {update={club={u}}})
    else
        skynet.error(string.format("Role %d not in club %d.", data.id, club.id))
    end
end
function club.leave(clubid)
    cz.start()
    leave(clubid)
    cz.finish()
end

--------------------------protocol process-----------------------

function proc.query_club(msg)
    if not msg.name then
        error{code = error_code.ERROR_ARGS}
    end
    local club = skynet.call(club_mgr, "lua", "get_by_id", msg.id)
    if not club then
        error{code = error_code.NO_CLUB}
    end
    local info = skynet.call(club, "lua", "get_info")
    if not info then
        error{code = error_code.NO_CLUB}
    end
    return "club_info", info
end

function proc.found_club(msg)
    if not msg.name then
        error{code = error_code.ERROR_ARGS}
    end
    local data = game.data
    cz.start()
    local club_info = data.club_info
    if #club_info >= base.MAX_CLUB then
        error{code = error_code.CLUB_LIMIT}
    end
    if data.club_found >= base.MAX_FOUND_CLUB then
        error{code = error_code.CLUB_FOUND_LIMIT}
    end
    -- TODO: if check data.chess_table
    local user = date.user
    if user.room_card < base.FOUND_CLUB_ROOM_CARD then
        error{code = error_code.ROOM_CARD_LIMIT}
    end
    local club = skynet.call(club_mgr, "lua", "add", msg.name, data.serverid)
    if not club then
        error{code = error_code.CLUB_NAME_EXIST}
    end
    local p = update_user()
    role.add_room_card(p, false, -base.FOUND_CLUB_ROOM_CARD)
    local now = floor(skynet.time())
    club.time = now
    club.name = msg.name
    club.notify = msg.notify or ""
    club.chief_id = user.id
    local uname = user.nick_name or user.account
    club.chief = uname
    club.room_card = base.FOUND_CLUB_ROOM_CARD
    local member = {
        id = user.id,
        name = uname,
        pos = base.CLUB_POS_CHIEF,
        head_img = user.head_img,
        online = true,
        time = now,
    }
    club.member = {member}
    club.apply = {}
    skynet.call(club.addr, "lua", "open", club, rand.randi(1, 300))
    skynet.call(club_role, "lua", "add", user.id, club.id, club.addr)
    local index = #club_info + 1
    local info = {
        id = club.id,
        name = club.name,
        notify = club.notify,
        chief_id = club.chief_id,
        chief = club.chief,
        addr = club.addr,
        pos = base.CLUB_POS_CHIEF,
        index = index,
    }
    club_info[index] = info
    data.id_club[club.id] = info
    user.club[index] = club.id
    data.club_found = data.club_found + 1
    cz.finish()
    skynet.send(club.addr, "lua", "save")
    p.club = {info}
    return "update_user", {update=p}
end

function proc.apply_club(msg)
    local data = game.data
    if data.id_club[msg.id] then
        error{code = error_code.ALREADY_IN_CLUB}
    end
    local addr = skynet.call(club_mgr, "lua", "get_by_id", msg.id)
    local now = floor(skynet.time())
    local user = data.user
    local uname = user.nick_name or user.account
    local info = {
        id = user.id,
        name = uname,
        head_img = user.head_img,
        time = now,
    }
    return skynet.call(addr, "lua", "apply", info)
end

function proc.accept_club_apply(msg)
    local data = game.data
    local club = data.id_club[msg.id]
    if not club then
        error{code = error_code.NOT_IN_CLUB}
    end
    if club.pos < base.CLUB_POS_ADMIN then
        error{code = error_code.CLUB_PERMIT_LIMIT}
    end
    return skynet.call(club.addr, "lua", "accept", data.id, msg.roleid)
end

function proc.refuse_club_apply(msg)
    local data = game.data
    local club = data.id_club[msg.id]
    if not club then
        error{code = error_code.NOT_IN_CLUB}
    end
    if club.pos < base.CLUB_POS_ADMIN then
        error{code = error_code.CLUB_PERMIT_LIMIT}
    end
    return skynet.call(club.addr, "lua", "accept", data.id, msg.roleid)
end

function proc.query_club_apply(msg)
    local data = game.data
    local club = data.id_club[msg.id]
    if not club then
        error{code = error_code.NOT_IN_CLUB}
    end
    if club.pos < base.CLUB_POS_ADMIN then
        error{code = error_code.CLUB_PERMIT_LIMIT}
    end
    return skynet.call(club.addr, "lua", "query_apply", data.id)
end

function proc.query_club_member(msg)
    local data = game.data
    local club = data.id_club[msg.id]
    if not club then
        error{code = error_code.NOT_IN_CLUB}
    end
    if club.pos < base.CLUB_POS_ADMIN then
        error{code = error_code.CLUB_PERMIT_LIMIT}
    end
    return skynet.call(club.addr, "lua", "query_member", data.id)
end

function proc.remove_club_member(msg)
    local data = game.data
    local club = data.id_club[msg.id]
    if not club then
        error{code = error_code.NOT_IN_CLUB}
    end
    if club.pos < base.CLUB_POS_ADMIN then
        error{code = error_code.CLUB_PERMIT_LIMIT}
    end
    return skynet.call(club.addr, "lua", "remove_member", data.id, msg.roleid)
end

function proc.club_top(msg)
    local data = game.data
    local club = data.id_club[msg.id]
    if not club then
        error{code = error_code.NOT_IN_CLUB}
    end
    cz.start()
    local club_info = data.club_info
    local uc = data.user.club
    local index = club.index
    for i = index-1, 1, -1 do
        local j = i + 1
        local c = club_info[i]
        club_info[j] = c
        c.index = j
        uc[j] = uc[i]
    end
    club_info[1] = club
    c.index = 1
    uc[1] = club.id
    cz.finish()
    return "club_top_ret", {id=msg.id}
end

function proc.leave_club(msg)
    local data = game.data
    local club = data.id_club[msg.id]
    if not club then
        error{code = error_code.NOT_IN_CLUB}
    end
    cz.start()
    local index = info.index
    local club_info = data.club_info
    table.remove(club_info, index)
    table.remove(data.user.club, index)
    for i = index, #club_info do
        club_info[i].index = i
    end
    data.id_club[club.id] = nil
    local p = update_user()
    if club.pos == base.CLUB_POS_CHIEF then
        local room_card = skynet.call(club.addr, "lua", "disband", data.id)
        if room_card then
            role.add_room_card(p, false, room_card)
        end
        skynet.send(club_mgr, "lua", "delete", club.id)
    else
        skynet.call(club.addr, "lua", "leave", data.id)
    end
    skynet.call(club_role, "lua", "del", data.id, club.id)
    cz.finish()
    p.club = {{id=club.id, leave=true}}
    return "update_user", {update=p}
end

return club
