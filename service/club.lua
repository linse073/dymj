local skynet = require "skynet"

local assert = assert

local CMD = {}

function CMD.exit()
	skynet.exit()
end

function CMD.open(id, roleid)
    
end

function CMD.login(roleid)
    
end

function CMD.logout(roleid)
    
end

function CMD.get_info()
    
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
