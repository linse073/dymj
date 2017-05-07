local skynet = require "skynet"
local util = require "util"
local sharedata = require "sharedata"

local assert = assert
local ipairs = ipairs
local string = string
local base
local day_second = 24 * 60 * 60
local start_routine_time = tonumber(skynet.getenv("start_routine_time"))

skynet.init(function()
    base = sharedata.query("base")
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

function func.update_msg(chess, user)
    return "update_user", {update={
        user = user,
        chess = chess,
    }}
end

return func
