local skynet = require "skynet"
local util = require "util"
local sharedata = require "skynet.sharedata"

local assert = assert
local ipairs = ipairs
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

return func
