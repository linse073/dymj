local skynet = require "skynet"
local util = require "util"
local sharedata = require "skynet.sharedata"

local assert = assert
local ipairs = ipairs
local type = type
local tonumber = tonumber
local string = string
local base
local error_code
local day_second = 24 * 60 * 60
local start_routine_time = tonumber(skynet.getenv("start_routine_time"))

skynet.init(function()
    base = sharedata.query("base")
    error_code = sharedata.query("error_code")
end)

local func = {}

function func.game_day(t, start_time)
    if start_time then
        start_time = util.day_time(start_time)
    else
        start_time = start_routine_time
    end
    local st = util.day_time(t)
    return (st - start_time) // day_second
end

function func.return_msg(ok, msg, info)
    if not ok then
        if type(msg) == "string" then
            skynet.error(msg)
            info = {code = error_code.INTERNAL_ERROR}
        else
            assert(type(msg) == "table")
            info = msg
        end
        msg = "error_code"
    end
    return msg, info
end

function func.poker_info(c)
    local tc = c - 1
    return tc//base.POKER_VALUE+1, tc%base.POKER_VALUE+1
end

function func.sort_poker_value(l, r)
    local lc, lv = func.poker_info(l)
    local rc, rv = func.poker_info(r)
    if lv ~= rv then
        return lv > rv
    end
    return lc > rc
end

function func.sort_poker_color(l, r)
    local lc, lv = func.poker_info(l)
    local rc, rv = func.poker_info(r)
    if lc ~= rc then
        return lc > rc
    end
    return lv > rv
end

function func.p13_special_score(i)
    local s = base.P13_SPECIAL_SCORE[i]
    if s then
        return s
    end
    return 6
end

return func
