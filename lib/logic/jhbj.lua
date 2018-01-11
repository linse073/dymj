local skynet = require "skynet"
local share = require "share"
local util = require "util"
local timer = require "timer"
local bson = require "bson"
local func = require "func"

local string = string
local ipairs = ipairs
local pairs = pairs
local table = table
local floor = math.floor
local os = os

local base
local error_code
local user_record_db
local record_info_db
local record_detail_db
local table_mgr
local chess_mgr
local offline_mgr

skynet.init(function()
    base = share.base
    error_code = share.error_code
    local master = skynet.queryservice("mongo_master")
    user_record_db = skynet.call(master, "lua", "get", "user_record")
    record_info_db = skynet.call(master, "lua", "get", "record_info")
    record_detail_db = skynet.call(master, "lua", "get", "record_detail")
    table_mgr = skynet.queryservice("table_mgr")
    chess_mgr = skynet.queryservice("chess_mgr")
    offline_mgr = skynet.queryservice("offline_mgr")
end)

local function valid_card(c)
    return c>0 and c<=base.POKER_CARD
end

local function session_msg(user, chess_user, chess_info)
    local msg = {update={chess={
        info = chess_info,
        user = chess_user,
        session = user.session,
    }}}
    user.session = user.session + 1
    return "update_user", msg
end

local function send(user, chess_user, chess_info)
    if user.agent then
        local m, i = session_msg(user, chess_user, chess_info)
        skynet.call(user.agent, "lua", "notify", m, i)
    end
end

local function broadcast(chess_user, chess_info, role, ...)
    if ... then
        local exclude = {}
        for k, v in ipairs({...}) do
            exclude[v] = v
        end
        for k, v in pairs(role) do
            if not exclude[v.id] then
                send(v, chess_user, chess_info)
            end
        end
    else
        for k, v in pairs(role) do
            send(v, chess_user, chess_info)
        end
    end
end

local jhbj = {}

function jhbj:init(number, rule, rand, server, card)
    self._number = number
    self._rule = rule
    self._rand = rand
    self._server = server
    self._custom_card = card
    self._banker = 1
    self._status = base.CHESS_STATUS_READY
    self._role = {}
    self._id = {}
    self._count = 0
    self._pause = false
    self._close_index = 0
    self._record = {
        info = {
            name = "jhbj",
            number = number,
            rule = rule.pack,
        },
    }
end

function jhbj:status(id, status, addr)
    local info = self._id[id]
    if info then
        if status~=info.status or (addr and addr~=info.ip) then
            info.status = status
            if addr then
                info.ip = addr
            end
            if status == base.USER_STATUS_LOGOUT then
                info.agent = nil
            end
            local user = {index=info.index, status=status, ip=addr}
            broadcast({user}, chess, self._role)
        end
    end
end

function jhbj:destroy()
    timer.del_once_routine("close_timer")
end

local function finish()
    skynet.call(skynet.self(), "lua", "destroy")
    skynet.call(table_mgr, "lua", "free", skynet.self())
end
function jhbj:finish()
    local role = self._role
    self._role = {}
    self._id = {}
    for i = 1, self._rule.user do
        local v = role[i]
        if v then
            skynet.call(chess_mgr, "lua", "del", v.id)
            if v.agent then
                skynet.call(v.agent, "lua", "action", "role", "leave")
            end
        end
    end
    skynet.fork(finish)
end

function jhbj:custom_card(name, card)
    if name ~= "jhbj" then
        error{code = error_code.ERROR_CHESS_NAME}
    end
    self._custom_card = card
    return "response", ""
end

function jhbj:pack(id, ip, agent)
    local si = self._id[id]
    if si then
        si.ip = ip
        si.status = base.USER_STATUS_ONLINE
        si.agent = agent
        local role = self._role
        broadcast({
            {index=si.index, status=si.status, ip=ip},
        }, nil, role, id)
        local status = self._status
        local rule = self._rule
        if status == base.CHESS_STATUS_READY then
            local chess = {
                name = "jhbj",
                number = self._number,
                rule = rule.pack,
                banker = self._banker,
                status = status,
                count = self._count,
                pause = self._pause,
                old_banker = self._old_banker,
                close_index = self._close_index,
                close_time = self._close_time,
            }
            local user = {}
            for i = 1, rule.user do
                local info = role[i]
                if info then
                    local u = {
                        account = info.account,
                        id = info.id,
                        sex = info.sex,
                        nick_name = info.nick_name,
                        head_img = info.head_img,
                        ip = info.ip,
                        index = info.index,
                        score = info.score,
                        ready = info.ready,
                        top_score = info.top_score,
                        hu_count = info.hu_count,
                        status = info.status,
                        out_index = info.out_index,
                        give_up = info.give_up,
                        location = info.location,
                    }
                    if info.out_card then
                        local show_card = {
                            own_card = info.out_card,
                            last_index = info.out_index,
                            score = info.last_score,
                            give_up = info.give_up,
                        }
                        u.show_card = show_card
                    end
                    user[#user+1] = u
                end
            end
            return {info=chess, user=user, start_session=si.session}
        elseif status == base.CHESS_STATUS_START then
            local chess = {
                name = "jhbj",
                number = self._number,
                rule = rule.pack,
                banker = self._banker,
                status = status,
                count = self._count,
                pause = self._pause,
                close_index = self._close_index,
                close_time = self._close_time,
            }
            local user = {}
            for i = 1, rule.user do
                local info = role[i]
                if info then
                    local u = {
                        account = info.account,
                        id = info.id,
                        sex = info.sex,
                        nick_name = info.nick_name,
                        head_img = info.head_img,
                        ip = info.ip,
                        index = info.index,
                        score = info.score,
                        ready = info.ready,
                        agree = info.agree,
                        top_score = info.top_score,
                        hu_count = info.hu_count,
                        status = info.status,
                        location = info.location,
                        pass = info.out_card~=nil or info.give_up,
                    }
                    if info.id == id then
                        u.own_card = info.deal_card
                        u.out_card = info.out_card
                        u.out_index = info.out_index
                        u.give_up = info.give_up
                    end
                    user[#user+1] = u
                end
            end
            return {info=chess, user=user, start_session=si.session}
        end
    end
end

function jhbj:enter(info, agent, index, location)
    local role = self._role
    assert(not role[index], string.format("Seat %d already has role.", index))
    info.agent = agent
    info.index = index
    info.location = location
    info.score = 0
    info.ready = false
    info.hu_count = 0
    info.top_score = 0
    info.session = 1
    info.status = base.USER_STATUS_ONLINE
    role[index] = info
    self._id[info.id] = info
    skynet.call(chess_mgr, "lua", "add", info.id, skynet.self())
    local user = {}
    local rule = self._rule
    for i = 1, rule.user do
        user[#user+1] = role[i] -- role[i] can be nil
    end
    local chess = {
        name = "jhbj",
        number = self._number,
        rule = rule.pack,
        banker = self._banker,
        status = self._status,
        count = self._count,
        pause = self._pause,
        close_index = self._close_index,
    }
    return "update_user", {update={chess={
        info = chess,
        user = user,
        start_session = info.session,
    }}}
end

function jhbj:join(info, room_card, agent, location)
    if self._status ~= base.CHESS_STATUS_READY then
        error{code = error_code.ERROR_OPERATION}
    end
    local rule = self._rule
    if rule.aa_pay and room_card < rule.single_card then
        error{code = error_code.ROOM_CARD_LIMIT}
    end
    local role = self._role
    if rule.ip then
        for i = 1, rule.user do
            local r = role[i]
            if r and r.ip == info.ip then
                error{code = error_code.IP_LIMIT}
            end
        end
    end
    local index
    for i = 1, rule.user do
        if not role[i] then
            index = i
            break
        end
    end
    if not index then
        error{code = error_code.CHESS_ROLE_FULL}
    end
    local i = self._id[info.id]
    if i then
        error{code = error_code.ALREAD_IN_CHESS}
    end
    local rmsg, rinfo = self:enter(info, agent, index, location)
    broadcast({info}, nil, role, info.id)
    return rmsg, rinfo
end

function jhbj:leave(id, msg)
    local info = self._id[id]
    if not info then
        error{code = error_code.NOT_IN_CHESS}
    end
    local role = self._role
    local index = info.index
    if self._count > 0 or self._status == base.CHESS_STATUS_START then
        if self._close_index > 0 then
            error{code = error_code.IN_CLOSE_PROCESS}
        end
        self._pause = true
        local now = floor(skynet.time())
        self._close_time = now
        self._close_index = index
        info.agree = true
        local cu = {
            {index=index, agree=true},
        }
        local ci = {pause=self._pause, close_index=index, close_time=now}
        broadcast(cu, ci, role, id)
        timer.add_once_routine("close_timer", function()
            self._status = base.CHESS_STATUS_EXIT
            self._pause = false
            self._close_index = 0
            broadcast(nil, {
                status = self._status, 
                pause = self._pause,
                close_index = self._close_index,
            }, role)
            self:finish()
        end, 180)
        return session_msg(info, cu, ci)
    elseif index == 1 then
        local cu = {
            {index=index, action=base.P13_OP_LEAVE},
        }
        broadcast(cu, nil, role, id)
        self:finish()
        return session_msg(info, cu)
    else
        self._id[id] = nil
        role[index] = nil
        skynet.call(chess_mgr, "lua", "del", id)
        if info.agent then
            skynet.call(info.agent, "lua", "action", "role", "leave")
        end
        local cu = {
            {index=index, action=base.P13_OP_LEAVE},
        }
        broadcast(cu, nil, role)
        return session_msg(info, cu)
    end
end

function jhbj:chat_info(id, msg)
    local info = self._id[id]
    if not info then
        error{code = error_code.NOT_IN_CHESS}
    end
    local cu = {
        {index=info.index, chat_text=msg.text, chat_audio=msg.audio}
    }
    broadcast(cu, nil, self._role, id)
    return session_msg(info, cu)
end

function jhbj:location_info(id, msg)
    local info = self._id[id]
    if not info then
        error{code = error_code.NOT_IN_CHESS}
    end
    info.location = msg.location
    local cu = {
        {index=info.index, location=msg.location}
    }
    broadcast(cu, nil, self._role, id)
    return session_msg(info, cu)
end

function jhbj:is_all_agree()
    local count = 0
    for k, v in ipairs(self._role) do
        if v.agree then
            count = count + 1
        end
    end
    return count > self._rule.user//2
end

function jhbj:reply(id, msg)
    local info = self._id[id]
    if not info then
        error{code = error_code.NOT_IN_CHESS}
    end
    if self._close_index == 0 then
        error{code = error_code.NOT_IN_CLOSE}
    end
    if info.agree ~= nil then
        error{code = error_code.ALREADY_REPLY}
    end
    info.agree = msg.agree
    local chess = {}
    if info.agree then
        if self:is_all_agree() then
            self._status = base.CHESS_STATUS_EXIT
            chess.status = self._status
            self._pause = false
        end
    else
        self._pause = false
    end
    local cu = {
        {index=info.index, agree=info.agree},
    }
    if not self._pause then
        self._close_index = 0
        chess.pause = self._pause
        chess.close_index = self._close_index
        timer.del_once_routine("close_timer")
        for k, v in ipairs(self._role) do
            v.agree = nil
        end
    end
    broadcast(cu, chess, self._role, id)
    if self._status == base.CHESS_STATUS_EXIT then
        self:finish()
    end
    return session_msg(info, cu, chess)
end

function jhbj:is_all_ready()
    local role = self._role
    for i = 1, self._rule.user do
        local v = role[i]
        if not v or not v.ready then
            return false
        end
    end
    return true
end

function jhbj:op_check(id, status)
    if self._status ~= status then
        error{code = error_code.ERROR_OPERATION}
    end
    local info = self._id[id]
    if not info then
        error{code = error_code.NOT_IN_CHESS}
    end
    return info
end

function jhbj:ready(id, msg)
    local info = self:op_check(id, base.CHESS_STATUS_READY)
    if info.ready then
        error{code = error_code.ALREADY_READY}
    end
    info.ready = true
    local index = info.index
    local user = {index=index, ready=true}
    local chess
    if self:is_all_ready() then
        self:start()
        -- self
        local now = floor(skynet.time())
        chess = {
            status = self._status,
            rand = now,
        }
        self._detail.info.rand = now
        user.own_card = info.deal_card
        -- other
        for k, v in ipairs(self._role) do
            if v.id ~= id then
                send(v, {
                    {index=index, ready=true}, 
                    {index=k, own_card=v.deal_card},
                }, chess)
            end
        end
    else
        broadcast({user}, chess, self._role, id)
    end
    return session_msg(info, {user}, chess)
end

function jhbj:consume_card()
    local rule = self._rule
    if rule.aa_pay then
        local count = -rule.single_card
        for k, v in ipairs(self._role) do
            skynet.call(offline_mgr, "lua", "add", v.id, "role", "add_room_card", count)
        end
    else
        local id = self._role[1].id
        local count = -rule.total_card
        skynet.call(offline_mgr, "lua", "add", id, "role", "add_room_card", count)
    end
end

local function compare(l, r)
    if l.p ~= r.p then
        return l.p > r.p
    end
    return l.v > r.v
end

local function analyze(card, ib, ie)
    local color = {}
    local value = {}
    local array = {}
    local value_color = {}
    for i = ib, ie do
        local c, v = func.poker_info(card[i])
        color[c] = (color[c] or 0) + 1
        value[v] = (value[v] or 0) + 1
        array[#array+1] = v
        value_color[v] = c
    end
    local sc = false
    for k, v in pairs(color) do
        if v == 3 then
            sc = true
        end
        break
    end
    local sv = {}
    local comp = {}
    for k, v in pairs(value) do
        sv[v] = (sv[v] or 0) + 1
        if v == 1 then
            comp[#comp+1] = {v=value_color[k], p=k}
        end
        comp[#comp+1] = {v=k, p=20+v}
    end
    table.sort(comp, compare)
    local shunzi = false
    if sv[1] == 3 then
        table.sort(array)
        if array[3] - array[1] == 2 then
            shunzi = true
        elseif array[1] == 1 and array[2] == 2 and array[3] == 13 then
            shunzi = true
            comp[1].v = 0
        end
    end
    local pt = base.PBJ_TYPE_NONE
    if sc then
        if shunzi then
            pt = base.PBJ_TYPE_TONGHUASHUN
        else
            pt = base.PBJ_TYPE_TONGHUA
        end
    else
        if shunzi then
            pt = base.PBJ_TYPE_SHUNZI
        elseif sv[3] then
            pt = base.PBJ_TYPE_SANTIAO
        elseif sv[2] then
            pt = base.PBJ_TYPE_DUIZI
        end
    end
    return {pt=pt, comp=comp, count=sv[1] or 0}
end

local function comp_2(l, r)
    if l.pt ~= r.pt then
        return l.pt > r.pt
    end
    local rcomp = r.comp
    for k, v in ipairs(l.comp) do
        local lv, rv = v.v, rcomp[k].v
        if lv ~= rv then
            return lv > rv
        end
    end
    return false
end

local function comp_1(l, r)
    return comp_2(l[2], r[2])
end

local function jintiao(v, i1, i2)
    local diff = i2 - i1
    local vb, ve = v[i1], v[i2]
    return vb-ve==diff or (vb-ve==12 and v[i1+1]-ve==diff-1)
end

local function special(extra, card, type_card)
    local color = {}
    local value = {}
    local ccount, vcount = 0, 0
    for k, v in ipairs(card) do
        local cl, vl = func.poker_info(v)
        local ci = color[cl]
        if ci then
            ci[#ci+1] = vl
        else
            ci = {vl}
            color[cl] = ci
            ccount = ccount + 1
        end
        local vi = value[vl]
        if vi then
            value[vl] = vi + 1
        else
            value[vl] = 1
            vcount = vcount + 1
        end
    end
    local count3, count4, ths = 0, 0, 0
    for k, v in ipairs(type_card) do
        if v.pt == base.PBJ_TYPE_SANTIAO then
            count3 = count3 + 1
            if value[v.comp[1].v] == 4 then
                count4 = count4 + 1
            end
        elseif v.pt == base.PBJ_TYPE_TONGHUASHUN then
            ths = ths + 1
        end
    end
    local nv = {0, 0, 0, 0}
    for k, v in pairs(value) do
        nv[v] = nv[v] + 1
    end
    if count4 == 2 then
        return base.PBJ_SPECIAL_SHUANGZHADAN
    end
    if extra then
        if vcount == 9 and jintiao(card, 1, 9) then
            if ccount == 1 then
                return base.PBJ_SPECIAL_JIULIANTONGHUASHUN
            else
                return base.PBJ_SPECIAL_JIULIANSHUN
            end
        end
        if count3 == 3 then
            return base.PBJ_SPECIAL_QUANSANTIAO
        end
        if count4 == 1 then
            return base.PBJ_SPECIAL_ZHADAN
        end
        if ths == 3 then
            return base.PBJ_SPECIAL_SANTONGHUASHUN
        end
        local pt1 = type_card[1].pt
        if pt1 >= base.PBJ_TYPE_TONGHUA then
            return base.PBJ_SPECIAL_SANQING
        end
        local pt2 = type_card[2].pt
        local pt3 = type_card[3].pt
        if pt2 == base.PBJ_TYPE_SANTIAO 
            and pt3 == base.PBJ_TYPE_SANTIAO then
            return base.PBJ_SPECIAL_SHUANGSANTIAO
        end
        if pt2 == base.PBJ_TYPE_TONGHUASHUN
            and pt3 == base.PBJ_TYPE_TONGHUASHUN then
            return base.PBJ_SPECIAL_SHUANGTONGHUASHUN
        end
        if (pt1 == base.PBJ_TYPE_SHUNZI or pt1 == base.PBJ_TYPE_TONGHUASHUN)
            and (pt2 == base.PBJ_TYPE_SHUNZI or pt2 == base.PBJ_TYPE_TONGHUASHUN)
            and (pt3 == base.PBJ_TYPE_SHUNZI or pt3 == base.PBJ_TYPE_TONGHUASHUN) then   
            return base.PBJ_SPECIAL_SANSHUNZI
        end
        local ncr, ncb = 0, 0
        for k, v in pairs(color) do
            if k == 1 or k == 3 then
                ncr = ncr + #v
            elseif k == 2 or k == 4 then
                ncb = ncb + #v
            end
        end
        if ncb == 9 then
            return base.PBJ_SPECIAL_QUANHEI
        end
        if ncr == 9 then
            return base.PBJ_SPECIAL_QUANHONG
        end
    end
    return 0
end

function jhbj:settle(info)
    local index = info.index
    local id = info.id
    local count = self._rule.user
    local role = self._role
    local scores = {0, 0, 0, 0, 0}
    if self._give_up < count then
        local len = 0
        local temp = {{}, {}, {}}
        local ng = {}
        local gscore = (1 - count) * 3
        for i = 1, count do
            local r = role[i]
            if r.give_up then
                scores[i] = scores[i] + gscore
            else
                len = len + 1
                local rt = r.type_card
                for j = 1, 3 do
                    temp[j][len] = {i, rt[j]}
                end
                ng[len] = r
            end
        end
        local gt = (count - 1) * self._give_up
        for k, v in ipairs(temp) do
            table.sort(v, comp_1)
            local total = 0
            for i = 2, len do
                local ri, score = v[i][1], i - 1
                scores[ri] = scores[ri] - score
                total = total + score
            end
            local ri = v[1][1]
            scores[ri] = scores[ri] + total + gt
        end
        for k, v in ipairs(ng) do
            if v.out_index > 0 then
                local score = base.PBJ_SPECIAL_SCORE[v.out_index]
                if not score then
                    score = count - 1
                end
                local total = 0
                for k1, v1 in ipairs(ng) do
                    if k ~= k1 then
                        local ri = v1.index
                        scores[ri] = scores[ri] - score
                        total = total + score
                    end
                end
                local ri = v.index
                scores[ri] = scores[ri] + total
            end
        end
        local mi = temp[1][1][1]
        if temp[2][1][1] == mi and temp[3][1][1] == mi then
            local total, score = 0, count - 1
            for k, v in ipairs(ng) do
                local ri = v.index
                if ri ~= mi then
                    scores[ri] = scores[ri] - score
                    total = total + score
                end
            end
            scores[mi] = scores[mi] + total
        end
    end
    self._count = self._count + 1
    if self._count == self._rule.total_count then
        self._status = base.CHESS_STATUS_FINISH
    else
        self._status = base.CHESS_STATUS_READY
    end
    if self._count == 1 then
        self:consume_card()
    end
    local user = {}
    local detail = self._detail
    local now = floor(skynet.time())
    detail.id = skynet.call(self._server, "lua", "gen_record_detail")
    local show_card = {}
    local banker = self._banker
    local record_detail = {
        id = detail.id,
        time = now,
        show_card = show_card,
        banker = banker,
    }
    local top_score, top_role
    for k, v in ipairs(role) do
        v.ready = false
        local score = scores[k]
        v.last_score = score
        local rc = v.score + score
        v.score = rc
        if not top_score or rc > top_score then
            top_score = rc
            top_role = {k}
        elseif rc == top_score then
            top_role[#top_role+1] = k
        end
        local sc = {
            own_card = v.out_card,
            last_index = v.out_index,
            score = score,
            give_up = v.give_up,
        }
        local u = {
            index = k,
            ready = v.ready,
            score = rc,
            out_index = v.out_index,
            give_up = v.give_up,
            show_card = sc,
        }
        detail.user[k].show_card = sc
        show_card[k] = sc
        if score > v.top_score then
            v.top_score = score
            u.top_score = score
        end
        if score > 0 then
            v.hu_count = v.hu_count + 1
            u.hu_count = v.hu_count
        end
        user[k] = u
    end
    local expire = bson.date(os.time())
    detail.time = now
    detail.expire = expire
    skynet.call(record_detail_db, "lua", "safe_insert", detail)
    local sr = self._record
    sr.expire = expire
    sr.time = now
    local record_id
    if sr.id then
        skynet.call(record_info_db, "lua", "update", {id=sr.id}, {
            ["$push"] = {record=record_detail},
            ["$set"] = {expire=expire, time=now},
        }, true)
    else
        record_id = skynet.call(self._server, "lua", "gen_record")
        sr.id = record_id
        local record_user = {}
        for k, v in ipairs(role) do
            record_user[k] = {
                account = v.account,
                id = v.id,
                sex = v.sex,
                nick_name = v.nick_name,
                head_img = v.head_img,
                ip = v.ip,
                index = v.index,
            }
            skynet.call(user_record_db, "lua", "update", {id=v.id}, {["$push"]={record=record_id}}, true)
        end
        sr.user = record_user
        sr.record = {record_detail}
        skynet.call(record_info_db, "lua", "safe_insert", sr)
    end
    self._old_banker = banker
    self._banker = index
    user[index].pass = true
    local win = 0
    if top_score > 0 then
        local top_len = #top_role
        if top_len == 1 then
            win = top_role[1]
        else
            win = top_role[self._rand.randi(1, top_len)]
        end
    end
    local ci = {
        status = self._status, 
        count = self._count, 
        banker = self._banker, 
        record_id = record_id,
        win = win,
    }
    broadcast(user, ci, role, id)
    if self._status == base.CHESS_STATUS_FINISH then
        self:finish()
    end
    return session_msg(info, user, ci)
end

function jhbj:is_all_out()
    local role = self._role
    for i = 1, self._rule.user do
        local v = role[i]
        if not v.out_card and not v.give_up then
            return false
        end
    end
    return true
end

function jhbj:bj_out(id, msg)
    local info = self:op_check(id, base.CHESS_STATUS_START)
    local index = info.index
    if info.out_card then
        error{code = error_code.ALREADY_OUT}
    end
    if info.give_up then
        error{code = error_code.ALREADY_GIVE_UP}
    end
    local card = msg.card
    local temp_card = util.clone(card)
    table.sort(temp_card)
    local temp_own = util.clone(info.deal_card)
    table.sort(temp_own)
    for i = 1, base.PBJ_ROLE_CARD do
        if temp_card[i] ~= temp_own[i] then
            error{code = error_code.INVALID_CARD}
        end
    end
    local type_card = {
        analyze(card, 1, 3),
        analyze(card, 4, 6),
        analyze(card, 7, 9),
    }
    if comp_2(type_card[1], type_card[2]) or comp_2(type_card[2], type_card[3]) then
        error{code = error_code.ERROR_OPERATION}
    end
    info.out_card = card
    info.type_card = type_card
    table.sort(temp_own, func.sort_poker_value)
    info.out_index = special(self._rule.extra, temp_own, type_card)
    local record_action = self._detail.action
    record_action[#record_action+1] = {
        index = index,
        out_card = card,
        type_card = type_card,
    }
    if self:is_all_out() then
        return self:settle(info)
    else
        local user = {index=index, pass=true}
        broadcast({user}, nil, self._role, id)
        return session_msg(info, {{index=index, pass=true, out_index=info.out_index}})
    end
end

function jhbj:give_up(id, msg)
    local info = self:op_check(id, base.CHESS_STATUS_START)
    local index = info.index
    if info.out_card then
        error{code = error_code.ALREADY_OUT}
    end
    if info.give_up then
        error{code = error_code.ALREADY_GIVE_UP}
    end
    if not self._rule.give_up then
        error{code = error_code.ERROR_OPERATION}
    end
    info.give_up = true
    self._give_up = self._give_up + 1
    local record_action = self._detail.action
    record_action[#record_action+1] = {
        index = index,
        give_up = true,
    }
    if self:is_all_out() then
        return self:settle(info)
    else
        local user = {index=index, pass=true}
        broadcast({user}, nil, self._role, id)
        return session_msg(info, {
            {index=index, pass=true, give_up=true},
        })
    end
end

function jhbj:start()
    local card
    if self._custom_card then
        card = util.clone(self._custom_card)
    else
        card = {}
        for i = 1, base.POKER_CARD do
            card[i] = i
        end
        util.shuffle(card, self._rand)
    end
    self._card = card
    self._status = base.CHESS_STATUS_START
    self._old_banker = nil
    self._give_up = 0
    local left = #card
    local role = self._role
    local record_user = {}
    local rule = self._rule
    for j = 1, rule.user do
        local index = (self._banker+j-2)%rule.user+1
        local v = role[index]
        v.out_card = nil
        v.out_index = 0
        v.type_card = nil
        v.give_up = false
        local deal_card = {}
        for i = 1, base.PBJ_ROLE_CARD do
            local c = card[(i-1)*rule.user+j]
            deal_card[i] = c
        end
        left = left - base.PBJ_ROLE_CARD
        v.deal_card = deal_card
        record_user[index] = {
            account = v.account,
            id = v.id,
            sex = v.sex,
            nick_name = v.nick_name,
            head_img = v.head_img,
            ip = v.ip,
            index = index,
            score = v.score,
            own_card = deal_card,
        }
    end
    self._detail = {
        info = {
            name = "jhbj",
            number = self._number,
            rule = rule.pack,
            banker = self._banker,
            count = self._count,
        },
        user = record_user,
        action = {},
    }
end

return {__index=jhbj}
