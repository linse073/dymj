local skynet = require "skynet"
local share = require "share"
local broadcast = require "broadcast"
local util = require "util"

local string = string
local random = math.random
local ipairs = ipairs
local pairs = pairs

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

function dymj:init(number, rule)
    self._number = number
    self._rule = rule
    local c, p = string.unpack(rule, "BB")
    print("game rule:", c, p)
    if c then
        self._count = 16
    else
        self._count = 8
    end
    if p then
        self._limit50 = true
    end
    self._magic_card = 45
    self._banker = random(base.MJ_FOUR)
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
    local other = self._id[id]
    if other then
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
    {-2, -1},
    {-1, 1},
    {1, 2},
}
function dymj:analyze(card, id)
    for k, v in ipairs(self._role) do
        if v.id ~= id then
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
            else
                v.pass = true
            end
            local action = v.action
            action[base.MJ_OP_CHI], action[base.MJ_OP_PENG], action[base.MJ_OP_GANG] = false, false, false
        end
    end
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
    type_card[card] = type_card[card] - 1
    self._out_card = card
    self:analyze(card, id)
    local rmsg = {chess={user={{index=info.index, out_card=card}}}}
    broadcast("update_user", rmsg, self._role, id)
    return "update_user", rmsg
end

function dymj:hu_card(id, msg)
    local info = self:op_check(id, base.CHESS_STATUS_START)
    if self._deal_index ~= info.index then
        error{code = error_code.ERROR_DEAL_INDEX}
    end
end

function dymj:chi_card(id, msg)
    local info = self:op_check(id, base.CHESS_STATUS_START)
end

function dymj:peng_card(id, msg)
    local info = self:op_check(id, base.CHESS_STATUS_START)
end

function dymj:gang_card(id, msg)
    local info = self:op_check(id, base.CHESS_STATUS_START)
end

function dymj:pass_card(id, msg)
    local info = self:op_check(id, base.CHESS_STATUS_START)
end

function dymj:finish()
    self._status = base.CHESS_STATUS_READY
    for k, v in ipairs(self._role) do
        v.ready = false
    end
end

function dymj:deal(info, num)
    local card = self._card
    local type_card = info.type_card
    local left = self._left
    for i = 1, num do
        local c = card[left]
        left = left - 1
        type_card[c] = type_card[c] + 1
    end
    self._left = left
    self._deal_index = info.index
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
    util.shuffle(card)
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
        c.type_card = type_card
        c.weave_card = {}
        c.respond = {}
        c.action = {}
        self:deal(v, base.MJ_ROLE_CARD)
    end
    self:deal(role[self._banker], 1)
end

return {__index=dymj}
