local skynet = require "skynet"
local util = require "util"
local timer = require "timer"
local func = require "func"
local sharedata = require "skynet.sharedata"
local queue = require "skynet.queue"

local assert = assert
local pairs = pairs

local error_code
local base

local club_db
local club
local club_info
local club_role
local role_mgr
local cs = queue()

local function save()
    skynet.call(club_db, "lua", "update", {id=club.id}, club, true)
end

local function delay_save()
    timer.del_once_routine("delay_save_club")
    time.add_routine("save_club", save, 300)
end

local function del_timer()
    timer.del_once_routine("delay_save_club")
    timer.del_routine("save_club")
end

local CMD = {}
util.time_wrap(CMD)

function CMD.exit()
	skynet.exit()
end

function CMD.open(info, delay)
    club = info
    club_info = {
        id = club.id,
        name = club.name,
        notify = club.notify,
        chief_id = club.chief_id,
        chief = club.chief,
        addr = skynet.self(),
    }
    time.add_once_routine("delay_save_club", delay_save, delay)
end

function CMD.leave(roleid)
    if club then
        local m = club.member[roleid]
        if m and m.pos ~= base.CLUB_POS_CHIEF then
            club.member[roleid] = nil
        else
            skynet.error(string.format("Role %d leave club %d error.", roleid, club.id))
        end
    else
        skynet.error(string.format("Role %d leave club error.", roleid))
    end
end

function CMD.disband(roleid)
    if club then
        local m = club.member[roleid]
        if m and m.pos == base.CLUB_POS_CHIEF then
            for k, v in pairs(club.member) do
                if v.id ~= roleid then
                    local agent = skynet.call(role_mgr, "lua", "get", v.id)
                    if agent then
                        skynet.call(agent, "action", "club", "leave", club.id)
                    else
                        skynet.call(club_role, "del", roleid, club.id)
                    end
                end
            end
            local room_card = club.room_card
            club = nil
            club_info = nil
            del_timer()
            skynet.call(club_db, "lua", "delete", {id=club.id})
            return room_card
        else
            skynet.error(string.format("Role %d disband club %d error.", roleid, club.id))
        end
    else
        skynet.error(string.format("Role %d disband club error.", roleid))
    end
end

function CMD.charge(roleid, room_card)
    if club then
        local m = club.member[roleid]
        if m and m.pos == base.CLUB_POS_CHIEF then
            club.room_card = club.room_card + room_card
            return club.room_card
        else
            skynet.error(string.format("Role %d charge club %d, room_card %d error.", roleid, club.id, room_card))
        end
    else
        skynet.error(string.format("Role %d charge club, room_card %d error.", roleid, room_card))
    end
end

function CMD.change_name(roleid, name)
    if club then
        local m = club.member[roleid]
        if m and m.pos == base.CLUB_POS_CHIEF then
            club.name = name
            club_info.name = name
        else
            skynet.error(string.format("Role %d change club %d name %d error.", roleid, club.id, name))
        end
    else
        skynet.error(string.format("Role %d change club name %d error.", roleid, name))
    end
end

function CMD.get_info()
    return club_info
end

function CMD.save()
    save()
end

function CMD.shutdown()
    del_timer()
    save()
end

function CMD.login(roleid)
    if club then
        local m = club.member[roleid]
        if m then
            return club_info, m.pos
        end
    end
end

function CMD.online(roleid, online)
    if club then
        local m = club.member[roleid]
        if m then
            m.online = online
        end
    end
end

local MSG = {}

function MSG.apply(info)
    if not club then
        error{code = error_code.NO_CLUB}
    end
    if club.member[info.id] then
        error{code = error_code.ALREADY_IN_CLUB}
    end
    if club.apply[info.id] then
        error{code = error_code.ALREADY_APPLY_CLUB}
    end
    club.apply[info.id] = info
    return "response", ""
end

function MSG.accept(adminid, roleid)
    if not club then
        error{code = error_code.NO_CLUB}
    end
    local admin = club.member[adminid]
    if not admin then
        error{code = error_code.NOT_IN_CLUB}
    end
    if admin.pos < base.CLUB_POS_ADMIN then
        error{code = error_code.CLUB_PERMIT_LIMIT}
    end
    if club.member[roleid] then
        error{code = error_code.ALREADY_IN_CLUB}
    end
    local a = club.apply[roleid]
    if not a then
        error{code = error_code.NOT_APPLY_CLUB}
    end
    local role = skynet.call(role_mgr, "lua", "get", roleid)
    if role then
        if skynet.call(role, "lua", "action", "club", "join", club_info) then
            a.time = floor(skynet.time())
            a.pos = base.CLUB_POS_NONE
            a.online = true
            club.member[roleid] = a
            club.apply[roleid] = nil
            return "club_all", {id=club.id, member={a}}
        else
            error{code = error_code.CLUB_LIMIT}
        end
    else
        if skynet.call(club_role, "lua", "count", roleid) >= base.MAX_CLUB then
            error{code = error_code.CLUB_LIMIT}
        else
            skynet.call(club_role, "lua", "add", roleid, club.id, skynet.self())
            a.time = floor(skynet.time())
            a.pos = base.CLUB_POS_NONE
            a.online = false
            club.member[roleid] = a
            club.apply[roleid] = nil
            return "club_all", {id=club.id, member={a}}
        end
    end
end

function MSG.accept_all(adminid)
    if not club then
        error{code = error_code.NO_CLUB}
    end
    local admin = club.member[adminid]
    if not admin then
        error{code = error_code.NOT_IN_CLUB}
    end
    if admin.pos < base.CLUB_POS_ADMIN then
        error{code = error_code.CLUB_PERMIT_LIMIT}
    end
    local member = club.member
    local m = {}
    local now = floor(skynet.time())
    for k, v in pairs(club.apply) do
        if not member[v.id] then
            local role = skynet.call(role_mgr, "lua", "get", v.id)
            if role then
                if skynet.call(role, "lua", "action", "club", "join", club_info) then
                    v.time = now
                    v.pos = base.CLUB_POS_NONE
                    v.online = true
                    member[v.id] = v
                    m[#m+1] = v
                end
            else
                if skynet.call(club_role, "lua", "count", v.id) < base.MAX_CLUB then
                    skynet.call(club_role, "lua", "add", v.id, club.id, skynet.self())
                    v.time = now
                    v.pos = base.CLUB_POS_NONE
                    v.online = false
                    member[v.id] = v
                    m[#m+1] = v
                end
            end
        end
    end
    club.apply = {}
    return "club_all", {id=club.id, member=m, refush_apply=true}
end

function MSG.refuse(adminid, roleid)
    if not club then
        error{code = error_code.NO_CLUB}
    end
    local admin = club.member[adminid]
    if not admin then
        error{code = error_code.NOT_IN_CLUB}
    end
    if admin.pos < base.CLUB_POS_ADMIN then
        error{code = error_code.CLUB_PERMIT_LIMIT}
    end
    if not club.apply[roleid] then
        error{code = error_code.NOT_APPLY_CLUB}
    end
    club.apply[roleid] = nil
    return "club_all", {id=club.id, apply={{id=roleid, del=true}}}
end

function MSG.refuse_all(adminid)
    if not club then
        error{code = error_code.NO_CLUB}
    end
    local admin = club.member[adminid]
    if not admin then
        error{code = error_code.NOT_IN_CLUB}
    end
    if admin.pos < base.CLUB_POS_ADMIN then
        error{code = error_code.CLUB_PERMIT_LIMIT}
    end
    club.apply = {}
    return "club_all", {id=club.id, refush_apply=true}
end

function MSG.query_apply(adminid)
    if not club then
        error{code = error_code.NO_CLUB}
    end
    local admin = club.member[adminid]
    if not admin then
        error{code = error_code.NOT_IN_CLUB}
    end
    if admin.pos < base.CLUB_POS_ADMIN then
        error{code = error_code.CLUB_PERMIT_LIMIT}
    end
    local a = {}
    for k, v in pairs(club.apply) do
        a[#a+1] = v
    end
    return "club_all", {id=club.id, refush_apply=true, apply=a}
end

function MSG.query_member(adminid)
    if not club then
        error{code = error_code.NO_CLUB}
    end
    local admin = club.member[adminid]
    if not admin then
        error{code = error_code.NOT_IN_CLUB}
    end
    local m = {}
    for k, v in pairs(club.member) do
        m[#m+1] = v
    end
    return "club_all", {id=club.id, refresh_member=true, member=m}
end

function MSG.detail(roleid)
    if not club then
        error{code = error_code.NO_CLUB}
    end
    local role = club.member[roleid]
    if not role then
        error{code = error_code.NOT_IN_CLUB}
    end
    local info = {
        id = club.id,
        name = club.name,
        notify = club.notify,
        chief_id = club.chief_id,
        chief = club.chief,
        time = club.time,
        room_card = club.room_card,
    }
    return "club_all", info
end

function MSG.remove_member(adminid, roleid)
    if not club then
        error{code = error_code.NO_CLUB}
    end
    local admin = club.member[adminid]
    if not admin then
        error{code = error_code.NOT_IN_CLUB}
    end
    local role = club.member[roleid]
    if not role then
        error{code = error_code.TARGET_NOT_IN_CLUB}
    end
    if admin.pos <= role.pos then
        error{code = error_code.CLUB_PERMIT_LIMIT}
    end
    local agent = skynet.call(role_mgr, "lua", "get", roleid)
    if agent then
        skynet.call(agent, "action", "club", "leave", club.id)
        club.member[roleid] = nil
    else
        skynet.call(club_role, "del", roleid, club.id)
        club.member[roleid] = nil
    end
    return "club_all", {id=club.id, member={{id=roleid, del=true}}}
end

function MSG.promote(adminid, roleid)
    if not club then
        error{code = error_code.NO_CLUB}
    end
    local admin = club.member[adminid]
    if not admin then
        error{code = error_code.NOT_IN_CLUB}
    end
    if admin.pos ~= base.CLUB_POS_CHIEF then
        error{code = error_code.CLUB_PERMIT_LIMIT}
    end
    local role = club.member[roleid]
    if not role then
        error{code = error_code.TARGET_NOT_IN_CLUB}
    end
    if role.pos == base.CLUB_POS_ADMIN then
        error{code = error_code.ALREADY_CLUB_ADMIN}
    end
    local agent = skynet.call(role_mgr, "lua", "get", roleid)
    if agent then
        skynet.call(agent, "lua", "promote", club.id)
    end
    role.pos = base.CLUB_POS_ADMIN
    return "club_all", {id=club.id, member={{id=roleid, pos=role.pos}}}
end

function MSG.demote(adminid, roleid)
    if not club then
        error{code = error_code.NO_CLUB}
    end
    local admin = club.member[adminid]
    if not admin then
        error{code = error_code.NOT_IN_CLUB}
    end
    if admin.pos ~= base.CLUB_POS_CHIEF then
        error{code = error_code.CLUB_PERMIT_LIMIT}
    end
    local role = club.member[roleid]
    if not role then
        error{code = error_code.TARGET_NOT_IN_CLUB}
    end
    if role.pos == base.CLUB_POS_NONE then
        error{code = error_code.NOT_CLUB_ADMIN}
    end
    local agent = skynet.call(role_mgr, "lua", "get", roleid)
    if agent then
        skynet.call(agent, "lua", "demote", club.id)
    end
    role.pos = base.CLUB_POS_NONE
    return "club_all", {id=club.id, member={{id=roleid, pos=role.pos}}}
end

for k, v in pairs(MSG) do
    CMD[k] = function(...)
        return func.return_msg(pcall(v, ...))
    end
end

skynet.start(function()
    error_code = sharedata.query("error_code")
    base = sharedata.query("base")

    local master = skynet.queryservice("mongo_master")
    club_db = skynet.call(master, "lua", "get", "club")
    club_role = skynet.queryservice("club_role")
    role_mgr = skynet.queryservice("role_mgr")

	skynet.dispatch("lua", function(session, source, command, ...)
		local f = assert(CMD[command])
        if session == 0 then
            cs(f, ...)
        else
            skynet.retpack(cs(f, ...))
        end
	end)
end)
