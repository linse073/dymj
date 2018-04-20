local skynet = require "skynet"

local ipairs = ipairs
local assert = assert

local role_club = {}

local CMD = {}

function CMD.batch_add(ids, clubid, agent)
    for k, v in ipairs(ids) do
        CMD.add(v, clubid, agent)
    end
end

function CMD.add(id, clubid, agent)
    local c = role_club[id]
    if not c then
        c = {{}, 0}
        role_club[id] = c
    end
    c[1][clubid] = agent
    c[2] = c[2] + 1
end

function CMD.batch_del(ids, clubid)
    for k, v in ipairs(ids) do
        CMD.del(v, clubid)
    end
end

function CMD.del(id, clubid)
    local c = role_club[id]
    if c then
        c[1][clubid] = nil
        c[2] = c[2] - 1
    else
        skynet.error(string.format("Role %d not in club %d.", id, clubid))
    end
end

function CMD.get(id)
    local c = role_club[id]
    if c then
        return c[1]
    end
end

function CMD.count(id)
    local c = role_club[id]
    if c then
        return c[2]
    end
    return 0
end

skynet.start(function()
	skynet.dispatch("lua", function(session, source, command, ...)
		local f = assert(CMD[command])
        skynet.retpack(f(...))
	end)
end)
