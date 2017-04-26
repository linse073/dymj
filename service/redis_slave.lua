local skynet = require "skynet"
local redis = require "redis"
local util = require "util"

local assert = assert

local CMD = {}

function CMD.open(conf, name)
    local db = redis.connect(conf)
    util.cmd_wrap(CMD, db)
end

skynet.start(function()
	skynet.dispatch("lua", function(session, source, command, ...)
		local f = assert(CMD[command])
        if session == 0 then
            f(...)
        else
            skynet.retpack(f(...))
        end
	end)
end)
