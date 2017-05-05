local skynet = require "skynet"
local share = require "share"
local broadcast = require "broadcast"
local util = require "util"

local string = string
local ipairs = ipairs
local pairs = pairs
local table = table

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
    return c<=base.MJ_CARD_INDEX and not mj_invalid_card[c]
end

local dymj = {}

function dymj:init(number, rule, rand)
    self._number = number
    self._rule = rule
    self._rand = rand
    local c, p = string.unpack(rule, "BB")
    print("game rule:", c, p)
    if c then
        self._total_count = 16
    else
        self._total_count = 8
    end
    if p then
        self._limit50 = true
    end
    self._magic_card = 45
    self._banker = rand.randi(1, base.MJ_FOUR)
    self._status = base.CHESS_STATUS_READY
end

function dymj:destroy()

end

function dymj:enter(info, agent)
    info.agent = agent
    local role = self._role
    local index = #role + 1
    info.index = index
    info.score = 0
    info.ready = false
    role[index] = info
    self._id[id] = info
    return "update_user", {
        name = "dymj",
        number = self._number,
        rule = self._rule,
        banker = self._banker,
        user = role,
        status = self._status,
    }
end

function dymj:join(name, info, agent)
    if name ~= "dymj" then
        error{code = error_code.ERROR_CHESS_NAME}
    end
    if self._status ~= base.CHESS_STATUS_READY then
        error{code = error_code.ERROR_CHESS_STATUS}
    end
    local role = self._role
    if #role >= base.MJ_FOUR then
        error{code = error_code.CHESS_ROLE_FULL}
    end
    local i = self._id[id]
    if i then
        error{code = error_code.ALREAD_IN_CHESS}
    end
    local rmsg, rinfo = self:enter(info, agent)
    broadcast("update_user", {user={info}}, role, info.id)
    return rmsg, rinfo
end

function dymj:is_all_ready()
    for k, v in ipairs(self._role) do
        if not v.ready then
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
    local chess = {user=user}
    if self:is_all_ready() then
        self:start()
        chess.status = self._status
        chess.left = self._left
        chess.deal_index = self._deal_index
        local own_card = {}
        for k, v in pairs(info.type_card) do
            for i = 1, v do
                own_card[#own_card+1] = k
            end
        end
        user.own_card = own_card
    end
    broadcast("update_user", {chess=chess}, self._role, id)
    return "update_user", rmsg
end

local CHI_RULE = {
    {-2, -1, -2},
    {-1, 1, -1},
    {1, 2, 0},
}
function dymj:analyze(card, id)
    local has_respond = false
    for k, v in ipairs(self._role) do
        if v.id ~= id and card ~= self._magic_card then
            local type_card = v.type_card
            local chi = false
            for k1, v1 in ipairs(CHI_RULE) do
                if type_card[card+v1[1]]>=1 and type_card[card+v1[2]]>=1 then
                    chi = true
                    break
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
            local action = v.action
            action[base.MJ_OP_CHI], action[base.MJ_OP_PENG], action[base.MJ_OP_GANG] = 0, 0, 0
        else
            local respond = v.respond
            respond[base.MJ_OP_CHI], respond[base.MJ_OP_PENG], respond[base.MJ_OP_GANG] = false, false, false
            v.pass = true
            local action = v.action
            action[base.MJ_OP_CHI], action[base.MJ_OP_PENG], action[base.MJ_OP_GANG] = 0, 0, 0
        end
    end
    return has_respond
end

function dymj:out_card(id, msg)
    local info = self:op_check(id, base.CHESS_STATUS_START)
    if self._deal_index ~= info.index then
        error{code = error_code.ERROR_DEAL_INDEX}
    end
    local type_card = info.type_card
    local card = msg.card
    if not type_card[card] then
        error{code = error_code.INVALID_CARD}
    end
    if type_card[card] == 0 then
        error{code = error_code.NO_OUT_CARD}
    end
    local magic = false
    local role = self._role
    for k, v in ipairs(role) do
        if v.out_magic > 0 then
            magic = true
        end
    end
    if magic and card ~= self._deal_card then
        error{code = error_code.OUT_CARD_LIMIT}
    end
    if self._left <= 20 then
        self:conclude(id)
    else
        type_card[card] = type_card[card] - 1
        info.gang_count = 0
        if card == self._magic_card then
            info.out_magic = info.out_magic + 1
        else
            info.out_magic = 0
        end
        self._out_card = card
        local deal_index
        if not self:analyze(card, id) then
            deal_index = self._deal_index%base.MJ_FOUR+1
            local c = self:deal(role[deal_index])
            skynet.send(v.agent, "lua", "notify", "update_user", {chess={
                user={
                    {index=info.index, out_card=card},
                    {index=deal_index, own_card={c}},
                },
                deal_index=deal_index,
            }})
        end
        local rmsg = {chess={user={{index=info.index, out_card=card}}, deal_index=deal_index}}
        for k, v in ipairs(role) do
            if v.id ~= id and v.index ~= deal_index then
                skynet.send(v.agent, "lua", "notify", "update_user", rmsg)
            end
        end
        return "update_user", rmsg
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
                            local n = type_card[i]
                            if n then
                                type_card[i] = n + 1
                            else
                                type_card[i] = 1
                            end
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
        local n = clone[deal_card]
        dec(clone, deal_card, 1)
        weave_card[#weave_card+1] = {deal_card, 0}
        if find_weave(clone, weave_card, magic_count-1) then
            return true
        end
        weave_card[#weave_card] = nil
        clone[deal_card] = n
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
    local magic_count = type_card[self._magic_card]
    local four_count = 0
    for k, v in pairs(type_card) do
        if k ~= self._magic_card then
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
                four_count = four_count + 1
            elseif v == 4 then
                four_count = four_count + 1
            end
        end
    end
    return true, four_count
end

function dymj:hu(id, msg)
    local info = self:op_check(id, base.CHESS_STATUS_START)
    if self._deal_index ~= info.index then
        error{code = error_code.ERROR_DEAL_INDEX}
    end
    local type_card = info.type_card
    local mul = 1
    local hu, four_count = self:is_qidui(type_card)
    if hu then
        mul = 2^(four_count+1)
        if type_card[self._deal_card]%2 == 1 then
            mul = mul * 2^(info.out_magic+1)
        end
    else
        local tc = {}
        for k, v in pairs(type_card) do
            if v > 0 then
                tc[k] = v
            end
        end
        local magic_count = tc[self._magic_card] or 0
        tc[self._magic_card] = nil
        local weave_card = {}
        if not self:check_hu(tc, weave_card, magic_count) then
            error{code = error_code.ERROR_OPERATION}
        end
        mul = 2^info.gang_count
        local head = weave_card[1]
        if head[1] == self._deal_card and head[2] == 0 then
            mul = mul * 2^(info.out_magic+1)
        end
    end
    self._status = base.CHESS_STATUS_READY
    self._count = self._count + 1
    local user = {}
    for k, v in ipairs(self._role) do
        v.ready = false
        if k == info.index then
            v.score = v.score + mul * 3
        else
            v.score = v.score - mul
        end
        local own_card = {}
        for k1, v1 in pairs(v.type_card) do
            for i = 1, v1 do
                own_card[#own_card+1] = k1
            end
        end
        user[k] = {
            index = k,
            own_card = own_card,
            weave_card = v.weave_card,
            ready = false,
            score = v.score,
        }
    end
    user[info.index].action = base.MJ_OP_HU
    local rmsg = {chess={user=user, status=self._status, count=self._count, banker=info.index}}
    broadcast("update_user", rmsg, self._role, id)
    return "update_user", rmsg
end

function dymj:check_prior(index, op)
    local front = true
    for i = 1, base.MJ_FOUR-1 do
        local n = (self._deal_index+i-1)%base.MJ_FOUR+1
        if n == index then
            front = false
        else
            local other = self._role[n]
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
    if info.chi_count >= base.MJ_CHI_COUNT then
        error{code = error_code.CHI_COUNT_LIMIT}
    end
    if info.action[base.MJ_OP_CHI] > 0 then
        error{code = error_code.WAIT_FOR_OTHER}
    end
    if not info.respond[base.MJ_OP_CHI] then
        error{code = error_code.ERROR_OPERATION}
    end
    local valid = false
    local type_card = info.type_card
    local card = msg.card
    for i = card, card+2 do
        if i == self._out_card then
            valid = true
        elseif not (type_card[i] >= 1) then
            error{code = error_code.ERROR_OPERATION}
        end
    end
    if not valid then
        error{code = error_code.ERROR_OPERATION}
    end
    if self:check_prior(info.index, base.MJ_OP_CHI) then
        info.action[base.MJ_OP_CHI] = card
        return "update_user", {chess={user={{
            index = info.index,
            action = base.MJ_OP_CHI,
        }}}}
    else
        for i = card, card+2 do
            if i ~= self._out_card then
                type_card[i] = type_card[i] - 1
            end
        end
        local weave = {
            op = base.MJ_OP_CHI,
            card = card,
        }
        info.weave_card[#info.weave_card+1] = weave
        local rmsg = {chess={user={{
            index = info.index,
            weave_card = {weave},
        }}}}
        broadcast("update_user", rmsg, self._role, id)
        return "update_user", rmsg
    end
end

function dymj:peng(id, msg)
    local info = self:op_check(id, base.CHESS_STATUS_START)
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
    }
    info.weave_card[#info.weave_card+1] = weave
    local rmsg = {chess={user={{
        index = info.index,
        weave_card = {weave},
    }}}}
    broadcast("update_user", rmsg, self._role, id)
    return "update_user", rmsg
end

function dymj:gang(id, msg)
    local info = self:op_check(id, base.CHESS_STATUS_START)
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
    }
    info.weave_card[#info.weave_card+1] = weave
    info.gang_count = info.gang_count + 1
    local c = self:deal(info)
    local rmsg = {chess={
        user={{
            index = info.index,
            weave_card = {weave},
        }},
        deal_index = info.index,
    }}
    broadcast("update_user", rmsg, self._role, id)
    return "update_user", {chess={
        user={{
            index = info.index,
            weave_card = {weave},
            own_card = {c},
        }},
        deal_index = info.index,
    }}
end

function dymj:hide_gang(id, msg)
    local info = self:op_check(id, base.CHESS_STATUS_START)
    if self._deal_index ~= info.index then
        error{code = error_code.ERROR_DEAL_INDEX}
    end
    local type_card = info.type_card
    local deal_card = self._deal_card
    if not (type_card[deal_card] >= 4) then
        error{code = error_code.ERROR_OPERATION}
    end
    type_card[deal_card] = type_card[deal_card] - 4
    local weave = {
        op = base.MJ_OP_HIDE_GANG,
        card = deal_card,
    }
    info.weave_card[#info.weave_card+1] = weave
    info.gang_count = info.gang_count + 1
    local c = self:deal(info)
    local rmsg = {chess={
        user={{
            index = info.index,
            weave_card = {{
                op = base.MJ_OP_HIDE_GANG,
                card = 0,
            }},
        }},
        deal_index = info.index,
    }}
    broadcast("update_user", rmsg, self._role, id)
    return "update_user", {chess={
        user={{
            index = info.index,
            weave_card = {weave},
            own_card = {c},
        }},
        deal_index = info.index,
    }}
end

function dymj:pass(id, msg)
    local info = self:op_check(id, base.CHESS_STATUS_START)
    if info.pass then
        error{code = error_code.ALREADY_PASS}
    end
    info.pass = true
    local all_pass = true
    local role = self._role
    for k, v in ipairs(role) do
        if not v.pass then
            all_pass = false
            -- NOTICE: only check MJ_OP_CHI
            local card = v.action[base.MJ_OP_CHI]
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
                }
                v.weave_card[#v.weave_card+1] = weave
                local rmsg = {chess={user={{
                    index = v.index,
                    weave_card = {weave},
                }}}}
                broadcast("update_user", rmsg, role, id)
                return "update_user", {chess={user={
                    {index=v.index, weave_card={weave}},
                    {index=info.index, action=base.MJ_OP_PASS},
                }}}
            end
        end
    end
    local deal_index
    if all_pass then
        deal_index = self._deal_index%base.MJ_FOUR+1
        local c = self:deal(role[deal_index])
        skynet.send(v.agent, "lua", "notify", "update_user", {chess={
            user={{index=deal_index, own_card={c}}},
            deal_index=deal_index,
        }})
        local rmsg = {chess={deal_index=deal_index}}
        for k, v in ipairs(role) do
            if v.id ~= id and v.index ~= deal_index then
                skynet.send(v.agent, "lua", "notify", "update_user", rmsg)
            end
        end
    end
    return "update_user", {chess={
        user={{index=info.index, action=base.MJ_OP_PASS}},
        deal_index=deal_index,
    }}
end

function dymj:conclude(id, msg)
    local info = self:op_check(id, base.CHESS_STATUS_START)
    if self._deal_index ~= info.index then
        error{code = error_code.ERROR_DEAL_INDEX}
    end
    if self._left > 20 then
        error{code = error_code.CONCLUDE_CARD_LIMIT}
    end
    self._status = base.CHESS_STATUS_READY
    self._count = self._count + 1
    local user = {}
    for k, v in ipairs(self._role) do
        v.ready = false
        local own_card = {}
        for k1, v1 in pairs(v.type_card) do
            for i = 1, v1 do
                own_card[#own_card+1] = k1
            end
        end
        user[k] = {
            index = k,
            own_card = own_card,
            weave_card = v.weave_card,
            ready = false,
        }
    end
    local rmsg = {chess={user=user, status=self._status, count=self._count}}
    broadcast("update_user", rmsg, self._role, id)
    return "update_user", rmsg
end

function dymj:deal(info)
    local c = self._card[self._left]
    self._left = self._left - 1
    info.type_card[c] = info.type_card[c] + 1
    self._deal_index = info.index
    self._deal_card = c
    return c
end

function dymj:start()
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
    self._status = base.CHESS_STATUS_START
    self._left = #card
    self._out_card = 0
    local role = self._role
    for k, v in ipairs(role) do
        local type_card = {}
        for i = 1, base.MJ_CARD_INDEX do
            if not mj_invalid_card[i] then
                type_card[i] = 0
            end
        end
        v.type_card = type_card
        v.weave_card = {}
        v.respond = {}
        v.action = {}
        v.chi_count = 0
        v.gang_count = 0
        v.out_magic = 0
        for i = 1, base.MJ_ROLE_CARD do
            self:deal(v)
        end
    end
    self:deal(role[self._banker])
end

return {__index=dymj}
