local skynet = require "skynet"

local assert = assert
local string = string

local role_list = {}

local CMD = {}

function CMD.add(id, chess)
    assert(not role_list[id], string.format("Already add role %d.", id))
    role_list[id] = chess
end

function CMD.del(id)
    assert(role_list[id], string.format("No role %d.", id))
    role_list[id] = nil
end

function CMD.get(id)
    return role_list[id]
end

skynet.start(function()
	skynet.dispatch("lua", function(session, source, command, ...)
		local f = assert(CMD[command])
        skynet.retpack(f(...))
	end)
end)
