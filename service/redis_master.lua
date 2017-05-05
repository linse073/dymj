local skynet = require "skynet"

local assert = assert
local string = string
local ipairs = ipairs

local slave_list = {}

local CMD = {}

function CMD.open(conf)
    for k, v in ipairs(conf.name) do
        local slave = skynet.newservice("redis_slave")
        skynet.call(slave, "lua", "open", {host=conf.host, port=conf.port, db=conf.base+k-1}, v)
        slave_list[v] = slave
    end
end

function CMD.get(name)
    return assert(slave_list[name], string.format("No database slave %s.", name))
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
