local skynet = require "skynet"

local assert = assert
local string = string

local role_list = {}
local number_list = {}

local CMD = {}

function CMD.get()
end

skynet.start(function()
	skynet.dispatch("lua", function(session, source, command, ...)
		local f = assert(CMD[command])
        skynet.retpack(f(...))
	end)
end)
