local skynet = require "skynet"
local share = require "share"
local util = require "util"
local timer = require "timer"
local bson = require "bson"

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
    return c>0 and c<=base.POKER_CARD_INDEX
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
            local chess
            if self._status == base.CHESS_STATUS_DEAL and not info.deal_end then
                info.deal_end = true
                user.deal_end = true
                if self:is_all_deal() then
                    self._status = base.CHESS_STATUS_START
                    chess = {status=self._status}
                end
            end
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
    for i = 1, base.P13_FOUR do
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
        if status == base.CHESS_STATUS_READY then
            local chess = {
                name = "jd13",
                number = self._number,
                rule = self._rule.pack,
                banker = self._banker,
                status = status,
                count = self._count,
                pause = self._pause,
                old_banker = self._old_banker,
                close_index = self._close_index,
                close_time = self._close_time,
            }
            local user = {}
            for i = 1, base.P13_FOUR do
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
                        deal_end = info.deal_end,
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
        elseif status == base.CHESS_STATUS_START or status == base.CHESS_STATUS_DEAL then
            local chess = {
                name = "jd13",
                number = self._number,
                rule = self._rule.pack,
                banker = self._banker,
                status = status,
                count = self._count,
                pause = self._pause,
                close_index = self._close_index,
                close_time = self._close_time,
            }
            local user = {}
            for i = 1, base.P13_FOUR do
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
                        deal_end = info.deal_end,
                        agree = info.agree,
                        top_score = info.top_score,
                        hu_count = info.hu_count,
                        status = info.status,
                        pass = info.pass,
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
    info.deal_end = false
    info.hu_count = 0
    info.top_score = 0
    info.session = 1
    info.status = base.USER_STATUS_ONLINE
    role[index] = info
    self._id[info.id] = info
    skynet.call(chess_mgr, "lua", "add", info.id, skynet.self())
    local user = {}
    for i = 1, base.P13_FOUR do
        user[#user+1] = role[i] -- role[i] can be nil
    end
    local chess = {
        name = "jd13",
        number = self._number,
        rule = self._rule.pack,
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

function jd13:join(name, info, room_card, agent)
    if name ~= "jd13" then
        error{code = error_code.ERROR_CHESS_NAME}
    end
    if self._status ~= base.CHESS_STATUS_READY then
        error{code = error_code.ERROR_OPERATION}
    end
    if self._rule.aa_pay and room_card < self._rule.single_card then
        error{code = error_code.ROOM_CARD_LIMIT}
    end
    local role = self._role
    local index
    for i = 1, self._rule.user do
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
    if self._count > 0 or self._status == base.CHESS_STATUS_START
        or self._status == base.CHESS_STATUS_DEAL then
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
    return count >= (self._rule.user+1)//2
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

function jd13:is_all_deal()
    local role = self._role
    for i = 1, self._rule.user do
        local v = role[i]
        if not v.deal_end then
            return false
        end
    end
    return true
end

function jd13:deal_end(id, msg)
    local info = self:op_check(id, base.CHESS_STATUS_DEAL)
    if info.deal_end then
        error{code = error_code.ALREADY_DEAL_END}
    end
    info.deal_end = true
    local user = {index=info.index, deal_end=true}
    local chess
    if self:is_all_deal() then
        self._status = base.CHESS_STATUS_START
        chess = {status=self._status}
    end
    broadcast({user}, chess, self._role, id)
    return session_msg(info, {user}, chess)
end

function jd13:consume_card()
    if self._rule.aa_pay then
        local count = -self._rule.single_card
        for k, v in ipairs(self._role) do
            skynet.call(offline_mgr, "lua", "add", v.id, "role", "add_room_card", count)
        end
    else
        local id = self._role[1].id
        local count = -self._rule.total_card
        skynet.call(offline_mgr, "lua", "add", id, "role", "add_room_card", count)
    end
end

function jd13:settle()

    local info = self:op_check(id, base.CHESS_STATUS_START)
    local index = info.index
    if self._deal_index ~= index then
        error{code = error_code.ERROR_OPERATION}
    end
    if self._pass_status ~= base.PASS_STATUS_DEAL then
        error{code = error_code.ERROR_OPERATION}
    end
    if info.pass then
        error{code = error_code.ALREADY_PASS}
    end
    if self._can_out ~= index then
        error{code = error_code.ERROR_OPERATION}
    end
    local type_card = info.type_card
    local magic_card = self._magic_card
    local deal_card = self._deal_card
    local mul = 1
    local tc = {}
    for k, v in pairs(type_card) do
        if v > 0 then
            tc[k] = v
        end
    end
    local magic_count = tc[magic_card] or 0
    tc[magic_card] = nil
    local hu, four_count, mc = is_qidui(tc, magic_count)
    local hu_type
    if hu then
        hu_type = base.HU_DUIZI
        mul = 2^(four_count+1)
        if (deal_card ~= magic_card and tc[deal_card]%2 == 1)
            or (deal_card == magic_card and mc > 0) then
            mul = mul * 2^(info.out_magic+1)
        elseif tc[magic_card] == 0 then
            mul = mul * 2
        end
    else
        local weave_card = {}
        if not self:check_hu(tc, weave_card, magic_count) then
            error{code = error_code.ERROR_OPERATION}
        end
        hu_type = base.HU_NONE
        local head = weave_card[1]
        if head[1] == deal_card and head[2] == 0 then
            if info.gang_count > 0 then
                hu_type = base.HU_GANGBAO
            else
                hu_type = base.HU_BAOTOU
            end
            mul = 2^info.gang_count
            mul = mul * 2^(info.out_magic+1)
        else
            local out_card = info.out_card
            local len = #out_card
            if len == 0 or out_card[len] ~= magic_card then
                if info.gang_count > 0 then
                    hu_type = base.HU_GANGKAI
                end
                mul = 2^info.gang_count
            end
        end
    end
    local banker = self._banker
    local scores
    if index == banker then
        local ts = -mul * 8
        scores = {ts, ts, ts, ts}
        scores[index] = mul * 24
    else
        scores = {-mul, -mul, -mul, -mul}
        scores[banker] = -mul * 8
        scores[index] = mul * 10
    end
    self:clear_all_op()
    info.hu_count = info.hu_count + 1
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
    local role = self._role
    local detail = self._detail
    local record_action = detail.action
    record_action[#record_action+1] = {
        index = index,
        op = base.MJ_OP_HU,
    }
    detail.id = skynet.call(self._server, "lua", "gen_record_detail")
    local record_score = {}
    detail.score = record_score
    local record_detail = {
        id = detail.id,
        time = detail.time,
        score = record_score,
    }
    for k, v in ipairs(role) do
        v.ready = false
        v.deal_end = false
        local score = scores[k]
        record_score[k] = score
        v.last_score = score
        v.score = v.score + score
        local own_card = {}
        for k1, v1 in pairs(v.type_card) do
            for i = 1, v1 do
                own_card[#own_card+1] = k1
            end
        end
        local u = {
            index = k,
            ready = v.ready,
            deal_end = v.deal_end,
            score = v.score,
            show_card = {
                own_card = own_card,
                score = score,
            },
        }
        if score > v.top_score then
            v.top_score = score
            u.top_score = score
        end
        user[k] = u
    end
    local now = floor(skynet.time())
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
    info.last_hu = {
        last_deal = info.last_deal,
        hu = hu_type,
    }
    local win = user[index]
    win.hu_count = info.hu_count
    win.action = base.MJ_OP_HU
    local ws = win.show_card
    ws.last_deal = info.last_deal
    ws.hu = hu_type
    self._old_banker = banker
    self._banker = index
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
            error{code = error_code.CARD_MISMATCH}
        end
    end
    -- TODO: check reverse
    info.out_card = card
    local record_action = self._detail.action
    record_action[#record_action+1] = {
        index = index,
        out_card = card,
    }
    if self:is_all_out() then
        return self:settle()
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
        for i = 1, base.POKER_CARD_INDEX do
            card[i] = i
        end
        util.shuffle(card, self._rand)
    end
    self._card = card
    self._status = base.CHESS_STATUS_DEAL
    self._old_banker = nil
    local left = #card
    local role = self._role
    local record_user = {}
    for j = 1, self._rule.user do
        local index = (self._banker+j-2)%base.P13_FOUR+1
        local v = role[index]
        v.out_card = nil
        local deal_card = {}
        for i = 1, base.P13_ROLE_CARD do
            local c = card[left]
            left = left - 1
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
    self._detail = {
        info = {
            name = "jd13",
            number = self._number,
            rule = self._rule.pack,
            banker = self._banker,
            count = self._count,
        },
        user = record_user,
        action = {},
    }
end

return {__index=jd13}
