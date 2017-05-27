local skynet = require "skynet"
local share = require "share"
local util = require "util"

local role
local game

local update_user = util.update_user
local error_code

local proc = {}
local gm = {proc = proc}

skynet.init(function()
    error_code = share.error_code
end)

function gm.init_module()
	game = require "game"
    role = require "game.role"
end

--------------------------protocol process-----------------------

function proc.add_room_card(msg)
    if game.data.user.gm_level == 0 then
        error{code = error_code.ROLE_NO_PERMIT}
    end
    if not msg.num then
        error{code = error_code.ERROR_ARGS}
    end
    local p = update_user()
    role.add_room_card(p, msg.num)
    return "update_user", {update=p}
end

function proc.dymj_card(msg)
    local data = game.data
    if data.user.gm_level == 0 then
        error{code = error_code.ROLE_NO_PERMIT}
    end
    data.dymj_card = msg.card
    if data.table then
        return skynet.call(data.table, "lua", "custom_card", "dymj", msg.card)
    else
        return "respond", ""
    end
end

return gm
