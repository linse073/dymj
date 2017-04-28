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

skynet.init(function()
    cz = share.cz
    base = share.base
    error_code = share.error_code
end)

local dymj = {}

function dymj:init(number, rule)
    self._number = number
    local c, p = string.unpack("BB")
    print("game rule:", c, p)
    if c then
        self._count = 16
    else
        self._count = 8
    end
    if p then
        self._50limit = true
    end
    self._magic_card = 45
    self._banker = random(base.MJ_FOUR)
end

function dymj:finish()

end

function dymj:enter(id, agent)
    local info = {
        id = id,
        agent = agent,
        score = 0,
    }
    local role = self._role
    role[#role+1] = info
    self._id[id] = info
    return "update_user", {}
end

function dymj:join(id, agent)
    local role = self._role
    if #role >= base.MJ_FOUR then
        error{code = error_code.CHESS_ROLE_FULL}
    end
    local info = self._id[id]
    if info then
        error{code = error_code.ALREAD_IN_CHESS}
    end
    return dymj:enter(id, agent)
end

function dymj:ready(id)
    local info = self._id[id]
    if not info then
        error{code = error_code.NOT_IN_CHESS}
    end
    if info.ready then
        error{code = error_code.ALREADY_READY}
    end
    info.ready = true
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
    for k, v in ipairs(self._role) do
        v.ready = false
        v.card = {}
        v.type_card = {}
    end
end

return {__index=dymj}
