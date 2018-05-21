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
local club_mgr
local activity_mgr

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
    club_mgr = skynet.queryservice("club_mgr")

    activity_mgr = skynet.queryservice("activity_mgr")
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

local function play(role) --完成一牌局
    local id = {}
    for k, v in pairs(role) do
        id[k] = v.id
    end

    skynet.send(activity_mgr, "lua", "play", id)
end

local function play_winner(role, winner) --大赢家
    local id = {}
    for k, v in pairs(role) do
        id[k] = v.id
    end

    local w = id[winner]
    if (w) then --大赢家
        skynet.send(activity_mgr, "lua", "top_win", w)
    end
end

local dy13 = {}

function dy13:init(number, rule, rand, server, card, club)
    self._number = number
    self._rule = rule
    self._rand = rand
    self._server = server
    self._custom_card = card
    self._club = club
    self._banker = 1
    self._status = base.CHESS_STATUS_READY
    self._role = {}
    self._id = {}
    self._count = 0
    self._pause = false
    self._close_index = 0
    self._record = {
        info = {
            name = "dy13",
            number = number,
            rule = rule.pack,
            club = club,
        },
    }
    if club then
        local c = skynet.call(club_mgr, "lua", "get_by_id", club)
        if c then
            skynet.call(c, "lua", "add_room", {
                name = "dy13",
                number = number,
                rule = rule.pack,
                user = rule.user,
            })
        end
    end
end

function dy13:status(id, status, addr)
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

function dy13:destroy()
    timer.del_once_routine("close_timer")
end

local function finish()
    skynet.call(skynet.self(), "lua", "destroy")
    skynet.call(table_mgr, "lua", "free", skynet.self())
end
function dy13:finish()
    local role = self._role

    -- 大赢家
    if (self.win_idx) then
        play_winner(role, self.win_idx)
    end
    self.win_idx = nil

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
    if self._club then
        local club = skynet.call(club_mgr, "lua", "get_by_id", self._club)
        if club then
            skynet.call(club, "lua", "del_room", self._number)
        end
    end
    skynet.fork(finish)
end

function dy13:custom_card(name, card)
    if name ~= "dy13" then
        error{code = error_code.ERROR_CHESS_NAME}
    end
    self._custom_card = card
    return "response", ""
end

function dy13:pack(id, ip, agent)
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
                name = "dy13",
                number = self._number,
                rule = rule.pack,
                banker = self._banker,
                status = status,
                count = self._count,
                pause = self._pause,
                old_banker = self._old_banker,
                close_index = self._close_index,
                close_time = self._close_time,
                record_id = self._record.id,
                club = self._club,
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
                        location = info.location,
                    }
                    if info.out_card then
                        local show_card = {
                            own_card = info.out_card,
                            last_index = info.out_index,
                            score = info.last_score,
                        }
                        u.show_card = show_card
                    end
                    user[#user+1] = u
                end
            end
            return {info=chess, user=user, start_session=si.session}
        elseif status == base.CHESS_STATUS_START then
            local chess = {
                name = "dy13",
                number = self._number,
                rule = rule.pack,
                banker = self._banker,
                status = status,
                count = self._count,
                pause = self._pause,
                close_index = self._close_index,
                close_time = self._close_time,
                record_id = self._record.id,
                club = self._club,
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
                        pass = info.out_card~=nil,
                    }
                    if info.id == id then
                        u.own_card = info.deal_card
                        u.out_card = info.out_card
                        u.out_index = info.out_index
                    end
                    user[#user+1] = u
                end
            end
            return {info=chess, user=user, start_session=si.session}
        end
    end
end

function dy13:enter(info, agent, index, location)
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
    if self._club then
        local club = skynet.call(club_mgr, "lua", "get_by_id", self._club)
        if club then
            skynet.call(club, "lua", "enter_room", self._number, {
                id = info.id,
                name = info.nick_name or info.account,
                head_img = info.head_img,
                sex = info.sex,
            })
        end
    end
    local user = {}
    local rule = self._rule
    for i = 1, rule.user do
        user[#user+1] = role[i] -- role[i] can be nil
    end
    local chess = {
        name = "dy13",
        number = self._number,
        rule = rule.pack,
        banker = self._banker,
        status = self._status,
        count = self._count,
        pause = self._pause,
        close_index = self._close_index,
        club = self._club,
    }
    return "update_user", {update={chess={
        info = chess,
        user = user,
        start_session = info.session,
    }}}
end

function dy13:join(info, room_card, agent, location)
    -- if self._status ~= base.CHESS_STATUS_READY then
    --     error{code = error_code.ERROR_OPERATION}
    -- end
    local rule = self._rule
    if self._club then
        local club = skynet.call(club_mgr, "lua", "get_by_id", self._club)
        if club then
            local cr = skynet.call(club, "lua", "check_role_day_card", info.id)
            if cr == nil then
                error{code = error_code.NOT_IN_CLUB}
            end
            if not cr then
                error{code = error_code.CLUB_DAY_CARD_LIMIT}
            end
        end
    else
        if rule.aa_pay and room_card < rule.single_card then
            error{code = error_code.ROOM_CARD_LIMIT}
        end
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

function dy13:leave(id, msg)
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
        if self._club then
            local club = skynet.call(club_mgr, "lua", "get_by_id", self._club)
            if club then
                skynet.call(club, "lua", "leave_room", self._number, id)
            end
        end
        local cu = {
            {index=index, action=base.P13_OP_LEAVE},
        }
        broadcast(cu, nil, role)
        return session_msg(info, cu)
    end
end

function dy13:chat_info(id, msg)
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

function dy13:location_info(id, msg)
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

function dy13:is_all_agree()
    local count = 0
    for k, v in ipairs(self._role) do
        if v.agree then
            count = count + 1
        end
    end
    return count > self._rule.user//2
end

function dy13:reply(id, msg)
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

function dy13:is_all_ready()
    local role = self._role
    for i = 1, self._rule.user do
        local v = role[i]
        if not v or not v.ready then
            return false
        end
    end
    return true
end

function dy13:op_check(id, status)
    if self._status ~= status then
        error{code = error_code.ERROR_OPERATION}
    end
    local info = self._id[id]
    if not info then
        error{code = error_code.NOT_IN_CHESS}
    end
    return info
end

function dy13:ready(id, msg)
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

function dy13:consume_card()
    local rule = self._rule
    if self._club then
        local club = skynet.call(club_mgr, "lua", "get_by_id", self._club)
        if club then
            skynet.call(club, "lua", "consume_card", self._number, rule.total_card, rule.single_card)
        end
    else
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

    skynet.send(activity_mgr, "lua", "consume_room_succ", {self._role[1].id,}) --有效创建房间
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
        if v == 5 then
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
    if sv[1] == 5 then
        table.sort(array)
        if array[5] - array[1] == 4 then
            shunzi = true
        elseif array[1] == 1 and array[4] == 4 and array[5] == 13 then
            shunzi = true
        end
    end
    local pt = base.P13_TYPE_NONE
    if sc then
        if shunzi then
            pt = base.P13_TYPE_TONGHUASHUN
        else
            pt = base.P13_TYPE_TONGHUA
        end
    else
        if shunzi then
            pt = base.P13_TYPE_SHUNZI
        elseif sv[4] then
            pt = base.P13_TYPE_ZHADAN
        elseif sv[3] then
            if sv[2] then
                pt = base.P13_TYPE_HULU
            else
                pt = base.P13_TYPE_SANZHANG
            end
        elseif sv[2] then
            if sv[2] == 2 then
                pt = base.P13_TYPE_LIANGDUI
            else
                pt = base.P13_TYPE_DUIZI
            end
        end
    end
    return {pt=pt, comp=comp, count=sv[1] or 0}
end

local function comp_1(l, r)
    if l.pt ~= r.pt then
        return l.pt > r.pt
    end
    local lcomp = l.comp
    local rcomp = r.comp
    local rc = {}
    for i = 1, #lcomp-l.count do
        rc[i] = rcomp[i]
    end
    local b = #rcomp - r.count
    for i = b+1, b+l.count do
        rc[#rc+1] = rcomp[i]
    end
    for k, v in ipairs(lcomp) do
        local lv, rv = v.v, rc[k].v
        if lv ~= rv then
            return lv > rv
        end
    end
    return false
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

local function comp_3(l, r)
    if comp_2(l, r) then
        return 1, l.pt
    else
        return -1, r.pt
    end
end

function dy13:settle(info)
    local index = info.index
    local id = info.id
    local count = self._rule.user
    local role = self._role
    local scores = {0, 0, 0, 0}
    local shoot = {0, 0, 0, 0}
    local single = {
        {0, 0, 0, 0},
        {0, 0, 0, 0},
        {0, 0, 0, 0},
        {0, 0, 0, 0},
    }
    for i = 1, count do
        for j = i+1, count do
            local score = 0
            local lr, rr = role[i], role[j]
            local spe = false
            if lr.out_index > 0 then
                score = score + func.p13_special_score(lr.out_index)
                spe = true
            end
            if rr.out_index > 0 then
                score = score - func.p13_special_score(rr.out_index)
                spe = true
            end
            if not spe then
                local wc = 0
                local lt, rt = lr.type_card, rr.type_card
                local w1, wt1 = comp_3(lt[1], rt[1])
                wc = wc + w1
                if wt1 == base.P13_TYPE_SANZHANG then
                    score = score + w1 * 3
                else
                    score = score + w1
                end
                local w2, wt2 = comp_3(lt[2], rt[2])
                wc = wc + w2
                if wt2 == base.P13_TYPE_TONGHUASHUN then
                    score = score + w2 * 10
                elseif wt2 == base.P13_TYPE_ZHADAN then
                    score = score + w2 * 8
                elseif wt2 == base.P13_TYPE_HULU then
                    score = score + w2 * 2
                else
                    score = score + w2
                end
                local w3, wt3 = comp_3(lt[3], rt[3])
                wc = wc + w3
                if wt3 == base.P13_TYPE_TONGHUASHUN then
                    score = score + w3 * 5
                elseif wt3 == base.P13_TYPE_ZHADAN then
                    score = score + w3 * 4
                else
                    score = score + w3
                end
                if wc == 3 then
                    score = score * 2
                    shoot[i] = shoot[i] + 1
                elseif wc == -3 then
                    score = score * 2
                    shoot[j] = shoot[j] + 1
                end
            end
            if lr.key or rr.key then
                score = score * 2
            end
            single[i][j] = score
            scores[i] = scores[i] + score
            single[j][i] = -score
            scores[j] = scores[j] - score
        end
    end
    local all_shoot = count - 1
    if all_shoot > 1 then
        for i = 1, count do
            if shoot[i] == all_shoot then
                for j = 1, count do
                    if j ~= i then
                        scores[i] = scores[i] + single[i][j]
                        scores[j] = scores[j] + single[j][i]
                    end
                end
            end
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
        }
        local u = {
            index = k,
            ready = v.ready,
            score = rc,
            out_index = v.out_index,
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
    local win = 0
    if top_score > 0 then
        local top_len = #top_role
        if top_len == 1 then
            win = top_role[1]
        else
            win = top_role[self._rand.randi(1, top_len)]
        end
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
            ["$set"] = {expire=expire, time=now, winner=win},
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
            if self._club then
                skynet.call(user_record_db, "lua", "update", {id=v.id}, {["$push"]={club_record=record_id}}, true)
            else
                skynet.call(user_record_db, "lua", "update", {id=v.id}, {["$push"]={record=record_id}}, true)
            end
        end
        sr.user = record_user
        sr.clubid = self._club
        sr.read = false
        sr.record = {record_detail}
        sr.winner = win
        skynet.call(record_info_db, "lua", "safe_insert", sr)
    end
    self._old_banker = banker
    self._banker = index
    user[index].pass = true
    local ci = {
        status = self._status, 
        count = self._count, 
        banker = self._banker, 
        record_id = record_id,
        win = win,
    }
    self.win_idx = win

    play(role) -- 完成一牌局

    broadcast(user, ci, role, id)
    if self._status == base.CHESS_STATUS_FINISH then
        self:finish()
       
    end
    return session_msg(info, user, ci)
end

function dy13:is_all_out()
    local role = self._role
    for i = 1, self._rule.user do
        local v = role[i]
        if not v.out_card then
            return false
        end
    end
    return true
end

function dy13:thirteen_out(id, msg)
    local info = self:op_check(id, base.CHESS_STATUS_START)
    local index = info.index
    if info.out_card then
        error{code = error_code.ALREADY_OUT}
    end
    local card = msg.card
    local temp_card = util.clone(card)
    table.sort(temp_card)
    local temp_own = util.clone(info.deal_card)
    table.sort(temp_own)
    for i = 1, base.P13_ROLE_CARD do
        if temp_card[i] ~= temp_own[i] then
            error{code = error_code.INVALID_CARD}
        end
    end
    local type_card = {
        analyze(card, 1, 3),
        analyze(card, 4, 8),
        analyze(card, 9, 13),
    }
    if comp_1(type_card[1], type_card[2]) or comp_2(type_card[2], type_card[3]) then
        error{code = error_code.ERROR_OPERATION}
    end
    info.out_card = card
    info.type_card = type_card
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
        return session_msg(info, {user})
    end
end

local function jintiao(v, i1, i2)
    local diff = i2 - i1
    local vb, ve = v[i1], v[i2]
    return vb-ve==diff or (vb-ve==12 and v[i1+1]-ve==diff-1)
end
local function jintiao_1(v, i, i1, i2)
    local diff = i2 - i1 + 1
    local vb, ve = v[i], v[i2]
    return vb-ve==diff or (vb-ve==12 and v[i1]-ve==diff-1)
end
local function sanjintiao(color)
    for k, v in pairs(color) do
        local len = #v
        if len == 3 then
            if not jintiao(v, 1, 3) then
                return false
            end
        elseif len == 5 then
            if not jintiao(v, 1, 5) then
                return false
            end
        elseif len == 8 then
            if not ((jintiao(v, 1, 5) and jintiao(v, 6, 8)) 
                or (jintiao(v, 1, 3) and jintiao(v, 4, 8))
                or (jintiao_1(v, 1, 5, 8) and jintiao(v, 2, 4))
                or (jintiao_1(v, 1, 7, 8) and jintiao(v, 2, 6))) then
                return false
            end
        else
            return false
        end
    end
    return true
end
local function santonghua(color)
    local c3
    for k, v in pairs(color) do
        local len = #v
        if len==3 or len==8 then
            c3 = k
        elseif len ~= 5 then
            return false
        end
    end
    return true, c3
end
local function shunzi_switch(s, vi)
    local len = #vi
    s[#s+1] = vi[len]
    vi[len] = nil
end
local shunzi_find
local function shunzi_check(v, ib, i1, i2, w)
    for i = i1, i2 do
        if #v[i] == 0 then
            return false
        end
    end
    local s = {}
    shunzi_switch(s, v[ib])
    for i = i2, i1, -1 do
        shunzi_switch(s, v[i])
    end
    w[#w+1] = s
    local nb
    for i = ib, 1, -1 do
        if #v[i] > 0 then
            nb = i
            break
        end
    end
    if nb then
        if shunzi_find(v, nb, w) then
            return true
        else
            for k1, v1 in ipairs(s) do
                local o = v1[2]
                o[#o+1] = v1
            end
            w[#w] = nil
            return false
        end
    else
        return true
    end
end
shunzi_find = function(v, ib, w)
    if ib == 13 then
        if shunzi_check(v, ib, 1, 4, w) then
            return true
        end
        if shunzi_check(v, ib, 1, 2, w) then
            return true
        end
    end
    if ib >= 5 and shunzi_check(v, ib, ib-4, ib-1, w) then
        return true
    end
    if ib >= 3 and shunzi_check(v, ib, ib-2, ib-1, w) then
        return true
    end
    return false
end
local function sanshunzi(value)
    local ib
    local nv = {}
    for i = 1, base.POKER_VALUE do
        local o = {}
        local v = value[i]
        if v then
            for k1, v1 in ipairs(v) do
                o[k1] = {v1, o}
            end
            ib = i
        end
        nv[i] = o
    end
    local w = {}
    return shunzi_find(nv, ib, w), w
end
local function sort_shunzi(l, r)
    return #l < #r
end
local function special(card)
    local color = {}
    local value = {}
    local color_value = {}
    local ccount, vcount = 0, 0
    for k, v in ipairs(card) do
        local cl, vl = func.poker_info(v)
        local ci = color[cl]
        if ci then
            ci[#ci+1] = vl
            local cv = color_value[cl]
            cv[#cv+1] = v
        else
            ci = {vl}
            color[cl] = ci
            color_value[cl] = {v}
            ccount = ccount + 1
        end
        local vi = value[vl]
        if vi then
            vi[#vi+1] = v
        else
            vi = {v}
            value[vl] = vi
            vcount = vcount + 1
        end
    end
    if ccount == 1 then
        return base.P13_SPECIAL_QINGLONG
    end
    if vcount == 13 then
        return base.P13_SPECIAL_YITIAOLONG
    end
    -- if sanjintiao(color) then
    --     return base.P13_SPECIAL_SANJINTIAO
    -- end
    local nv = {0, 0, 0, 0}
    local nb, ns = 0, 0
    for k, v in pairs(value) do
        local len = #v
        nv[len] = nv[len] + 1
        if k >= 7 then
            nb = nb + len
        end
        if k <= 7 then
            ns = ns + len
        end
    end
    -- if nv[4] == 3 then
    --     return base.P13_SPECIAL_SANZHADAN
    -- end
    -- if nb == 13 then
    --     return base.P13_SPECIAL_QUANDA
    -- end
    -- if ns == 13 then
    --     return base.P13_SPECIAL_QUANXIAO
    -- end
    local ncr, ncb = 0, 0
    for k, v in pairs(color) do
        if k == 1 or k == 3 then
            ncr = ncr + #v
        elseif k == 2 or k == 4 then
            ncb = ncb + #v
        end
    end
    if ncb == 13 then
        return base.P13_SPECIAL_QUANHEI
    end
    if ncr == 13 then
        return base.P13_SPECIAL_QUANHONG
    end
    local count2 = nv[2] + nv[4] * 2
    -- if count2 == 5 and nv[3] == 1 then
    --     return base.P13_SPECIAL_WUDUIYIKE
    -- end
    if nv[1] + nv[3] == 1 then
        return base.P13_SPECIAL_LIUDUIBAN
    end
    if nv[3] == 4 then
        return base.P13_SPECIAL_SISANTIAO
    end
    local santh, c3 = santonghua(color)
    if santh then
        local ac = {1, 2, 3, 4}
        table.sort(ac, function(l, r)
            if l == c3 then
                return true
            end
            if r == c3 then
                return false
            end
            return l < r
        end)
        local si = 1
        for k, v in ipairs(ac) do
            local cv = color_value[v]
            if cv then
                for k1, v1 in ipairs(cv) do
                    card[si] = v1
                    si = si + 1
                end
            end
        end
        return base.P13_SPECIAL_SANTONGHUA
    end
    local sansz, w = sanshunzi(value)
    if sansz then
        table.sort(w, sort_shunzi)
        local si = 1
        for k, v in ipairs(w) do
            for k1, v1 in ipairs(v) do
                card[si] = v1[1]
                si = si + 1
            end
        end
        return base.P13_SPECIAL_SANSHUNZI
    end
    return 0
end
function dy13:p13_call(id, msg)
    local info = self:op_check(id, base.CHESS_STATUS_START)
    local index = info.index
    if info.out_card then
        error{code = error_code.ALREADY_OUT}
    end
    local temp_own = util.clone(info.deal_card)
    table.sort(temp_own, func.sort_poker_value)
    local out_index = special(temp_own)
    if out_index == 0 then
        error{code = error_code.ERROR_OPERATION}
    end
    info.out_card = temp_own
    info.out_index = out_index
    local record_action = self._detail.action
    record_action[#record_action+1] = {
        index = index,
        out_card = temp_own,
        out_index = out_index,
    }
    if self:is_all_out() then
        return self:settle(info)
    else
        local user = {index=index, pass=true}
        broadcast({user}, nil, self._role, id)
        return session_msg(info, {
            {index=index, pass=true, out_index=out_index},
        })
    end
end

function dy13:start()
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
        v.key = nil
        local deal_card = {}
        for i = 1, base.P13_ROLE_CARD do
            local c = card[left+1-((i-1)*rule.user+j)]
            if c == rule.key then
                v.key = true
            end
            deal_card[i] = c
        end
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
	-- left = left - rule.user * base.P13_ROLE_CARD
    self._detail = {
        info = {
            name = "dy13",
            number = self._number,
            rule = rule.pack,
            banker = self._banker,
            count = self._count,
            club = self._club,
        },
        user = record_user,
        action = {},
    }
end

return {__index=dy13}
