local skynet = require "skynet"
local util = require "util"
local share = require "share"
local random = require "random"
local func = require "func"

local assert = assert
local pcall = pcall
local string = string
local setmetatable = setmetatable
local math = math
local floor = math.floor
local pairs = pairs

local number = tonumber(...)
local cz
local rand
local chess = {}

local CMD = {}
util.timer_wrap(CMD)

local logic

function CMD.init(name, rule, info, agent, server, card)
    rand.init(floor(skynet.time()))
    logic = setmetatable({}, chess[name])
    logic:init(number, rule, rand, server, card)
    return logic:enter(info, agent, 1)
end

function CMD.destroy()
    logic:destroy()
    logic = nil
end

function CMD.exit()
    skynet.exit()
end

skynet.start(function()
    cz = share.cz
    rand = share.rand
    for k, v in pairs(share.valid_chess) do
        chess[v] = require("logic." .. v)
    end

	skynet.dispatch("lua", function(session, source, command, ...)
		local f = CMD[command]
        local ok, rmsg, info
        if f then
            ok, rmsg, info = pcall(f, ...)
        else
            f = assert(logic[command], string.format("No logic procedure %s.", command))
            ok, rmsg, info = pcall(f, logic, ...)
        end
        cz.over()
        skynet.retpack(func.return_msg(ok, rmsg, info))
	end)
end)
