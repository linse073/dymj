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
local mj_invalid_card
local user_record_db
local record_info_db
local record_detail_db
local table_mgr
local chess_mgr
local offline_mgr

skynet.init(function()
    base = share.base
    error_code = share.error_code
    mj_invalid_card = share.mj_invalid_card
    local master = skynet.queryservice("mongo_master")
    user_record_db = skynet.call(master, "lua", "get", "user_record")
    record_info_db = skynet.call(master, "lua", "get", "record_info")
    record_detail_db = skynet.call(master, "lua", "get", "record_detail")
    table_mgr = skynet.queryservice("table_mgr")
    chess_mgr = skynet.queryservice("chess_mgr")
    offline_mgr = skynet.queryservice("offline_mgr")
end)

local function valid_card(c)
    return c>0 and c<=base.MJ_CARD_INDEX and not mj_invalid_card[c]
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

local dymj = {}

function dymj:init(number, rule, rand, server, card)
    self._number = number
    self._rule = rule
    self._rand = rand
    self._server = server
    self._custom_card = card
    self._magic_card = 45
    self._banker = rand.randi(1, base.MJ_FOUR)
    self._status = base.CHESS_STATUS_READY
    self._role = {}
    self._id = {}
    self._count = 0
    self._pause = false
    self._close_index = 0
    self._record = {
        info = {
            name = "dymj",
            number = number,
            rule = rule.pack,
        },
    }
end

function dymj:status(id, status, addr)
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
            broadcast({
                {index=info.index, status=status, ip=addr},
            }, nil, self._role)
        end
    end
end

function dymj:destroy()
    timer.del_once_routine("close_timer")
end

local function finish()
    skynet.call(skynet.self(), "lua", "destroy")
    skynet.call(table_mgr, "lua", "free", skynet.self())
end
function dymj:finish()
    local role = self._role
    self._role = {}
    self._id = {}
    for i = 1, base.MJ_FOUR do
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

function dymj:custom_card(name, card)
    if name ~= "dymj" then
        error{code = error_code.ERROR_CHESS_NAME}
    end
    self._custom_card = card
    return "response", ""
end

function dymj:pack(id, ip, agent)
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
                name = "dymj",
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
            for i = 1, base.MJ_FOUR do
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
                    local type_card = info.type_card
                    if type_card then
                        local own_card = {}
                        for k1, v1 in pairs(type_card) do
                            for j = 1, v1 do
                                own_card[#own_card+1] = k1
                            end
                        end
                        local show_card = {
                            own_card = own_card,
                            score = info.last_score,
                        }
                        if info.last_score > 0 then
                            show_card.last_deal = info.last_deal
                        end
                        u.weave_card = info.weave_card
                        u.show_card = show_card
                    end
                    user[#user+1] = u
                end
            end
            return {info=chess, user=user, start_session=si.session}
        elseif status == base.CHESS_STATUS_START or status == base.CHESS_STATUS_DEAL then
            local chess = {
                name = "dymj",
                number = self._number,
                rule = self._rule.pack,
                banker = self._banker,
                status = status,
                count = self._count,
                pause = self._pause,
                left = self._left,
                deal_index = self._deal_index,
                out_card = self._out_card,
                out_index = self._out_index,
                close_index = self._close_index,
                close_time = self._close_time,
            }
            local user = {}
            for i = 1, base.MJ_FOUR do
                local info = role[i]
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
                    out = info.out,
                    out_magic = info.out_magic>0,
                    top_score = info.top_score,
                    hu_count = info.hu_count,
                    status = info.status,
                }
                local out_card = info.out_card
                if out_card and #out_card > 0 then
                    u.out_card = out_card
                end
                local weave_card = info.weave_card
                if weave_card and #weave_card > 0 then
                    u.weave_card = weave_card
                end
                if info.op[base.MJ_OP_CHI] > 0 then
                    u.action = base.MJ_OP_CHI
                end
                if info.id == id then
                    local own_card = {}
                    for k, v in pairs(info.type_card) do
                        for i = 1, v do
                            own_card[#own_card+1] = k
                        end
                    end
                    u.own_card = own_card
                    u.own_count = #own_card
                    u.last_deal = info.last_deal
                    u.chi_count = info.chi_count
                    u.hu = info.hu
                else
                    local count = 0
                    for k, v in pairs(info.type_card) do
                        count = count + v
                    end
                    u.own_count = count
                end
                user[#user+1] = u
            end
            return {info=chess, user=user, start_session=si.session}
        end
    end
end

function dymj:enter(info, agent, index)
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
    for i = 1, base.MJ_FOUR do
        user[#user+1] = role[i] -- role[i] can be nil
    end
    local chess = {
        name = "dymj",
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

function dymj:join(name, info, room_card, agent)
    if name ~= "dymj" then
        error{code = error_code.ERROR_CHESS_NAME}
    end
    if self._status ~= base.CHESS_STATUS_READY then
        error{code = error_code.ERROR_CHESS_STATUS}
    end
    if self._rule.aa_pay and room_card < self._rule.total_count/8 then
        error{code = error_code.ROOM_CARD_LIMIT}
    end
    local role = self._role
    local index
    for i = 1, base.MJ_FOUR do
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

function dymj:leave(id, msg)
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
            {index=index, action=base.MJ_OP_LEAVE},
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
            {index=index, action=base.MJ_OP_LEAVE},
        }
        broadcast(cu, nil, role)
        return session_msg(info, cu)
    end
end

function dymj:chat_info(id, msg)
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

function dymj:is_all_agree()
    local count = 0
    for k, v in ipairs(self._role) do
        if v.agree then
            count = count + 1
        end
    end
    return count >= 3
end

function dymj:reply(id, msg)
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

function dymj:is_all_ready()
    local role = self._role
    for i = 1, base.MJ_FOUR do
        local v = role[i]
        if not v or not v.ready then
            return false
        end
    end
    return true
end

function dymj:op_check(id, status)
    if self._status ~= status then
        error{code = error_code.ERROR_CHESS_STATUS}
    end
    local info = self._id[id]
    if not info then
        error{code = error_code.NOT_IN_CHESS}
    end
    return info
end

function dymj:ready(id, msg)
    local info = self:op_check(id, base.CHESS_STATUS_READY)
    if info.ready then
        error{code = error_code.ALREADY_READY}
    end
    info.ready = true
    local user = {index=info.index, ready=true}
    local chess = {}
    if self:is_all_ready() then
        self:start()
        -- self
        chess.status = self._status
        chess.left = self._left
        chess.deal_index = self._deal_index
        local now = floor(skynet.time())
        chess.rand = now
        self._detail.info.rand = now
        user.own_card = info.deal_card
        if info.index == self._banker then
            user.last_deal = info.last_deal
        end
        -- other
        for k, v in ipairs(self._role) do
            if v.id ~= id then
                local last_deal
                if k == self._banker then
                    last_deal = v.last_deal
                end
                send(v, {
                    {index=info.index, ready=true}, 
                    {index=k, own_card=v.deal_card, last_deal=last_deal},
                }, chess)
            end
        end
    else
        broadcast({user}, chess, self._role, id)
    end
    return session_msg(info, {user}, chess)
end

function dymj:is_all_deal()
    local role = self._role
    for i = 1, base.MJ_FOUR do
        local v = role[i]
        if not v.deal_end then
            return false
        end
    end
    return true
end

function dymj:deal_end(id, msg)
    local info = self:op_check(id, base.CHESS_STATUS_DEAL)
    if info.deal_end then
        error{code = error_code.ALREADY_DEAL_END}
    end
    info.deal_end = true
    local user = {index=info.index, deal_end=true}
    local chess = {}
    if self:is_all_deal() then
        self._status = Base.CHESS_STATUS_START
        chess.status = self._status
    end
    broadcast({user}, chess, self._role, id)
    return session_msg(info, {user}, chess)
end

local CHI_RULE = {
    {-2, -1, -2},
    {-1, 1, -1},
    {1, 2, 0},
}
function dymj:analyze(card, index)
    local has_respond = false
    for k, v in ipairs(self._role) do
        if k ~= index and not self:is_out_magic(k) and v.chi_count[index] < base.MJ_CHI_COUNT then
            local type_card = v.type_card
            local chi = false
            if k == index%base.MJ_FOUR+1 then
                for k1, v1 in ipairs(CHI_RULE) do
                    local c1, c2 = card+v1[1], card+v1[2]
                    if valid_card(c1) and type_card[c1]>=1 
                        and valid_card(c2) and type_card[c2]>=1 then
                        chi = true
                        break
                    end
                end
            end
            local peng = false
            if type_card[card] >= 2 then
                peng = true
            end
            local gang = false
            if type_card[card] >= 3 then
                gang = true
            end
            local respond = v.respond
            respond[base.MJ_OP_CHI], respond[base.MJ_OP_PENG], respond[base.MJ_OP_GANG] = chi, peng, gang
            if chi or peng or gang then
                v.out_pass = false
                has_respond = true
            else
                v.out_pass = true
            end
            local op = v.op
            op[base.MJ_OP_CHI], op[base.MJ_OP_PENG], op[base.MJ_OP_GANG] = 0, 0, 0
            v.deal_pass = false
        else
            self:clear_op(v)
        end
    end
    return has_respond
end

function dymj:is_out_magic(index)
    for k, v in ipairs(self._role) do
        if k ~= index and v.out_magic > 0 then
            return true
        end
    end
end

function dymj:out_card(id, msg)
    local info = self:op_check(id, base.CHESS_STATUS_START)
    if not info.out then
        error{code = error_code.ERROR_OUT_INDEX}
    end
    local type_card = info.type_card
    local card = msg.card
    if not type_card[card] then
        error{code = error_code.INVALID_CARD}
    end
    if type_card[card] == 0 then
        error{code = error_code.NO_OUT_CARD}
    end
    local index = info.index
    if self:is_out_magic(index) and card ~= self._deal_card then
        error{code = error_code.OUT_CARD_LIMIT}
    end
    info.out = false
    type_card[card] = type_card[card] - 1
    if card == self._magic_card then
        info.out_magic = info.out_magic + 1
    else
        info.out_magic = 0
        info.gang_count = 0
    end
    self._out_card = card
    self._out_index = index
    info.out_card[#info.out_card+1] = card
    local record_action = self._detail.action
    record_action[#record_action+1] = {
        index = index,
        card = card,
        out_index = msg.index,
    }
    if self._left <= 20 then
        return self:conclude(id)
    else
        local chess
        local deal_id
        local role = self._role
        if not self:analyze(card, index) then
            local deal_index = index%base.MJ_FOUR+1
            local r = role[deal_index]
            deal_id = r.id
            local c = self:deal(r)
            chess = {deal_index=deal_index, left=self._left}
            send(r, {
                {index=index, out_card={card}, out_index=msg.index},
                {index=deal_index, last_deal=c},
            }, chess)
        end
        local cu = {
            {index=index, out_card={card}, out_index=msg.index},
        }
        broadcast(cu, chess, role, id, deal_id)
        return session_msg(info, cu, chess)
    end
end

local function dec(t, k, d)
    local n = t[k]
    if d >= n then
        t[k] = nil
        return n
    else
        t[k] = n - d
        return d
    end
end

local function inc(t, k, d)
    local n = t[k]
    if n then
        t[k] = n + d
    else
        t[k] = d
    end
end

local function find_weave(type_card, weave_card, magic_count)
    for k, v in pairs(type_card) do
        if v+magic_count >= 3 then
            local n = dec(type_card, k, 3)
            local weave = {k, k, k}
            for i = n+1, 3 do
                weave[i] = 0
            end
            weave_card[#weave_card+1] = weave
            if find_weave(type_card, weave_card, magic_count-(3-n)) then
                return true
            end
            weave_card[#weave_card] = nil
            type_card[k] = v
        end
        for k1, v1 in ipairs(CHI_RULE) do
            local weave = {k, k+v1[1], k+v1[2]}
            if valid_card(weave[2]) and valid_card(weave[3]) then
                local mc = 0
                local mi = 0
                for i = 2, 3 do
                    if not type_card[weave[i]] then
                        mc = mc + 1
                        mi = i
                    end
                end
                if mc <= 1 and magic_count >= mc then
                    for i = 1, 3 do
                        if i ~= mi then
                            dec(type_card, weave[i], 1)
                        end
                    end
                    weave[4] = mi
                    weave_card[#weave_card+1] = weave
                    if find_weave(type_card, weave_card, magic_count-mc) then
                        return true
                    end
                    weave_card[#weave_card] = nil
                    for i = 1, 3 do
                        if i ~= mi then
                            inc(type_card, weave[i], 1)
                        end
                    end
                end
            end
        end
        return false
    end
    return true
end

function dymj:check_hu(type_card, weave_card, magic_count)
    local clone = util.clone(type_card)
    if magic_count > 0 then
        local deal_card = self._deal_card
        if deal_card ~= self._magic_card then
            local n = clone[deal_card]
            dec(clone, deal_card, 1)
            weave_card[#weave_card+1] = {deal_card, 0}
            if find_weave(clone, weave_card, magic_count-1) then
                return true
            end
            weave_card[#weave_card] = nil
            clone[deal_card] = n
        elseif magic_count >= 2 then
            weave_card[#weave_card+1] = {deal_card, 0}
            if find_weave(clone, weave_card, magic_count-2) then
                return true
            end
            weave_card[#weave_card] = nil
        end
        for k, v in pairs(type_card) do
            if k ~= deal_card then
                dec(clone, k, 1)
                weave_card[#weave_card+1] = {k, 0}
                if find_weave(clone, weave_card, magic_count-1) then
                    return true
                end
                weave_card[#weave_card] = nil
                clone[k] = v
            end
        end
    end
    for k, v in pairs(type_card) do
        if v >= 2 then
            dec(clone, k, 2)
            weave_card[#weave_card+1] = {k, k}
            if find_weave(clone, weave_card, magic_count) then
                return true
            end
            weave_card[#weave_card] = nil
            clone[k] = v
        end
    end
    return false
end

function dymj:is_qidui(type_card)
    local magic_card = self._magic_card
    local magic_count = type_card[magic_card]
    local four_count = 0
    local count = 0
    for k, v in pairs(type_card) do
        count = count + v
        if k ~= magic_card then
            if v == 1 then
                if magic_count <= 0 then
                    return false
                end
                magic_count = magic_count - 1
            elseif v == 3 then
                if magic_count <= 0 then
                    return false
                end
                magic_count = magic_count - 1
            elseif v == 4 then
                four_count = four_count + 1
            end
        end
    end
    return count==14, four_count, magic_count
end

function dymj:consume_card()
    if self._rule.aa_pay then
        local count = -self._rule.total_count/8
        for k, v in ipairs(self._role) do
            skynet.call(offline_mgr, "lua", "add", v.id, "role", "add_room_card", count)
        end
    else
        local id = self._role[1].id
        local count = -self._rule.total_count/2
        skynet.call(offline_mgr, "lua", "add", id, "role", "add_room_card", count)
    end
end

function dymj:hu(id, msg)
    local info = self:op_check(id, base.CHESS_STATUS_START)
    local index = info.index
    if self._deal_index ~= index then
        error{code = error_code.ERROR_DEAL_INDEX}
    end
    if not info.hu then
        error{code = error_code.CAN_NOT_HU}
    end
    local type_card = info.type_card
    local mul = 1
    local hu, four_count, mc = self:is_qidui(type_card)
    local magic_card = self._magic_card
    local hu_type
    if hu then
        hu_type = base.HU_7DUI
        mul = 2^(four_count+1)
        if (self._deal_card ~= magic_card and type_card[self._deal_card]%2 == 1)
            or (self._deal_card == magic_card and mc > 0) then
            mul = mul * 2^(info.out_magic+1)
        elseif type_card[magic_card] == 0 then
            mul = mul * 2
        end
    else
        local tc = {}
        for k, v in pairs(type_card) do
            if v > 0 then
                tc[k] = v
            end
        end
        local magic_count = tc[magic_card] or 0
        tc[magic_card] = nil
        local weave_card = {}
        if not self:check_hu(tc, weave_card, magic_count) then
            error{code = error_code.ERROR_OPERATION}
        end
        hu_type = base.HU_NONE
        local head = weave_card[1]
        if head[1] == self._deal_card and head[2] == 0 then
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
    local banker = self._banker
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
        local score
        if k == index then
            if k == banker then
                score = mul * 24
            else
                score = mul * 10
            end
        else
            if k == banker or index == banker then
                score = -mul * 8
            else
                score = -mul
            end
        end
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
    if sr.id then
        skynet.call(record_info_db, "lua", "update", {id=sr.id}, {
            ["$push"] = {record=record_detail},
            ["$set"] = {expire=expire, time=now},
        }, true)
    else
        sr.id = skynet.call(self._server, "lua", "gen_record")
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
            skynet.call(user_record_db, "lua", "update", {id=v.id}, {["$push"]={record=sr.id}}, true)
        end
        sr.user = record_user
        sr.record = {record_detail}
        skynet.call(record_info_db, "lua", "safe_insert", sr)
    end
    local win = user[index]
    win.hu_count = info.hu_count
    win.action = base.MJ_OP_HU
    local ws = win.show_card
    ws.last_deal = info.last_deal
    ws.hu = hu_type
    self._old_banker = banker
    self._banker = index
    local ci = {
        status=self._status, count=self._count, banker=self._banker,
    }
    broadcast(user, ci, role, id)
    if self._status == base.CHESS_STATUS_FINISH then
        self:finish()
    end
    return session_msg(info, user, ci)
end

function dymj:check_prior(index, op)
    local front = true
    local role = self._role
    for i = 1, base.MJ_FOUR-1 do
        local n = (self._out_index+i-1)%base.MJ_FOUR+1
        if n == index then
            front = false
        else
            local other = role[n]
            if not other.out_pass then
                for k, v in ipairs(other.respond) do
                    if v and (k>op or (k==op and front)) then
                        return true
                    end
                end
            end
        end
    end
    return false
end

function dymj:chi(id, msg)
    local info = self:op_check(id, base.CHESS_STATUS_START)
    local out_index = self._out_index
    if info.chi_count[out_index] >= base.MJ_CHI_COUNT then
        error{code = error_code.CHI_COUNT_LIMIT}
    end
    if info.op[base.MJ_OP_CHI] > 0 then
        error{code = error_code.WAIT_FOR_OTHER}
    end
    if not info.respond[base.MJ_OP_CHI] then
        error{code = error_code.ERROR_OPERATION}
    end
    local index = info.index
    if index ~= out_index%base.MJ_FOUR+1 then
        error{code = error_code.ERROR_OPERATION}
    end
    local valid = false
    local type_card = info.type_card
    local card = msg.card
    local out_card = self._out_card
    for i = card, card+2 do
        if i == out_card then
            valid = true
        elseif not (type_card[i] >= 1) then
            error{code = error_code.ERROR_OPERATION}
        end
    end
    if not valid then
        error{code = error_code.ERROR_OPERATION}
    end
    if self:check_prior(index, base.MJ_OP_CHI) then
        info.op[base.MJ_OP_CHI] = card
        return session_msg(info, {
            {index=index, action=base.MJ_OP_CHI},
        })
    else
        local record_action = self._detail.action
        record_action[#record_action+1] = {
            index = index,
            op = base.MJ_OP_CHI,
            card = card,
        }
        self:clear_all_op()
        for i = card, card+2 do
            if i ~= out_card then
                type_card[i] = type_card[i] - 1
            end
        end
        local weave = {
            op = base.MJ_OP_CHI,
            card = card,
            index = out_index,
            out_card = out_card,
        }
        info.weave_card[#info.weave_card+1] = weave
        info.out = true
        info.hu = false
        info.chi_count[out_index] = info.chi_count[out_index] + 1
        local role_out = self._role[out_index].out_card
        role_out[#role_out] = nil
        local cu = {
            {index=index, weave_card={weave}},
        }
        broadcast(cu, nil, self._role, id)
        return session_msg(info, cu)
    end
end

function dymj:peng(id, msg)
    local info = self:op_check(id, base.CHESS_STATUS_START)
    local out_index = self._out_index
    if info.chi_count[out_index] >= base.MJ_CHI_COUNT then
        error{code = error_code.CHI_COUNT_LIMIT}
    end
    if not info.respond[base.MJ_OP_PENG] then
        error{code = error_code.ERROR_OPERATION}
    end
    local type_card = info.type_card
    local out_card = self._out_card
    if not (type_card[out_card] >= 2) then
        error{code = error_code.ERROR_OPERATION}
    end
    local record_action = self._detail.action
    record_action[#record_action+1] = {
        index = index,
        op = base.MJ_OP_PENG,
        card = out_card,
    }
    self:clear_all_op()
    type_card[out_card] = type_card[out_card] - 2
    local weave = {
        op = base.MJ_OP_PENG,
        card = out_card,
        index = out_index,
        out_card = out_card,
    }
    info.weave_card[#info.weave_card+1] = weave
    info.out = true
    info.hu = false
    info.chi_count[out_index] = info.chi_count[out_index] + 1
    local role_out = self._role[out_index].out_card
    role_out[#role_out] = nil
    local cu = {
        {index=info.index, weave_card={weave}},
    }
    broadcast(cu, nil, self._role, id)
    return session_msg(info, cu)
end

function dymj:gang(id, msg)
    local info = self:op_check(id, base.CHESS_STATUS_START)
    local index = info.index
    local out_index = self._out_index
    if info.chi_count[out_index] >= base.MJ_CHI_COUNT then
        error{code = error_code.CHI_COUNT_LIMIT}
    end
    if not info.respond[base.MJ_OP_GANG] then
        error{code = error_code.ERROR_OPERATION}
    end
    local type_card = info.type_card
    local out_card = self._out_card
    if not (type_card[out_card] >= 3) then
        error{code = error_code.ERROR_OPERATION}
    end
    local record_action = self._detail.action
    record_action[#record_action+1] = {
        index = index,
        op = base.MJ_OP_GANG,
        card = out_card,
    }
    type_card[out_card] = type_card[out_card] - 3
    local weave = {
        op = base.MJ_OP_GANG,
        card = out_card,
        index = out_index,
        out_card = out_card,
    }
    info.weave_card[#info.weave_card+1] = weave
    info.gang_count = info.gang_count + 1
    info.chi_count[out_index] = info.chi_count[out_index] + 1
    local role_out = self._role[out_index].out_card
    role_out[#role_out] = nil
    local c = self:deal(info)
    local chess = {deal_index=index, left=self._left}
    broadcast({
        {index=index, weave_card={weave}},
    }, chess, self._role, id)
    return session_msg(info, {
        {index=index, weave_card={weave}, last_deal=c},
    }, chess)
end

function dymj:hide_gang(id, msg)
    local info = self:op_check(id, base.CHESS_STATUS_START)
    if not info.out then
        error{code = error_code.ERROR_OPERATION}
    end
    local index = info.index
    -- if self._deal_index ~= index then
    --     error{code = error_code.ERROR_DEAL_INDEX}
    -- end
    if self:is_out_magic(index) then
        error{code = error_code.ERROR_OPERATION}
    end
    local card = msg.card
    if card == self._magic_card then
        error{code = error_code.ERROR_OPERATION}
    end
    local record_action = self._detail.action
    record_action[#record_action+1] = {
        index = index,
        op = base.MJ_OP_HIDE_GANG,
        card = card,
    }
    local type_card = info.type_card
    local weave
    local weave_card = info.weave_card
    local card_count = type_card[card]
    if card_count >= 4 then
        type_card[card] = card_count - 4
        weave = {
            op = base.MJ_OP_HIDE_GANG,
            card = card,
            index = index,
            out_card = card,
        }
        weave_card[#weave_card+1] = weave
    elseif card_count >= 1 then
        for k, v in ipairs(weave_card) do
            if v.op == base.MJ_OP_PENG and v.card == card then
                weave = v
                weave.old = k
                break
            end
        end
        if not weave then
            error{code = error_code.ERROR_OPERATION}
        end
        type_card[card] = card_count - 1
        weave.op = base.MJ_OP_GANG
    else
        error{code = error_code.ERROR_OPERATION}
    end
    info.gang_count = info.gang_count + 1
    local c = self:deal(info)
    local chess = {deal_index=index, left=self._left}
    broadcast({
        {index=index, weave_card={weave}},
    }, chess, self._role, id)
    return session_msg(info, {
        {index=index, weave_card={weave}, last_deal=c},
    }, chess)
end

local function in_respond(respond)
    return respond[base.MJ_OP_CHI] or respond[base.MJ_OP_PENG] or respond[base.MJ_OP_GANG]
end

function dymj:pass(id, msg)
    local info = self:op_check(id, base.CHESS_STATUS_START)
    if in_respond(info.respond) then
        if info.out_pass then
            error{code = error_code.ALREADY_PASS}
        end
        info.out_pass = true
        local chess
        local user = {index=info.index, action=base.MJ_OP_PASS}
        local all_pass = true
        local role = self._role
        local out_index = self._out_index
        for k, v in ipairs(role) do
            if not v.out_pass then
                all_pass = false
                -- NOTICE: only check MJ_OP_CHI
                local card = v.op[base.MJ_OP_CHI]
                if card > 0 and not self:check_prior(k, base.MJ_OP_CHI) then
                    local record_action = self._detail.action
                    record_action[#record_action+1] = {
                        index = index,
                        op = base.MJ_OP_CHI,
                        card = card,
                    }
                    self:clear_all_op()
                    local type_card = v.type_card
                    for i = card, card+2 do
                        if i ~= self._out_card then
                            type_card[i] = type_card[i] - 1
                        end
                    end
                    local weave = {
                        op = base.MJ_OP_CHI,
                        card = card,
                        index = out_index,
                        out_card = self._out_card,
                    }
                    v.weave_card[#v.weave_card+1] = weave
                    v.out = true
                    v.hu = false
                    v.chi_count[out_index] = v.chi_count[out_index] + 1
                    local role_out = role[out_index].out_card
                    role_out[#role_out] = nil
                    broadcast({
                        {index=k, weave_card={weave}},
                    }, nil, role, id)
                    return session_msg(info, {
                        {index=k, weave_card={weave}}, 
                        user,
                    })
                end
            end
        end
        if all_pass then
            self:clear_all_op()
            local deal_index = out_index%base.MJ_FOUR+1
            local r = role[deal_index]
            local c = self:deal(r)
            chess = {deal_index=deal_index, left=self._left}
            if r.id == id then
                user.last_deal = c
            else
                send(r, {
                    {index=deal_index, last_deal=c},
                }, chess)
            end
            broadcast(nil, chess, role, id, r.id)
        end
        return session_msg(info, {user}, chess)
    else
        if info.deal_pass then
            error{code = error_code.ALREADY_PASS}
        end
        info.deal_pass = true
        local user = {index=info.index, action=base.MJ_OP_PASS}
        return session_msg(info, {user})
    end
end

function dymj:conclude(id, msg)
    local info = self:op_check(id, base.CHESS_STATUS_START)
    if self._deal_index ~= info.index then
        error{code = error_code.ERROR_DEAL_INDEX}
    end
    if self._left > 20 then
        error{code = error_code.CONCLUDE_CARD_LIMIT}
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
    local role = self._role
    for k, v in ipairs(role) do
        v.ready = false
        v.deal_end = false
        v.last_score = 0
        local own_card = {}
        for k1, v1 in pairs(v.type_card) do
            for i = 1, v1 do
                own_card[#own_card+1] = k1
            end
        end
        user[k] = {
            index = k,
            ready = v.ready,
            deal_end = v.deal_end,
            show_card = {
                own_card = own_card,
                score = 0,
            },
        }
    end
    local detail = self._detail
    detail.id = skynet.call(self._server, "lua", "gen_record_detail")
    local record_detail = {
        id = detail.id,
        time = detail.time,
    }
    skynet.call(record_detail_db, "lua", "safe_insert", detail)
    local sr = self._record
    if sr.id then
        skynet.call(record_info_db, "lua", "update", {id=sr.id}, {["$push"]={record=record_detail}}, true)
    else
        sr.id = skynet.call(self._server, "lua", "gen_record")
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
            skynet.call(user_record_db, "lua", "update", {id=v.id}, {["$push"]={record=sr.id}}, true)
        end
        sr.user = record_user
        sr.record = {record_detail}
        skynet.call(record_info_db, "lua", "safe_insert", sr)
    end
    local ci = {
        status=self._status, count=self._count,
    }
    broadcast(user, ci, role, id)
    if self._status == base.CHESS_STATUS_FINISH then
        self:finish()
    end
    return session_msg(info, user, ci)
end

function dymj:deal(info)
    local c = self._card[self._left]
    self._left = self._left - 1
    info.type_card[c] = info.type_card[c] + 1
    info.last_deal = c
    info.out = true
    info.hu = true
    self._deal_index = info.index
    self._deal_card = c
    self:clear_all_op()
    local record_action = self._detail.action
    record_action[#record_action+1] = {
        index = info.index,
        deal_card = c,
    }
    return c
end

function dymj:clear_op(info)
    local respond = info.respond
    respond[base.MJ_OP_CHI], respond[base.MJ_OP_PENG], respond[base.MJ_OP_GANG] = false, false, false
    info.out_pass = true
    local op = info.op
    op[base.MJ_OP_CHI], op[base.MJ_OP_PENG], op[base.MJ_OP_GANG] = 0, 0, 0
    info.deal_pass = false
end

function dymj:clear_all_op()
    for k, v in ipairs(self._role) do
        self:clear_op(v)
    end
end

function dymj:start()
    local card
    if self._custom_card then
        card = util.clone(self._custom_card)
    else
        card = {
            01,02,03,04,05,06,07,08,09,
            01,02,03,04,05,06,07,08,09,
            01,02,03,04,05,06,07,08,09,
            01,02,03,04,05,06,07,08,09,
            11,12,13,14,15,16,17,18,19,
            11,12,13,14,15,16,17,18,19,
            11,12,13,14,15,16,17,18,19,
            11,12,13,14,15,16,17,18,19,
            21,22,23,24,25,26,27,28,29,
            21,22,23,24,25,26,27,28,29,
            21,22,23,24,25,26,27,28,29,
            21,22,23,24,25,26,27,28,29,
            31,33,35,37,
            31,33,35,37,
            31,33,35,37,
            31,33,35,37,
            41,43,45,
            41,43,45,
            41,43,45,
            41,43,45,
        }
        util.shuffle(card, self._rand)
    end
    self._card = card
    self._status = base.CHESS_STATUS_DEAL
    self._out_card = 0
    self._out_index = 0
    self._old_banker = nil
    local left = #card
    local role = self._role
    local record_user = {}
    for j = 1, base.MJ_FOUR do
        local index = (self._banker+j-2)%base.MJ_FOUR+1
        local v = role[index]
        local type_card = {}
        for i = 1, base.MJ_CARD_INDEX do
            if not mj_invalid_card[i] then
                type_card[i] = 0
            end
        end
        v.type_card = type_card
        v.weave_card = {}
        v.respond = {}
        v.op = {}
        v.out_card = {}
        v.out = false
        v.hu = false
        local chi_count = {}
        for i = 1, base.MJ_FOUR do
            chi_count[i] = 0
        end
        v.chi_count = chi_count
        v.gang_count = 0
        v.out_magic = 0
        local deal_card = {}
        for i = 1, base.MJ_ROLE_CARD do
            local c = card[left]
            left = left - 1
            type_card[c] = type_card[c] + 1
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
    self._left = left
    self._detail = {
        info = {
            name = "dymj",
            number = self._number,
            rule = self._rule.pack,
            banker = self._banker,
            left = left,
            count = self._count,
        },
        user = record_user,
        action = {},
    }
    self:deal(role[self._banker])
end

return {__index=dymj}
