local skynet = require "skynet"
local share = require "share"
local broadcast = require "broadcast"
local util = require "util"
local func = require "func"

local string = string
local ipairs = ipairs
local pairs = pairs
local table = table
local floor = math.floor

local cz
local base
local error_code
local mj_invalid_card

skynet.init(function()
    cz = share.cz
    base = share.base
    error_code = share.error_code
    mj_invalid_card = share.mj_invalid_card
end)

local function valid_card(c)
    return c>0 and c<=base.MJ_CARD_INDEX and not mj_invalid_card[c]
end

local dymj = {}

function dymj:init(number, rule, rand, card)
    self._number = number
    self._rule = rule
    self._rand = rand
    self._custom_card = card
    local p, c = string.unpack("BB", rule)
    if c == 1 then
        self._total_count = 8
    else
        self._total_count = 16
    end
    self._magic_card = 45
    self._banker = rand.randi(1, base.MJ_FOUR)
    self._status = base.CHESS_STATUS_READY
    self._role = {}
    self._id = {}
    self._count = 0
    self._pause = false
end

function dymj:destroy()
end

local function finish()
    local table_mgr = skynet.queryservice("table_mgr")
    skynet.call(table_mgr, "lua", "free", skynet.self())
end
function dymj:finish()
    local role = self._role
    self._role = {}
    self._id = {}
    for i = 1, base.MJ_FOUR do
        local v = role[i]
        if v then
            skynet.call(v.agent, "lua", "action", "role", "leave")
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

function dymj:pack(id)
    local chess = {
        name = "dymj",
        number = self._number,
        rule = self._rule,
        banker = self._banker,
        status = self._statue,
        count = self._count,
        pause = self._pause,
        left = self._left,
        deal_index = self._deal_index,
        out_card = self._out_card,
        out_index = self._out_index,
    }
    local user = {}
    local role = self._role
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
                out_card = info.out_card,
                weave_card = info.weave_card,
                agree = info.agree,
                out = info.out,
                pass = info.pass,
                chi_count = info.chi_count,
            }
            if info.out_magic then
                u.out_magic = info.out_magic>0
            else
                u.out_magic = false
            end
            local op = info.op
            if op and op[base.MJ_OP_CHI] > 0 then
                u.action = base.MJ_OP_CHI
            end
            local type_card = info.type_card
            if info.id == id then
                if type_card then
                    local own_card = {}
                    for k, v in pairs(type_card) do
                        for i = 1, v do
                            own_card[#own_card+1] = k
                        end
                    end
                    u.own_card = own_card
                    u.own_count = #own_card
                end
                u.last_deal = info.last_deal
            else
                if type_card then
                    local count = 0
                    for k, v in pairs(type_card) do
                        count = count + v
                    end
                    u.own_count = count
                end
            end
            user[#user+1] = u
        end
    end
    return {info=chess, user=user}
end

function dymj:enter(info, agent, index)
    local role = self._role
    assert(not role[index], string.format("Seat %d already has role.", index))
    info.agent = agent
    info.index = index
    info.score = 0
    info.ready = false
    role[index] = info
    self._id[info.id] = info
    local user = {}
    for i = 1, base.MJ_FOUR do
        user[#user+1] = role[i] -- role[i] can be nil
    end
    return func.update_msg(user, {
        name = "dymj",
        number = self._number,
        rule = self._rule,
        banker = self._banker,
        status = self._status,
        count = self._count,
        pause = self._pause,
    })
end

function dymj:join(name, info, agent)
    if name ~= "dymj" then
        error{code = error_code.ERROR_CHESS_NAME}
    end
    if self._status ~= base.CHESS_STATUS_READY then
        error{code = error_code.ERROR_CHESS_STATUS}
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
    local rg, ri = func.update_msg({info})
    broadcast(rg, ri, role, info.id)
    return rmsg, rinfo
end

function dymj:leave(id, msg)
    local info = self._id[id]
    if not info then
        error{code = error_code.NOT_IN_CHESS}
    end
    local role = self._role
    if self._count > 0 or self._status == base.CHESS_STATUS_START then
        for i = 1, base.MJ_FOUR do
            local v = role[i]
            if v then
                v.agree = nil
            end
        end
        self._pause = false
        info.agree = true
        local rmsg, rinfo = func.update_msg({
            {index=info.index, action=base.MJ_OP_CLOSE, agree=true},
        }, {pause=self._pause})
        broadcast(rmsg, rinfo, role, id)
        return rmsg, rinfo
    elseif info.index == 1 then
        self._status = base.CHESS_STATUS_EXIT
        local rmsg, rinfo = func.update_msg({
            {index=info.index, action=base.MJ_OP_LEAVE},
        }, {status=self._status})
        broadcast(rmsg, rinfo, role, id)
        self:finish()
        return rmsg, rinfo
    else
        self._id[id] = nil
        role[info.index] = nil
        skynet.call(info.agent, "lua", "action", "role", "leave")
        local rmsg, rinfo = func.update_msg({
            {index=info.index, action=base.MJ_OP_LEAVE},
        })
        broadcast(rmsg, rinfo, role)
        return rmsg, rinfo
    end
end

function dymj:is_all_agree()
    local role = self._role
    for i = 1, base.MJ_FOUR do
        local v = role[i]
        if v and not v.agree then
            return false
        end
    end
    return true
end

function dymj:reply(id, msg)
    local info = self._id[id]
    if not info then
        error{code = error_code.NOT_IN_CHESS}
    end
    if info.agree then
        error{code = error_code.ALREADY_REPLY}
    end
    info.agree = msg.agree
    local chess = {}
    local rmsg, rinfo = func.update_msg({
        {index=info.index, agree=info.agree},
    }, chess)
    if info.agree then
        if self:is_all_agree() then
            self._status = base.CHESS_STATUS_EXIT
            chess.status = self._status
        end
    else
        self._pause = false
        chess.pause = self._pause
    end
    broadcast(rmsg, rinfo, self._role, id)
    if self._status == base.CHESS_STATUS_EXIT then
        self:finish()
    end
    return rmsg, rinfo
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
    local rmsg, rinfo = func.update_msg({user}, chess)
    if self:is_all_ready() then
        self:start()
        -- self
        chess.status = self._status
        chess.left = self._left
        chess.deal_index = self._deal_index
        chess.rand = floor(skynet.time())
        user.own_card = info.deal_card
        if info.index == self._banker then
            user.last_deal = info.last_deal
        end
        -- other
        for k, v in ipairs(self._role) do
            if v.id ~= id then
                local last_deal
                if v.index == self._banker then
                    last_deal = v.last_deal
                end
                skynet.send(v.agent, "lua", "notify", func.update_msg({
                    {index=info.index, ready=true}, 
                    {index=k, own_card=v.deal_card, last_deal=last_deal},
                }, chess))
            end
        end
    else
        broadcast(rmsg, rinfo, self._role, id)
    end
    return rmsg, rinfo
end

local CHI_RULE = {
    {-2, -1, -2},
    {-1, 1, -1},
    {1, 2, 0},
}
function dymj:analyze(card, index)
    local has_respond = false
    for k, v in ipairs(self._role) do
        if v.index ~= index and not self:is_out_magic() and v.chi_count[index] < base.MJ_CHI_COUNT then
            local type_card = v.type_card
            local chi = false
            if v.index == index%base.MJ_FOUR+1 then
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
            else
                v.pass = true
            end
            local op = v.op
            op[base.MJ_OP_CHI], op[base.MJ_OP_PENG], op[base.MJ_OP_GANG] = 0, 0, 0
        else
            local respond = v.respond
            respond[base.MJ_OP_CHI], respond[base.MJ_OP_PENG], respond[base.MJ_OP_GANG] = false, false, false
            v.pass = true
            local op = v.op
            op[base.MJ_OP_CHI], op[base.MJ_OP_PENG], op[base.MJ_OP_GANG] = 0, 0, 0
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
    if self:is_out_magic(info.index) and card ~= self._deal_card then
        error{code = error_code.OUT_CARD_LIMIT}
    end
    info.out = false
    if self._left <= 20 then
        return self:conclude(id)
    else
        type_card[card] = type_card[card] - 1
        if card == self._magic_card then
            info.out_magic = info.out_magic + 1
        else
            info.out_magic = 0
            info.gang_count = 0
        end
        self._out_card = card
        self._out_index = info.index
        info.out_card[#info.out_card+1] = card
        local chess
        local deal_index
        local role = self._role
        if not self:analyze(card, info.index) then
            deal_index = info.index%base.MJ_FOUR+1
            local r = role[deal_index]
            local c = self:deal(r)
            chess = {deal_index=deal_index, left=self._left}
            skynet.send(r.agent, "lua", "notify", func.update_msg({
                {index=info.index, out_card={card}, out_index=msg.index},
                {index=deal_index, last_deal=c},
            }, chess))
        end
        local rmsg, rinfo = func.update_msg({
            {index=info.index, out_card={card}, out_index=msg.index},
        }, chess)
        for k, v in ipairs(role) do
            if v.id ~= id and v.index ~= deal_index then
                skynet.send(v.agent, "lua", "notify", rmsg, rinfo)
            end
        end
        return rmsg, rinfo
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
    local two_count = 0
    for k, v in pairs(type_card) do
        if k ~= magic_card then
            if v == 1 then
                if magic_count <= 0 then
                    return false
                end
                magic_count = magic_count - 1
                two_count = two_count + 1
            elseif v == 2 then
                two_count = two_count + 1
            elseif v == 3 then
                if magic_count <= 0 then
                    return false
                end
                magic_count = magic_count - 1
                two_count = two_count + 2
            elseif v == 4 then
                four_count = four_count + 1
                two_count = two_count + 2
            end
        end
    end
    return two_count==7, four_count
end

function dymj:hu(id, msg)
    local info = self:op_check(id, base.CHESS_STATUS_START)
    local index = info.index
    if self._deal_index ~= index then
        error{code = error_code.ERROR_DEAL_INDEX}
    end
    local type_card = info.type_card
    local mul = 1
    local hu, four_count = self:is_qidui(type_card)
    local magic_card = self._magic_card
    if hu then
        mul = 2^(four_count+1)
        if type_card[self._deal_card]%2 == 1 then
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
    self._count = self._count + 1
    if self._count == self._total_count then
        self._status = base.CHESS_STATUS_FINISH
    else
        self._status = base.CHESS_STATUS_READY
    end
    local user = {}
    local role = self._role
    for k, v in ipairs(role) do
        v.ready = false
        local banker = self._banker
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
        v.score = v.score + score
        local own_card = {}
        for k1, v1 in pairs(v.type_card) do
            for i = 1, v1 do
                own_card[#own_card+1] = k1
            end
        end
        user[k] = {
            index = k,
            ready = false,
            score = v.score,
            show_card = {
                own_card = own_card,
                score = score,
            },
        }
    end
    user[index].action = base.MJ_OP_HU
    user[index].show_card.last_deal = role[index].last_deal
    self._banker = index
    local rmsg, rinfo = func.update_msg(user, {
        status=self._status, count=self._count, banker=self._banker,
    })
    broadcast(rmsg, rinfo, role, id)
    if self._status == base.CHESS_STATUS_FINISH then
        self:finish()
    end
    return rmsg, rinfo
end

function dymj:check_prior(index, op)
    local front = true
    local role = self._role
    for i = 1, base.MJ_FOUR-1 do
        local n = (self._deal_index+i-1)%base.MJ_FOUR+1
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
    if info.index ~= out_index%base.MJ_FOUR+1 then
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
    if self:check_prior(info.index, base.MJ_OP_CHI) then
        info.op[base.MJ_OP_CHI] = card
        return func.update_msg({
            {index=info.index, action=base.MJ_OP_CHI},
        })
    else
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
        info.chi_count[out_index] = info.chi_count[out_index] + 1
        local role_out = self._role[out_index].out_card
        role_out[#role_out] = nil
        local rmsg, rinfo = func.update_msg({
            {index=info.index, weave_card={weave}},
        })
        broadcast(rmsg, rinfo, self._role, id)
        return rmsg, rinfo
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
    type_card[out_card] = type_card[out_card] - 2
    local weave = {
        op = base.MJ_OP_PENG,
        card = out_card,
        index = out_index,
        out_card = out_card,
    }
    info.weave_card[#info.weave_card+1] = weave
    info.out = true
    info.chi_count[out_index] = info.chi_count[out_index] + 1
    local role_out = self._role[out_index].out_card
    role_out[#role_out] = nil
    local rmsg, rinfo = func.update_msg({
        {index=info.index, weave_card={weave}},
    })
    broadcast(rmsg, rinfo, self._role, id)
    return rmsg, rinfo
end

function dymj:gang(id, msg)
    local info = self:op_check(id, base.CHESS_STATUS_START)
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
    info.out = true
    info.gang_count = info.gang_count + 1
    info.chi_count[out_index] = info.chi_count[out_index] + 1
    local role_out = self._role[out_index].out_card
    role_out[#role_out] = nil
    local c = self:deal(info)
    local chess = {deal_index=info.index, left=self._left}
    local rmsg, rinfo = func.update_msg({
        {index=info.index, weave_card={weave}},
    }, chess)
    broadcast(rmsg, rinfo, self._role, id)
    return func.update_msg({
        {index=info.index, weave_card={weave}, last_deal=c},
    }, chess)
end

function dymj:hide_gang(id, msg)
    local info = self:op_check(id, base.CHESS_STATUS_START)
    local index = info.index
    -- if self._deal_index ~= index then
    --     error{code = error_code.ERROR_DEAL_INDEX}
    -- end
    if self:is_out_magic(index) then
        error{code = error_code.ERROR_OPERATION}
    end
    local type_card = info.type_card
    local card = msg.card
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
    info.out = true
    info.gang_count = info.gang_count + 1
    local c = self:deal(info)
    local chess = {deal_index=index, left=self._left}
    local rmsg, rinfo = func.update_msg({
        {index=index, weave_card={weave}},
    }, chess)
    broadcast(rmsg, rinfo, self._role, id)
    return func.update_msg({
        {index=index, weave_card={weave}, last_deal=c},
    }, chess)
end

local function in_respond(respond)
    return respond[base.MJ_OP_CHI] or respond[base.MJ_OP_PENG] or respond[base.MJ_OP_GANG]
end

function dymj:pass(id, msg)
    local info = self:op_check(id, base.CHESS_STATUS_START)
    if info.pass then
        error{code = error_code.ALREADY_PASS}
    end
    info.pass = true
    local deal_index
    local chess
    if in_respond(info.respond) then
        local all_pass = true
        local role = self._role
        local out_index = self._out_index
        for k, v in ipairs(role) do
            if not v.pass then
                all_pass = false
                -- NOTICE: only check MJ_OP_CHI
                local card = v.op[base.MJ_OP_CHI]
                if card > 0 and not self:check_prior(k, base.MJ_OP_CHI) then
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
                    v.chi_count[out_index] = v.chi_count[out_index] + 1
                    local role_out = role[out_index].out_card
                    role_out[#role_out] = nil
                    local rmsg, rinfo = func.update_msg({
                        {index=v.index, weave_card={weave}},
                    })
                    broadcast(rmsg, rinfo, role, id)
                    return func.update_msg({
                        {index=v.index, weave_card={weave}},
                        {index=info.index, action=base.MJ_OP_PASS},
                    })
                end
            end
        end
        if all_pass then
            deal_index = self._out_index%base.MJ_FOUR+1
            local r = role[deal_index]
            local c = self:deal(r)
            chess = {deal_index=deal_index, left=self._left}
            skynet.send(r.agent, "lua", "notify", func.update_msg({
                {index=deal_index, last_deal=c},
            }, chess))
            local rmsg, rinfo = func.update_msg(nil, chess)
            for k, v in ipairs(role) do
                if v.id ~= id and v.index ~= deal_index then
                    skynet.send(v.agent, "lua", "notify", rmsg, rinfo)
                end
            end
        end
    end
    return func.update_msg({
        {index=info.index, action=base.MJ_OP_PASS},
    }, chess)
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
    if self._count == self._total_count then
        self._status = base.CHESS_STATUS_FINISH
    else
        self._status = base.CHESS_STATUS_READY
    end
    local user = {}
    local role = self._role
    for k, v in ipairs(role) do
        v.ready = false
        local own_card = {}
        for k1, v1 in pairs(v.type_card) do
            for i = 1, v1 do
                own_card[#own_card+1] = k1
            end
        end
        user[k] = {
            index = k,
            ready = false,
            show_card = {
                own_card = own_card,
                weave_card = v.weave_card,
                score = 0,
            },
        }
    end
    local rmsg, rinfo = func.update_msg(user, {
        status=self._status, count=self._count,
    })
    broadcast(rmsg, rinfo, role, id)
    if self._status == base.CHESS_STATUS_FINISH then
        self:finish()
    end
    return rmsg, rinfo
end

function dymj:deal(info)
    local c = self._card[self._left]
    self._left = self._left - 1
    info.type_card[c] = info.type_card[c] + 1
    info.last_deal = c
    info.out = true
    local respond = info.respond
    respond[base.MJ_OP_CHI], respond[base.MJ_OP_PENG], respond[base.MJ_OP_GANG] = false, false, false
    info.pass = false
    local op = info.op
    op[base.MJ_OP_CHI], op[base.MJ_OP_PENG], op[base.MJ_OP_GANG] = 0, 0, 0
    self._deal_index = info.index
    self._deal_card = c
    return c
end

function dymj:start()
    if self._custom_card then
        self._card = util.clone(self._custom_card)
    else
        local card = {
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
        self._card = card
        util.shuffle(card, self._rand)
    end
    self._status = base.CHESS_STATUS_START
    self._left = #self._card
    self._out_card = 0
    self._out_index = 0
    local role = self._role
    for j = 1, base.MJ_FOUR do
        local v = role[(self._banker+j-2)%base.MJ_FOUR+1]
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
        v.out = false
        local deal_card = {}
        for i = 1, base.MJ_ROLE_CARD do
            deal_card[i] = self:deal(v)
        end
        v.deal_card = deal_card
    end
    self:deal(role[self._banker])
end

return {__index=dymj}
