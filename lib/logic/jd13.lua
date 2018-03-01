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

local jd13 = {}

function jd13:init(number, rule, rand, server, card)
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
            name = "jd13",
            number = number,
            rule = rule.pack,
        },
    }
end

function jd13:status(id, status, addr)
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

function jd13:destroy()
    timer.del_once_routine("close_timer")
end

local function finish()
    skynet.call(skynet.self(), "lua", "destroy")
    skynet.call(table_mgr, "lua", "free", skynet.self())
end
function jd13:finish()
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

function jd13:custom_card(name, card)
    if name ~= "jd13" then
        error{code = error_code.ERROR_CHESS_NAME}
    end
    self._custom_card = card
    return "response", ""
end

function jd13:pack(id, ip, agent)
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
                name = "jd13",
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
                    }
                    if info.out_card then
                        local show_card = {
                            own_card = info.out_card,
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
                name = "jd13",
                number = self._number,
                rule = rule.pack,
                banker = self._banker,
                status = status,
                count = self._count,
                pause = self._pause,
                close_index = self._close_index,
                close_time = self._close_time,
                record_id = self._record.id,
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
                        pass = info.out_card~=nil,
                    }
                    if info.id == id then
                        u.own_card = info.deal_card
                        u.out_card = info.out_card
                    end
                    user[#user+1] = u
                end
            end
            return {info=chess, user=user, start_session=si.session}
        end
    end
end

function jd13:enter(info, agent, index)
    local role = self._role
    assert(not role[index], string.format("Seat %d already has role.", index))
    info.agent = agent
    info.index = index
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
        name = "jd13",
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

function jd13:join(info, room_card, agent)
    -- if self._status ~= base.CHESS_STATUS_READY then
    --     error{code = error_code.ERROR_OPERATION}
    -- end
    local rule = self._rule
    if rule.aa_pay and room_card < rule.single_card then
        error{code = error_code.ROOM_CARD_LIMIT}
    end
    local role = self._role
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
    local rmsg, rinfo = self:enter(info, agent, index)
    broadcast({info}, nil, role, info.id)
    return rmsg, rinfo
end

function jd13:leave(id, msg)
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

function jd13:chat_info(id, msg)
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

function jd13:is_all_agree()
    local count = 0
    for k, v in ipairs(self._role) do
        if v.agree then
            count = count + 1
        end
    end
    return count > self._rule.user//2
end

function jd13:reply(id, msg)
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

function jd13:is_all_ready()
    local role = self._role
    for i = 1, self._rule.user do
        local v = role[i]
        if not v or not v.ready then
            return false
        end
    end
    return true
end

function jd13:op_check(id, status)
    if self._status ~= status then
        error{code = error_code.ERROR_OPERATION}
    end
    local info = self._id[id]
    if not info then
        error{code = error_code.NOT_IN_CHESS}
    end
    return info
end

function jd13:ready(id, msg)
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

function jd13:consume_card()
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

function jd13:settle(info)
    local index = info.index
    local id = info.id
    local count = self._rule.user
    local role = self._role
    local scores = {0, 0, 0, 0}
    local shoot = {0, 0, 0, 0}
    for i = 1, count do
        for j = i+1, count do
            local wc = 0
            local score = 0
            local extra = 0
            local lr, rr = role[i], role[j]
            local lt, rt = lr.type_card, rr.type_card
            local w1, wt1 = comp_3(lt[1], rt[1])
            wc = wc + w1
            if wt1 == base.P13_TYPE_SANZHANG then
                score = score + w1 * 3
                extra = extra + 1
            else
                score = score + w1
            end
            local w2, wt2 = comp_3(lt[2], rt[2])
            wc = wc + w2
            if wt2 == base.P13_TYPE_TONGHUASHUN then
                score = score + w2 * 10
                extra = extra + 1
            elseif wt2 == base.P13_TYPE_ZHADAN then
                score = score + w2 * 8
                extra = extra + 1
            elseif wt2 == base.P13_TYPE_HULU then
                score = score + w2 * 2
                extra = extra + 1
            else
                score = score + w2
            end
            local w3, wt3 = comp_3(lt[3], rt[3])
            wc = wc + w3
            if wt3 == base.P13_TYPE_TONGHUASHUN then
                score = score + w3 * 5
                extra = extra + 1
            elseif wt3 == base.P13_TYPE_ZHADAN then
                score = score + w3 * 4
                extra = extra + 1
            else
                score = score + w3
            end
            if wc == 3 then
                score = score + 3 + extra
                shoot[i] = shoot[i] + 1
            elseif wc == -3 then
                score = score - 3 - extra
                shoot[j] = shoot[j] + 1
            end
            if lr.key or rr.key then
                score = score * 2
            end
            scores[i] = scores[i] + score
            scores[j] = scores[j] - score
        end
    end
    local all_shoot = count - 1
    if all_shoot > 1 then
        for i = 1, count do
            if shoot[i] == all_shoot then
                local lr = role[i]
                for j = 1, count do
                    if j ~= i then
                        local rr = role[j]
                        if lr.key or rr.key then
                            scores[i] = scores[i] + 14
                            scores[j] = scores[j] - 14
                        else
                            scores[i] = scores[i] + 7
                            scores[j] = scores[j] - 7
                        end
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
    for k, v in ipairs(role) do
        v.ready = false
        local score = scores[k]
        v.last_score = score
        v.score = v.score + score
        local sc = {
            own_card = v.out_card,
            score = score,
        }
        local u = {
            index = k,
            ready = v.ready,
            score = v.score,
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
    local ci = {
        status=self._status, count=self._count, banker=self._banker, record_id=record_id
    }
    broadcast(user, ci, role, id)
    if self._status == base.CHESS_STATUS_FINISH then
        self:finish()
    end
    return session_msg(info, user, ci)
end

function jd13:is_all_out()
    local role = self._role
    for i = 1, self._rule.user do
        local v = role[i]
        if not v.out_card then
            return false
        end
    end
    return true
end

function jd13:thirteen_out(id, msg)
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

function jd13:start()
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
            name = "jd13",
            number = self._number,
            rule = rule.pack,
            banker = self._banker,
            count = self._count,
        },
        user = record_user,
        action = {},
    }
end

return {__index=jd13}
