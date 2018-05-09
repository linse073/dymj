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

local jdmj = {}

function jdmj:init(number, rule, rand, server, card)
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
            name = "jdmj",
            number = number,
            rule = rule.pack,
        },
    }
end

function jdmj:status(id, status, addr)
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

function jdmj:destroy()
    timer.del_once_routine("close_timer")
end

local function finish()
    skynet.call(skynet.self(), "lua", "destroy")
    skynet.call(table_mgr, "lua", "free", skynet.self())
end
function jdmj:finish()
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

function jdmj:custom_card(name, card)
    if name ~= "jdmj" then
        error{code = error_code.ERROR_CHESS_NAME}
    end
    self._custom_card = card
    return "response", ""
end

function jdmj:pack(id, ip, agent)
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
                name = "jdmj",
                number = self._number,
                rule = self._rule.pack,
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
                            local last_hu = info.last_hu
                            show_card.last_deal = last_hu.last_deal
                            show_card.last_index = last_hu.last_index
                            show_card.hu = last_hu.hu
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
                name = "jdmj",
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
                pass_status = self._pass_status,
                can_out = self._can_out,
                gang_card = self._gang_card,
                gang_index = self._gang_index,
                record_id = self._record.id,
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
                if info.op[base.MJ_OP_CHI] then
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
                    u.pass = info.pass
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

function jdmj:enter(info, agent, index)
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
        name = "jdmj",
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

function jdmj:join(info, room_card, agent)
    -- if self._status ~= base.CHESS_STATUS_READY then
    --     error{code = error_code.ERROR_OPERATION}
    -- end
    local rule = self._rule
    if rule.aa_pay and room_card < rule.single_card then
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

function jdmj:leave(id, msg)
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

function jdmj:chat_info(id, msg)
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

function jdmj:is_all_agree()
    local count = 0
    for k, v in ipairs(self._role) do
        if v.agree then
            count = count + 1
        end
    end
    return count >= 3
end

function jdmj:reply(id, msg)
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

function jdmj:is_all_ready()
    local role = self._role
    for i = 1, base.MJ_FOUR do
        local v = role[i]
        if not v or not v.ready then
            return false
        end
    end
    return true
end

function jdmj:op_check(id, status)
    if self._status ~= status then
        error{code = error_code.ERROR_OPERATION}
    end
    local info = self._id[id]
    if not info then
        error{code = error_code.NOT_IN_CHESS}
    end
    return info
end

function jdmj:ready(id, msg)
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
            left = self._left,
            deal_index = self._deal_index,
            rand = now,
        }
        self._detail.info.rand = now
        user.own_card = info.deal_card
        if index == self._banker then
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
                    {index=index, ready=true}, 
                    {index=k, own_card=v.deal_card, last_deal=last_deal},
                }, chess)
            end
        end
    else
        broadcast({user}, chess, self._role, id)
    end
    return session_msg(info, {user}, chess)
end

function jdmj:is_all_deal()
    local role = self._role
    for i = 1, base.MJ_FOUR do
        local v = role[i]
        if not v.deal_end then
            return false
        end
    end
    return true
end

function jdmj:deal_end(id, msg)
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

local CHI_RULE = {
    {-2, -1, -2},
    {-1, 1, -1},
    {1, 2, 0},
}
function jdmj:analyze(card, index)
    self:clear_all_op()
    self._pass_status = base.PASS_STATUS_OUT
    local has_respond = false
    for k, v in ipairs(self._role) do
        if k ~= index and not self:is_out_magic(k) then
            local type_card = v.type_card
            local chi = false
            if k == index%base.MJ_FOUR+1 and v.chi_count[index] < base.MJ_CHI_COUNT then
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
                v.pass = false
                has_respond = true
            end
        end
    end
    return has_respond
end

function jdmj:is_out_magic(index)
    for k, v in ipairs(self._role) do
        if k ~= index and v.out_magic > 0 then
            return true
        end
    end
    return false
end

function jdmj:out_card(id, msg)
    local info = self:op_check(id, base.CHESS_STATUS_START)
    local index = info.index
    if index ~= self._can_out then
        error{code = error_code.ERROR_OPERATION}
    end
    local type_card = info.type_card
    local card = msg.card
    if not type_card[card] then
        error{code = error_code.INVALID_CARD}
    end
    if type_card[card] == 0 then
        error{code = error_code.NO_OUT_CARD}
    end
    -- if self:is_out_magic(index) and card ~= self._deal_card then
    --     error{code = error_code.OUT_CARD_LIMIT}
    -- end
    self._can_out = nil
    type_card[card] = type_card[card] - 1
    if card == self._magic_card then
        info.out_magic = info.out_magic + 1
        info.magic_index[info.out_magic] = info.last_weave
    else
        info.out_magic = 0
        info.gang_count = 0
    end
    info.last_weave = nil
    self._out_card = card
    self._out_index = index
    info.out_card[#info.out_card+1] = card
    local record_action = self._detail.action
    record_action[#record_action+1] = {
        index = index,
        card = card,
        out_index = msg.index,
    }
    if self._left <= 18 then
        return self:conclude(id)
    end
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

function jdmj:check_hu(type_card, weave_card, magic_count, deal_card)
    local clone = util.clone(type_card)
    if magic_count > 0 then
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

local function is_badui(type_card, magic_count)
    local single_count = 0
    local count = magic_count
    for k, v in pairs(type_card) do
        count = count + v
        if v == 1 or v == 3 then
            if magic_count <= 0 then
                single_count = single_count + 1
            end
            magic_count = magic_count - 1
        end
    end
    return count==17 and single_count<=1, magic_count
end

local function is_qingyise(type_card, weave_card)
    local has_color = {false, false, false, false, false}
    for k, v in pairs(type_card) do
        has_color[k//10+1] = true
    end
    for k, v in ipairs(weave_card) do
        has_color[v.card//10+1] = true
    end
    local index
    local color_none = 0
    for k, v in ipairs(has_color) do
        if v then
            index = k
        else
            color_none = color_none + 1
        end
    end
    return color_none>=4 and index<=3
end

local function is_qingfengzi(type_card, weave_card)
    local has_color = {false, false, false, false, false}
    for k, v in pairs(type_card) do
        has_color[k//10+1] = true
    end
    for k, v in ipairs(weave_card) do
        has_color[v.card//10+1] = true
    end
    for i = 1, 3 do
        if has_color[i] then
            return false
        end
    end
    return true
end

local match_count = {3, 3, 3, 4, 3}
local function is_shisanbuda(type_card, magic_count, magic_card)
    local color_card = {{}, {}, {}, {}, {}}
    if magic_count > 0 then
        local temp = color_card[magic_card//10+1]
        temp[#temp+1] = magic_card
        magic_count = magic_count - 1
    else
        return false
    end
    for k, v in pairs(type_card) do
        local temp = color_card[k//10+1]
        temp[#temp+1] = k
    end
    for k, v in ipairs(color_card) do
        local d = match_count[k] - #v
        if d > 0 then
            if magic_count >= d then
                magic_count = magic_count - d
            else
                return false
            end
        elseif d < 0 then
            return false
        end
    end
    for i = 1, 3 do
        local temp = color_card[i]
        table.sort(temp)
        local len = #temp
        if len > 1 then
            for j = 2, len do
                if temp[j] - temp[j-1] < 2 then
                    return false
                end
            end
        end
    end
    return true
end

function jdmj:consume_card()
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

function jdmj:analyzeHu(info, card)
    local type_card = info.type_card
    local magic_card = self._magic_card
    local wc = info.weave_card
    local mul, hu_type, baotou = 1, 0, false
    local deal_card
    local tc = {}
    for k, v in pairs(type_card) do
        if v > 0 then
            tc[k] = v
        end
    end
    if card then
        tc[card] = type_card[card] + 1
        deal_card = card
    else
        deal_card = self._deal_card
    end
    local magic_count = tc[magic_card] or 0
    tc[magic_card] = nil
    local hu, mc = is_badui(tc, magic_count)
    if hu then
        hu_type = base.HU_DUIZI
        mul = mul * 2
        if mc > 0 or (deal_card ~= magic_card and tc[deal_card]%2 == 1) then
            mul = mul * 2^(info.out_magic+1)
            baotou = true
        end
        if is_qingyise(tc, wc) then
            hu_type = base.HU_QINGYISE
            mul = mul * 10
        elseif is_qingfengzi(tc, wc) then
            hu_type = base.HU_QINGFENGZI
            mul = mul * 20
        end
    elseif is_qingfengzi(tc, wc) then
        hu_type = base.HU_QINGFENGZI
        mul = mul * 20
        mul = mul * 2^info.gang_count
    elseif is_shisanbuda(tc, magic_count, magic_card) then
        hu_type = base.HU_SHISANBUDA
        mul = mul * 4
    else
        local weave_card = {}
        if self:check_hu(tc, weave_card, magic_count, deal_card) then
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
                baotou = true
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
            if is_qingyise(tc, wc) then
                hu_type = base.HU_QINGYISE
                mul = mul * 10
            elseif is_qingfengzi(tc, wc) then
                hu_type = base.HU_QINGFENGZI
                mul = mul * 20
            end
        end
    end
    return hu_type, mul, baotou
end

function jdmj:gangHu(info, card)
    local type_card = info.type_card
    local magic_card = self._magic_card
    local wc = info.weave_card
    local mul, hu_type = 1, 0
    local deal_card = card
    local tc = {}
    for k, v in pairs(type_card) do
        if v > 0 then
            tc[k] = v
        end
    end
    tc[card] = type_card[card] + 1
    local magic_count = tc[magic_card] or 0
    tc[magic_card] = nil
    local hu, mc = is_badui(tc, magic_count)
    if hu and not (mc > 0 or (deal_card ~= magic_card and tc[deal_card]%2 == 1)) then
        hu_type = base.HU_DUIZI
        mul = mul * 2
        if is_qingyise(tc, wc) then
            hu_type = base.HU_QINGYISE
            mul = mul * 10
        elseif is_qingfengzi(tc, wc) then
            hu_type = base.HU_QINGFENGZI
            mul = mul * 20
        end
    elseif is_qingfengzi(tc, wc) then
        hu_type = base.HU_QINGFENGZI
        mul = mul * 20
        mul = mul * 2^info.gang_count
    elseif is_shisanbuda(tc, magic_count, magic_card) then
        hu_type = base.HU_SHISANBUDA
        mul = mul * 4
    else
        local weave_card = {}
        if self:check_hu(tc, weave_card, magic_count, deal_card) then
            local head = weave_card[1]
            if not (head[1] == deal_card and head[2] == 0) then
                hu_type = base.HU_NONE
                local out_card = info.out_card
                local len = #out_card
                if len == 0 or out_card[len] ~= magic_card then
                    if info.gang_count > 0 then
                        hu_type = base.HU_GANGKAI
                    end
                    mul = 2^info.gang_count
                end
                if is_qingyise(tc, wc) then
                    hu_type = base.HU_QINGYISE
                    mul = mul * 10
                elseif is_qingfengzi(tc, wc) then
                    hu_type = base.HU_QINGFENGZI
                    mul = mul * 20
                end
            end
        end
    end
    return hu_type, mul
end

function jdmj:analyzeGangHu(card, index)
    self:clear_all_op()
    self._pass_status = base.PASS_STATUS_GANG_HU
    self._gang_card = card
    self._gang_index = index
    local has_hu = false
    for k, v in ipairs(self._role) do
        if k ~= index then
            local hu_type, hu_mul = self:gangHu(v, card)
            if hu_type > 0 then
                has_hu = true
                v.pass = false
                v.respond[base.MJ_OP_HU] = true
                v.op[base.MJ_OP_HU] = {
                    hu = base.HU_QIANGGANG,
                    mul = hu_mul,
                }
            end
        end
    end
    return has_hu
end

function jdmj:contract()
    local c = {0, 0, 0, 0}
    for k, v in ipairs(self._role) do
        local weave = v.weave_card
        local len = #weave
        if len > 0 then
            local w = weave[1]
            local color = w.card//10+1
            if color <= 3 then
                local count, last_index, last_count = 0, 0, 0
                if w.op ~= base.MJ_OP_HIDE_GANG then
                    count = count + 1
                    last_index = w.index
                    last_count = last_count + 1
                end
                local s = true
                for i = 2, len do
                    local tw = weave[i]
                    local tc = tw.card//10+1
                    if tc == color then
                        if tw.op ~= base.MJ_OP_HIDE_GANG then
                            count = count + 1
                            local ti = tw.index
                            if ti == last_index then
                                last_count = last_count + 1
                            else
                                last_index = ti
                                last_count = 1
                            end
                        end
                    else
                        s = false
                        break
                    end
                end
                if s then
                    local magic_card = self._magic_card
                    for k1, v1 in pairs(v.type_card) do
                        if v1 > 0 and k1 ~= magic_card then
                            local tc = k1//10+1
                            if tc ~= color then
                                s = false
                                break
                            end
                        end
                    end
                    if s and (last_count >= 3 or count >= 4) then
                        c[k] = last_index
                    end
                end
            end
        end
    end
    return c
end

function jdmj:check_hu_prior(gang_index, index)
    local role = self._role
    for i = 1, base.MJ_FOUR-1 do
        local n = (gang_index+i-1)%base.MJ_FOUR+1
        if n == index then
            return false
        else
            local other = role[n]
            if not other.pass and other.respond[base.MJ_OP_HU] then
                return true
            end
        end
    end
    return false
end

function jdmj:hu(id, msg)
    local info = self:op_check(id, base.CHESS_STATUS_START)
    local index = info.index
    local hu_type, mul, baotou, last_deal, last_index, contract
    local role = self._role
    if self._pass_status ~= base.PASS_STATUS_GANG_HU then
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
        hu_type, mul, baotou = self:analyzeHu(info)
        if hu_type == 0 then
            error{code = error_code.ERROR_OPERATION}
        end
        last_deal = info.last_deal
        contract = self:contract()
    else
        if info.pass then
            error{code = error_code.ALREADY_PASS}
        end
        if not info.respond[base.MJ_OP_HU] then
            error{code = error_code.ERROR_OPERATION}
        end
        local op = info.op[base.MJ_OP_HU]
        if self:check_hu_prior(self._gang_index, index) then
            op.hu_action = true
            return session_msg(info, {
                {index=index, action=base.MJ_OP_HU},
            })
        end
        hu_type, mul, baotou = op.hu, op.mul, false
        if mul < 4 then
            mul = 4
        end
        last_deal = self._gang_card
        last_index = self._gang_index
        local u = role[last_index]
        u.type_card[last_deal] = u.type_card[last_deal] - 1
        contract = {0, 0, 0, 0}
        contract[index] = self._gang_index
    end
    local record_id, user = self:hu_action(info, hu_type, mul, baotou, last_deal, last_index, contract)
    local ci = {
        status=self._status, count=self._count, banker=self._banker, record_id=record_id
    }
    broadcast(user, ci, role, id)
    if self._status == base.CHESS_STATUS_FINISH then
        self:finish()
    end
    return session_msg(info, user, ci)
end

function jdmj:hu_action(info, hu_type, mul, baotou, last_deal, last_index, contract)
    local index = info.index
    local role = self._role
    local cindex = contract[index]
    if cindex > 0 and contract[cindex] == index then
        contract[cindex] = 0
    end
    local scores = {0, 0, 0, 0}
    local smul = 0
    for k, v in ipairs(contract) do
        local i
        if v == index then
            i = k
        elseif k == index and v > 0 then
            i = v
        end
        if i then
            local chu_type, cmul, cbaotou = self:analyzeHu(role[i], self._magic_card)
            local fmul
            if cmul > mul then
                fmul = cmul * 3
            else
                fmul = mul * 3
            end
            scores[i] = -fmul
            smul = smul + fmul
        end
    end
    if smul > 0 then
        scores[index] = smul
    else
        scores = {-mul, -mul, -mul, -mul}
        scores[index] = mul * 3
        if baotou then
            local magic_index = info.magic_index
            local base_mul = mul / 2^(info.out_magic-1)
            for i = 2, info.out_magic do
                local mi = magic_index[i]
                if mi then
                    local dm = base_mul * 2^(i-2)
                    scores[mi] = scores[mi] - dm*2
                    for j = 1, base.MJ_FOUR do
                        if j ~= mi and j ~= index then
                            scores[j] = scores[j] + dm
                        end
                    end
                end
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
    local banker = self._banker
    local detail = self._detail
    local record_action = detail.action
    record_action[#record_action+1] = {
        index = index,
        op = base.MJ_OP_HU,
    }
    local now = floor(skynet.time())
    detail.id = skynet.call(self._server, "lua", "gen_record_detail")
    local show_card = {}
    local record_detail = {
        id = detail.id,
        time = now,
        show_card = show_card,
        banker = banker,
    }
    for k, v in ipairs(role) do
        v.ready = false
        v.deal_end = false
        local score = scores[k]
        v.last_score = score
        v.score = v.score + score
        local own_card = {}
        for k1, v1 in pairs(v.type_card) do
            for i = 1, v1 do
                own_card[#own_card+1] = k1
            end
        end
        local sc = {
            own_card = own_card,
            score = score,
            weave_card = v.weave_card,
        }
        local u = {
            index = k,
            ready = v.ready,
            deal_end = v.deal_end,
            score = v.score,
            show_card = sc,
        }
        detail.user[k].show_card = sc
        show_card[k] = sc
        if score > v.top_score then
            v.top_score = score
            u.top_score = score
        end
        user[k] = u
    end
    local win = user[index]
    win.hu_count = info.hu_count
    win.action = base.MJ_OP_HU
    local ws = win.show_card
    ws.last_deal = last_deal
    ws.last_index = last_index
    ws.hu = hu_type
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
        hu = hu_type,
        last_deal = last_deal,
        last_index = last_index,
    }
    self._old_banker = banker
    self._banker = index
    return record_id, user
end

function jdmj:check_prior(index, op)
    local front = true
    local role = self._role
    for i = 1, base.MJ_FOUR-1 do
        local n = (self._out_index+i-1)%base.MJ_FOUR+1
        if n == index then
            front = false
        else
            local other = role[n]
            if not other.pass then
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

function jdmj:chi(id, msg)
    local info = self:op_check(id, base.CHESS_STATUS_START)
    if self._pass_status ~= base.PASS_STATUS_OUT then
        error{code = error_code.ERROR_OPERATION}
    end
    if info.pass then
        error{code = error_code.ALREADY_PASS}
    end
    local out_index = self._out_index
    if info.chi_count[out_index] >= base.MJ_CHI_COUNT then
        error{code = error_code.CHI_COUNT_LIMIT}
    end
    if not info.respond[base.MJ_OP_CHI] then
        error{code = error_code.ERROR_OPERATION}
    end
    if info.op[base.MJ_OP_CHI] then
        error{code = error_code.WAIT_FOR_OTHER}
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
    end
    local weave = self:chi_action(info, card)
    local cu = {
        {index=index, weave_card={weave}},
    }
    broadcast(cu, nil, self._role, id)
    return session_msg(info, cu)
end

function jdmj:chi_action(info, card)
    local index = info.index
    local out_card = self._out_card
    local out_index = self._out_index
    local type_card = info.type_card
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
    info.last_weave = out_index
    self._can_out = index
    self._pass_status = base.PASS_STATUS_WEAVE
    info.chi_count[out_index] = info.chi_count[out_index] + 1
    local role_out = self._role[out_index].out_card
    role_out[#role_out] = nil
    return weave
end

function jdmj:peng(id, msg)
    local info = self:op_check(id, base.CHESS_STATUS_START)
    if self._pass_status ~= base.PASS_STATUS_OUT then
        error{code = error_code.ERROR_OPERATION}
    end
    if info.pass then
        error{code = error_code.ALREADY_PASS}
    end
    if not info.respond[base.MJ_OP_PENG] then
        error{code = error_code.ERROR_OPERATION}
    end
    local type_card = info.type_card
    local out_card = self._out_card
    if not (type_card[out_card] >= 2) then
        error{code = error_code.ERROR_OPERATION}
    end
    local out_index = self._out_index
    local index = info.index
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
    info.last_weave = out_index
    self._can_out = index
    self._pass_status = base.PASS_STATUS_WEAVE
    local role_out = self._role[out_index].out_card
    role_out[#role_out] = nil
    local cu = {
        {index=index, weave_card={weave}},
    }
    broadcast(cu, nil, self._role, id)
    return session_msg(info, cu)
end

function jdmj:gang(id, msg)
    local info = self:op_check(id, base.CHESS_STATUS_START)
    if self._pass_status ~= base.PASS_STATUS_OUT then
        error{code = error_code.ERROR_OPERATION}
    end
    if info.pass then
        error{code = error_code.ALREADY_PASS}
    end
    if not info.respond[base.MJ_OP_GANG] then
        error{code = error_code.ERROR_OPERATION}
    end
    local type_card = info.type_card
    local out_card = self._out_card
    if not (type_card[out_card] >= 3) then
        error{code = error_code.ERROR_OPERATION}
    end
    local index = info.index
    local out_index = self._out_index
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

function jdmj:hide_gang(id, msg)
    local info = self:op_check(id, base.CHESS_STATUS_START)
    local index = info.index
    if index ~= self._can_out then
        error{code = error_code.ERROR_OPERATION}
    end
    -- if self:is_out_magic(index) then
    --     error{code = error_code.ERROR_OPERATION}
    -- end
    local card = msg.card
    if card == self._magic_card then
        error{code = error_code.ERROR_OPERATION}
    end
    local type_card = info.type_card
    local weave_card = info.weave_card
    local card_count = type_card[card]
    local role = self._role
    local weave
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
        if info.op[base.MJ_OP_HIDE_GANG] then
            error{code = error_code.WAIT_FOR_OTHER}
        end
        if self._out_card ~= card and self:analyzeGangHu(card, index) then
            local chess = {
                pass_status = self._pass_status,
                gang_card = card,
                gang_index = index,
            }
            broadcast(nil, chess, role, id)
            info.op[base.MJ_OP_HIDE_GANG] = weave
            self._can_out = nil
            return session_msg(info, {
                {index=index, action=base.MJ_OP_HIDE_GANG},
            }, chess)
        end
        type_card[card] = card_count - 1
        weave.op = base.MJ_OP_GANG
    else
        error{code = error_code.ERROR_OPERATION}
    end
    local record_action = self._detail.action
    record_action[#record_action+1] = {
        index = index,
        op = base.MJ_OP_HIDE_GANG,
        card = card,
    }
    info.gang_count = info.gang_count + 1
    local c = self:deal(info)
    local chess = {deal_index=index, left=self._left}
    broadcast({
        {index=index, weave_card={weave}},
    }, chess, role, id)
    return session_msg(info, {
        {index=index, weave_card={weave}, last_deal=c},
    }, chess)
end

function jdmj:pass(id, msg)
    local info = self:op_check(id, base.CHESS_STATUS_START)
    local index = info.index
    local pass_status = self._pass_status
    if pass_status == base.PASS_STATUS_OUT then
        if info.pass then
            error{code = error_code.ALREADY_PASS}
        end
        info.pass = true
        local chess
        local user = {index=index, action=base.MJ_OP_PASS}
        local all_pass = true
        local role = self._role
        local out_index = self._out_index
        for k, v in ipairs(role) do
            if not v.pass then
                all_pass = false
                -- NOTICE: only check MJ_OP_CHI
                local card = v.op[base.MJ_OP_CHI]
                if card and not self:check_prior(k, base.MJ_OP_CHI) then
                    local weave = self:chi_action(v, card)
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
    elseif pass_status == base.PASS_STATUS_DEAL or pass_status == base.PASS_STATUS_WEAVE then
        if info.pass then
            error{code = error_code.ALREADY_PASS}
        end
        info.pass = true
        local user = {index=index, action=base.MJ_OP_PASS}
        return session_msg(info, {user})
    elseif pass_status == base.PASS_STATUS_GANG_HU then
        if info.pass then
            error{code = error_code.ALREADY_PASS}
        end
        info.pass = true
        local chess
        local all_pass = true
        local role = self._role
        for k, v in ipairs(role) do
            if not v.pass then
                all_pass = false
                local op = v.op[base.MJ_OP_HU]
                if op and op.hu_action and not self:check_hu_prior(self._gang_index, k) then
                    local hu_type, mul, baotou = op.hu, op.mul, false
                    if mul < 4 then
                        mul = 4
                    end
                    last_deal = self._gang_card
                    last_index = self._gang_index
                    local u = role[last_index]
                    u.type_card[last_deal] = u.type_card[last_deal] - 1
                    local contract = {0, 0, 0, 0}
                    contract[k] = self._gang_index
                    local record_id, user = self:hu_action(v, hu_type, mul, baotou, last_deal, last_index, contract)
                    local ci = {
                        status=self._status, count=self._count, banker=self._banker, record_id=record_id
                    }
                    broadcast(user, ci, role, id)
                    if self._status == base.CHESS_STATUS_FINISH then
                        self:finish()
                    end
                    user[index].action = base.MJ_OP_PASS
                    return session_msg(info, user, ci)
                end
            end
        end
        local user = {{index=index, action=base.MJ_OP_PASS}}
        if all_pass then
            local deal_index = self._gang_index
            local r = role[deal_index]
            local weave = r.op[base.MJ_OP_HIDE_GANG]
            local card = weave.card
            r.type_card[card] = r.type_card[card] - 1
            weave.op = base.MJ_OP_GANG
            local record_action = self._detail.action
            record_action[#record_action+1] = {
                index = deal_index,
                op = base.MJ_OP_HIDE_GANG,
                card = card,
            }
            r.gang_count = r.gang_count + 1
            local c = self:deal(r)
            chess = {deal_index=deal_index, left=self._left}
            send(r, {
                {index=deal_index, weave_card={weave}, last_deal=c},
            }, chess)
            broadcast({
                {index=deal_index, weave_card={weave}},
            }, chess, role, id, r.id)
            user[#user+1] = {index=deal_index, weave_card={weave}}
        end
        return session_msg(info, user, chess)
    else
        error{code = error_code.ERROR_OPERATION}
    end
end

function jdmj:conclude(id, msg)
    local info = self:op_check(id, base.CHESS_STATUS_START)
    local index = info.index
    if self._deal_index ~= index then
        error{code = error_code.ERROR_OPERATION}
    end
    if self._left > 18 then
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
    local detail = self._detail
    local now = floor(skynet.time())
    detail.id = skynet.call(self._server, "lua", "gen_record_detail")
    local show_card = {}
    local record_detail = {
        id = detail.id,
        time = now,
        show_card = show_card,
        banker = self._banker,
    }
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
        local sc = {
            own_card = own_card,
            score = 0,
            weave_card = v.weave_card,
        }
        local u = {
            index = k,
            ready = v.ready,
            deal_end = v.deal_end,
            show_card = sc,
        }
        detail.user[k].show_card = sc
        show_card[k] = sc
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
            ["$push"]={record=record_detail},
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
    local ci = {
        status=self._status, count=self._count, record_id=record_id,
    }
    broadcast(user, ci, role, id)
    if self._status == base.CHESS_STATUS_FINISH then
        self:finish()
    end
    return session_msg(info, user, ci)
end

function jdmj:deal(info)
    local c = self._card[self._left]
    self._left = self._left - 1
    info.type_card[c] = info.type_card[c] + 1
    info.last_deal = c
    local index = info.index
    self._can_out = index
    self._deal_index = index
    self._deal_card = c
    self:clear_all_op()
    self._pass_status = base.PASS_STATUS_DEAL
    info.pass = false
    local record_action = self._detail.action
    record_action[#record_action+1] = {
        index = index,
        deal_card = c,
    }
    return c
end

function jdmj:clear_op(info)
    local respond = info.respond
    local op = info.op
    for i = 1, base.MJ_OP_COUNT do
        respond[i] = false
        op[i] = nil
    end
    info.pass = true
end

function jdmj:clear_all_op()
    self._pass_status = 0
    for k, v in ipairs(self._role) do
        self:clear_op(v)
    end
end

function jdmj:start()
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
    self._out_card = nil
    self._out_index = nil
    self._old_banker = nil
    self._can_out = nil
    self._gang_card = nil
    self._gang_index = nil
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
        local chi_count = {}
        for i = 1, base.MJ_FOUR do
            chi_count[i] = 0
        end
        v.chi_count = chi_count
        v.gang_count = 0
        v.out_magic = 0
        v.magic_index = {}
        local deal_card = {}
        for i = 1, base.JDMJ_ROLE_CARD do
            local c = card[left+1-((i-1)*base.MJ_FOUR+j)]
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
    left = left - base.MJ_FOUR * base.JDMJ_ROLE_CARD
    self._left = left
    self._detail = {
        info = {
            name = "jdmj",
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

return {__index=jdmj}
