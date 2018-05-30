local skynet = require "skynet"
local mongo = require "skynet.db.mongo"
local util = require "util"

local assert = assert
local tostring = tostring

local database = skynet.getenv("database")

local CMD = {}

local db
local cursor = {}

function CMD.open(conf, name)
    local d = mongo.client(conf)
    db = d[database][name]
    util.cmd_wrap(CMD, db)
end

function CMD.find(...)
    local c = db:find(...)
    local key = tostring(c)
    cursor[key] = c
    return key
end

function CMD.get_next(key)
    local c = cursor[key]
    if c:hasNext() then
        return c:next()
    else
        cursor[key] = nil
    end
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
