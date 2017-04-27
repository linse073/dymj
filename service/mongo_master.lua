local skynet = require "skynet"

local assert = assert
local string = string
local ipairs = ipairs

local slave_list = {}

local CMD = {}

function CMD.open(conf)
    for k, v in ipairs(conf.name) do
        local slave = skynet.newservice("mongo_slave")
        skynet.call(slave, "lua", "open", {host=conf.host}, v)
        slave_list[v] = slave
    end
    for k, v in ipairs(conf.index) do
        skynet.call(slave_list[v[1]], "lua", "ensureIndex", v[2])
    end
end

function CMD.get(name)
    return assert(slave_list[name], string.format("No log server %s.", name))
end

function CMD.get_all()
    return slave_list
end

skynet.start(function()
	skynet.dispatch("lua", function(session, source, command, ...)
		local f = assert(CMD[command])
        skynet.retpack(f(...))
	end)
end)
