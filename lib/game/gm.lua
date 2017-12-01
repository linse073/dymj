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
    role.add_room_card(p, false, msg.num)
    return "update_user", {update=p}
end

function proc.dymj_card(msg)
    local data = game.data
    if data.user.gm_level == 0 then
        error{code = error_code.ROLE_NO_PERMIT}
    end
    local card = msg.card
    if card then
        card = util.reverse(card)
    end
    data.dymj_card = card
    if data.chess_table then
        return skynet.call(data.chess_table, "lua", "custom_card", "dymj", card)
    else
        return "response", ""
    end
end

function proc.jdmj_card(msg)
    local data = game.data
    if data.user.gm_level == 0 then
        error{code = error_code.ROLE_NO_PERMIT}
    end
    local card = msg.card
    if card then
        card = util.reverse(card)
    end
    data.jdmj_card = card
    if data.chess_table then
        return skynet.call(data.chess_table, "lua", "custom_card", "jdmj", card)
    else
        return "response", ""
    end
end

function proc.jd13_card(msg)
    local data = game.data
    if data.user.gm_level == 0 then
        error{code = error_code.ROLE_NO_PERMIT}
    end
    local card = msg.card
    if card then
        card = util.reverse(card)
    end
    data.jd13_card = card
    if data.chess_table then
        return skynet.call(data.chess_table, "lua", "custom_card", "jd13", card)
    else
        return "response", ""
    end
end

function proc.dy13_card(msg)
    local data = game.data
    if data.user.gm_level == 0 then
        error{code = error_code.ROLE_NO_PERMIT}
    end
    local card = msg.card
    if card then
        card = util.reverse(card)
    end
    data.dy13_card = card
    if data.chess_table then
        return skynet.call(data.chess_table, "lua", "custom_card", "dy13", card)
    else
        return "response", ""
    end
end

function proc.jhbj_card(msg)
    local data = game.data
    if data.user.gm_level == 0 then
        error{code = error_code.ROLE_NO_PERMIT}
    end
    local card = msg.card
    if card then
        card = util.reverse(card)
    end
    data.jhbj_card = card
    if data.chess_table then
        return skynet.call(data.chess_table, "lua", "custom_card", "jhbj", card)
    else
        return "response", ""
    end
end

function proc.test_update_day(msg)
    local data = game.data
    if data.user.gm_level == 0 then
        error{code = error_code.ROLE_NO_PERMIT}
    end
    return role.test_update_day()
end

return gm
