local skynet = require "skynet"
local mongo = require "skynet.db.mongo"
local util = require "util"

local assert = assert

local database = skynet.getenv("database")

local CMD = {}

function CMD.open(conf, name)
    local d = mongo.client({host=conf.host})
    util.cmd_wrap(CMD, d[database][name])
end

skynet.start(function()
	skynet.dispatch("lua", function(session, source, command, ...)
		local f = assert(CMD[command])
        if session == 0 then
            f(...)
        else
            local r = f(...)
            util.dump(r)
            skynet.retpack(r)
        end
	end)
end)
