local skynet = require "skynet"
local util = require "util"
local share = require "share"

local assert = assert
local pcall = pcall
local string = string
local setmetatable = setmetatable
local math = math
local floor = math.floor
local randomseed = math.randomseed

local number = tonumber(...)
local cz

local CMD = {}
util.timer_wrap(CMD)

local logic

function CMD.start(name, rule, id, agent)
    logic = setmetatable({}, require(name))
    logic:init(number, rule)
    return logic:enter(id, agent)
end

function CMD.finish()
    logic:finish()
    logic = nil
end

function CMD.exit()
    skynet.exit()
end

skynet.start(function()
    randomseed(floor(skynet.time()))
    cz = share.cz

	skynet.dispatch("lua", function(session, source, command, ...)
		local f = CMD[command]
        if f then
            skynet.retpack(f(...))
        else
            f = assert(logic[command], string.format("No logic procedure %s.", command))
            local ok, rmsg, info = pcall(f, logic, ...)
            cz.over()
            skynet.retpack(ok, rmsg, info)
        end
	end)
end)
