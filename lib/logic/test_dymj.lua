local skynet = require "skynet"
local share = require "share"
local util = require "util"

local string = string
local ipairs = ipairs
local pairs = pairs
local table = table
local floor = math.floor
local xpcall = xpcall
local type = type

local base
local error_code
local mj_invalid_card
local table_mgr
local chess_mgr
local offline_mgr

skynet.init(function()
    base = share.base
    error_code = share.error_code
    mj_invalid_card = share.mj_invalid_card
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
    if not user.android and user.agent then
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

local function trace(msg)
    local t = type(msg)
    if t == "table" then
        util.dump(msg)
    else
        skynet.error(msg)
    end
    return msg
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
    for i = 1, 3 do
        local n = i + 1
        local info = {
            account = string.format("android_%d", rand.randi(i*10000, n*10000)),
            id = rand.randi(i*111111, n*111111),
            sex = rand.randi(1, 2),
            ip = string.format("192.168.%d.%d:%d", 
                rand.randi(1, 255), rand.randi(1, 255), rand.randi(i*10000, n*10000)),
            android = true,
        }
        self:enter(info, nil, i+1)
        info.ready = true
    end
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
        if v and not v.android then
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
        elseif status == base.CHESS_STATUS_START then
            local chess = {
                name = "dymj",
                number = self._number,
                rule = self._rule.pack,
                banker = self._banker,
                status = self._status,
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
    info.hu_count = 0
    info.top_score = 0
    info.session = 1
    info.status = base.USER_STATUS_ONLINE
    role[index] = info
    self._id[info.id] = info
    if not info.android then
        skynet.call(chess_mgr, "lua", "add", info.id, skynet.self())
    end
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
    local cu = {
        {index=index, action=base.MJ_OP_LEAVE},
    }
    broadcast(cu, nil, role, id)
    self:finish()
    return session_msg(info, cu)
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
                        chi = card+v1[3]
                        break
                    end
                end
            end
            local peng = false
            if type_card[card] >= 2 then
                peng = card
            end
            local gang = false
            if type_card[card] >= 3 then
                gang = card
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
        else
            for k, v in ipairs(role) do
                if v.android then
                    local respond = v.respond
                    local chi, peng, gang = respond[base.MJ_OP_CHI], respond[base.MJ_OP_PENG], respond[base.MJ_OP_GANG]
                    if gang then
                        skynet.fork(function()
                            xpcall(function()
                                self:gang(v.id)
                            end, trace)
                        end)
                    elseif peng then
                        skynet.fork(function()
                            xpcall(function()
                                self:peng(v.id)
                            end, trace)
                        end)
                    elseif chi then
                        skynet.fork(function()
                            xpcall(function()
                                self:chi(v.id, {card=chi})
                            end, trace)
                        end)
                    end
                end
            end
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
        local count = -self._rule.total_count//8
        for k, v in ipairs(self._role) do
            skynet.call(offline_mgr, "lua", "add", v.id, "role", "add_room_card", count)
        end
    else
        local id = self._role[1].id
        local count = -self._rule.total_count//2
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
    if hu then
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
        local head = weave_card[1]
        if head[1] == self._deal_card and head[2] == 0 then
            mul = 2^info.gang_count
            mul = mul * 2^(info.out_magic+1)
        else
            local out_card = info.out_card
            local len = #out_card
            if len == 0 or out_card[len] ~= magic_card then
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
    for k, v in ipairs(role) do
        if v.android then
            v.ready = true
        else
            v.ready = false
        end
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
    local win = user[index]
    win.hu_count = info.hu_count
    win.action = base.MJ_OP_HU
    win.show_card.last_deal = info.last_deal
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

function dymj:android_out(info)
    if self:is_out_magic(info.index) then
        xpcall(function()
            self:out_card(info.id, {card=info.last_deal, index=1})
        end, trace)
    else
        local own_card = {}
        for k, v in pairs(info.type_card) do
            for i = 1, v do
                own_card[#own_card+1] = k
            end
        end
        local len = #own_card
        local index = self._rand.randi(1, len)
        xpcall(function()
            self:out_card(info.id, {card=own_card[index], index=index})
        end, trace)
    end
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
        if info.android then
            skynet.fork(function()
                self:android_out(info)
            end)
        end
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
    if info.android then
        skynet.fork(function()
            self:android_out(info)
        end)
    end
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
                    if v.android then
                        skynet.fork(function()
                            self:android_out(v)
                        end)
                    end
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
        if v.android then
            v.ready = true
        else
            v.ready = false
        end
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
            show_card = {
                own_card = own_card,
                score = 0,
            },
        }
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

function dymj:android_deal(info)
    local type_card = info.type_card
    local hu = self:is_qidui(type_card)
    local magic_card = self._magic_card
    if hu then
        skynet.fork(function()
            xpcall(function()
                self:hu(info.id)
            end, trace)
        end)
        return
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
        if self:check_hu(tc, weave_card, magic_count) then
            skynet.fork(function()
                xpcall(function()
                    self:hu(info.id)
                end, trace)
            end)
            return
        end
    end
    if not self:is_out_magic(info.index) then
        for k1, v1 in pairs(type_card) do
            if k1 ~= magic_card and v1 >= 4 then
                skynet.fork(function()
                    xpcall(function()
                        self:hide_gang(info.id, {card=k1})
                    end, trace)
                end)
                return
            end
        end
        for k1, v1 in ipairs(info.weave_card) do
            if v1.op == base.MJ_OP_PENG and type_card[v1.card] >= 1 then
                skynet.fork(function()
                    xpcall(function()
                        self:hide_gang(info.id, {card=v1.card})
                    end, trace)
                end)
                return
            end
        end
    end
    skynet.fork(function()
        self:android_out(info)
    end)
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
    if info.android then
        self:android_deal(info)
    end
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
    self._status = base.CHESS_STATUS_START
    self._out_card = 0
    self._out_index = 0
    self._old_banker = nil
    local left = #card
    local role = self._role
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
    end
    self._left = left
    self:deal(role[self._banker])
end

return {__index=dymj}
