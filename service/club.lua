local skynet = require "skynet"
local util = require "util"

local assert = assert

local club_db
local club_info_db

local function save_db()
    
end

local CMD = {}
util.time_wrap(CMD)

function CMD.exit()
	skynet.exit()
end

function CMD.open(id, roleid)
    -- TODO: load club_info
    -- TODO: use skynet.fork to load clubdb
end

function CMD.login(roleid)
    
end

function CMD.logout(roleid)
    
end

function CMD.get_info()
    
end

skynet.start(function()
    local master = skynet.queryservice("mongo_master")
    club_db = skynet.call(master, "lua", "get", "club")
    club_info_db = skynet.call(master, "lua", "get", "club_info")

	skynet.dispatch("lua", function(session, source, command, ...)
		local f = assert(CMD[command])
        if session == 0 then
            f(...)
        else
            skynet.retpack(f(...))
        end
	end)
end)
