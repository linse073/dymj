local skynet = require "skynet"
local util = require "util"

local assert = assert
local pcall = pcall
local type = type
local string = string

local CMD = {}
util.timer_wrap(CMD)

local logic

function CMD.start(name)
    logic = require(name).new()
end

function CMD.finish()
    logic:finish()
    logic = nil
end

function CMD.exit()
    skynet.exit()
end

skynet.start(function()
	skynet.dispatch("lua", function(session, source, command, ...)
		local f = CMD[command]
        if f then
            skynet.retpack(f(...))
        else
            f = assert(logic[command], string.format())
        end
	end)

	skynet.dispatch("client", function(_, _, content)
        local id = content:byte(1) * 256 + content:byte(2)
        local arg = content:sub(3)
        local msgname = assert(msg[id], string.format("No protocol %d.", id))
        if sproto:exist_type(msgname) then
            arg = sproto:pdecode(msgname, arg)
        end
        local f = assert(proc[msgname], string.format("No protocol procedure %s.", msgname))
        local ok, rmsg, info = pcall(f, arg)
		cz.over()
        if not ok then
            if type(rmsg) == "string" then
                skynet.error(rmsg)
                info = {code = error_code.INTERNAL_ERROR}
            else
                assert(type(rmsg) == "table")
                info = rmsg
            end
            rmsg = "error_code"
        end
        if sproto:exist_type(rmsg) then
            info = sproto:pencode(rmsg, info)
        end
        local rid = assert(name_msg[rmsg], string.format("No protocol %s.", rmsg))
        skynet.ret(string.pack(">I2", rid) .. info)
	end)
end)
