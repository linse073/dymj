local skynet = require "skynet"
local game = require "game"
local util = require "util"
local share = require "share"
local notify = require "notify"
local func = require "func"

local assert = assert
local pcall = pcall
local type = type
local string = string

skynet.register_protocol {
	name = "client",
	id = skynet.PTYPE_CLIENT,
    unpack = skynet.tostring,
}

local proc = game.proc
local msg
local name_msg
local sproto
local error_code
local cz

local LOGIC_MSG_BEGIN = 20000

local CMD = {}
util.timer_wrap(CMD)
game.iter("init_module")

function CMD.login(info)
	-- you may use secret to make a encrypted data stream
	skynet.error(string.format("%d is login", info.id))
    game.init(info)
end

local function logout()
	local data = game.data
    skynet.error(string.format("%d is logout from agent", data.id))
    game.exit()
    skynet.call(data.gate, "lua", "logout", data.id)
end

function CMD.logout()
	-- NOTICE: The logout MAY be reentry
    if game.data then
        logout()
    end
end

function CMD.afk()
	-- the connection is broken, but the user may back
	local data = game.data
    if data then
        skynet.error(string.format("%d afk", data.id))
        game.iter("afk")
    end
end

function CMD.btk(addr)
    local data = game.data
    if data then
        skynet.error(string.format("%d btk", data.id))
        game.iter("btk", addr)
    end
end

function CMD.exit()
	local data = game.data
    assert(not data, string.format("Agent exit error %d.", data.id))
	skynet.exit()
end

function CMD.notify(msg, info)
    notify.add(msg, info)
end

function CMD.get_user()
    return game.data.user
end

function CMD.get_info()
    return game.data.info
end

function CMD.action(module, func, ...)
	return game.one(module, func, ...)
end

skynet.start(function()
    msg = share.msg
    name_msg = share.name_msg
    sproto = share.sproto
    error_code = share.error_code
	cz = share.cz

	-- If you want to fork a work thread, you MUST do it in CMD.login
	skynet.dispatch("lua", function(session, source, command, ...)
		local f = assert(CMD[command])
        if session == 0 then
            f(...)
        else
            skynet.retpack(f(...))
        end
	end)

	skynet.dispatch("client", function(_, _, content)
        local id = content:byte(1) * 256 + content:byte(2)
        local arg = content:sub(3)
        local msgname = assert(msg[id], string.format("No protocol %d.", id))
        if sproto:exist_type(msgname) then
            arg = sproto:pdecode(msgname, arg)
        end
        local ok, rmsg, info
        if id < LOGIC_MSG_BEGIN then
            local f = assert(proc[msgname], string.format("No protocol procedure %s.", msgname))
            ok, rmsg, info = pcall(f, arg)
            cz.over()
            rmsg, info = func.return_msg(ok, rmsg, info)
        else
            local data = game.data
            if data and data.chess_table then
                rmsg, info = skynet.call(data.chess_table, "lua", msgname, data.id, arg)
            else
                rmsg, info = "error_code", {code = error_code.NOT_JOIN_CHESS}
            end
        end
        if sproto:exist_type(rmsg) then
            info = sproto:pencode(rmsg, info)
        end
        local rid = assert(name_msg[rmsg], string.format("No protocol %s.", rmsg))
        skynet.ret(string.pack(">I2", rid) .. info)
	end)
end)
