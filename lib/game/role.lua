local skynet = require "skynet"
local timer = require "timer"
local share = require "share"
local notify = require "notify"
local util = require "util"

local pairs = pairs
local ipairs = ipairs
local assert = assert
local error = error
local string = string
local math = math
local floor = math.floor
local tonumber = tonumber
local pcall = pcall
local table = table

local game

local proc = {}
local role = {proc = proc}

local update_user = util.update_user
local error_code
local base
local cz
local rand
local valid_chess
local role_mgr
local offline_mgr
local table_mgr
local chess_mgr
local gm_level = tonumber(skynet.getenv("gm_level"))
local start_utc_time = tonumber(skynet.getenv("start_utc_time"))
local user_db
local info_db

skynet.init(function()
    error_code = share.error_code
    base = share.base
    cz = share.cz
    rand = share.rand
    valid_chess = share.valid_chess
    role_mgr = skynet.queryservice("role_mgr")
    offline_mgr = skynet.queryservice("offline_mgr")
    table_mgr = skynet.queryservice("table_mgr")
    chess_mgr = skynet.queryservice("chess_mgr")
	local master = skynet.queryservice("mongo_master")
    user_db = skynet.call(master, "lua", "get", "user")
    info_db = skynet.call(master, "lua", "get", "info")
end)

function role.init_module()
	game = require "game"
end

local function get_user()
	cz.start()
	local data = game.data
    if not data.user then
		local user = skynet.call(user_db, "lua", "findOne", {id=data.id})
		if user then
			user.nick_name = data.nick_name
			user.head_img = data.head_img
			user.ip = data.ip
			data.user = user
			data.info = {
				_id = user._id,
				account = user.account,
				id = user.id,
				sex = user.sex,
				nick_name = user.nick_name,
				head_img = user.head_img,
				ip = user.ip,
			}
		else
			local now = floor(skynet.time())
			local user = {
				_id = data.id,
				account = data.uid,
				id = data.id,
				sex = data.sex or rand.randi(1, 2),
				login_time = 0,
				last_login_time = 0,
				logout_time = 0,
				gm_level = gm_level,
				create_time = now,
				room_card = 0,
				nick_name = data.nick_name,
				head_img = data.head_img,
				ip = data.ip,
			}
			skynet.call(user_db, "lua", "safe_insert", user)
			data.user = user
			local info = {
				_id = user._id,
				account = user.account,
				id = user.id,
				sex = user.sex,
				nick_name = user.nick_name,
				head_img = user.head_img,
				ip = user.ip,
			}
			skynet.call(info_db, "lua", "safe_insert", info)
			data.info = info
		end
    end
	cz.finish()
end

function role.init()
	local data = game.data
    data.heart_beat = 0
    timer.add_routine("heart_beat", role.heart_beat, 300)
    local server_mgr = skynet.queryservice("server_mgr")
    data.server = skynet.call(server_mgr, "lua", "get", data.serverid)
	local now = floor(skynet.time())
    rand.init(now)
	-- you may load user data from database
	skynet.fork(get_user)
end

function role.exit()
    timer.del_routine("save_role")
    timer.del_routine("heart_beat")
    local data = game.data
    local user = data.user
    if user then
        skynet.call(role_mgr, "lua", "logout", user.id)
        user.logout_time = floor(skynet.time())
        role.save_user()
    end
    notify.exit()
    local chess_table = data.chess_table
    if chess_table then
        skynet.call(chess_table, "lua", "status", data.id, base.USER_STATUS_LOGOUT)
    end
end

function role.save_user()
    local data = game.data
    skynet.call(user_db, "lua", "safe_insert", data.user)
    skynet.call(info_db, "lua", "safe_insert", data.info)
end

function role.save_routine()
    role.save_user()
end

function role.heart_beat()
	local data = game.data
    if data.heart_beat == 0 then
        skynet.error(string.format("heart beat kick user %d.", data.id))
        skynet.call(data.gate, "lua", "kick", data.id) -- data is nil
    else
        data.heart_beat = 0
    end
end

function role.afk()
    local data = game.data
    local chess_table = data.chess_table
    if chess_table then
        skynet.call(chess_table, "lua", "status", data.id, base.USER_STATUS_LOST)
    end
end

local function btk()
    local data = game.data
    local chess_table = data.chess_table
    if chess_table then
        skynet.call(chess_table, "lua", "status", data.id, base.USER_STATUS_ONLINE, addr)
    else
        local p = update_user()
        p.user.ip = addr
        notify.add("update_user", {update=p})
    end
end
function role.btk(addr)
    local data = game.data
    data.ip = addr
    data.user.ip = addr
    data.info.ip = addr
    if data.enter then
        skynet.fork(btk)
    end
end

function role.repair(user, now)
end

function role.add_room_card(p, inform, num)
    local user = game.data.user
    user.room_card = user.room_card + num
    p.user.room_card = user.room_card
    if inform then
        notify.add("update_user", {update=p})
    end
end

function role.leave()
    local data = game.data
    cz.start()
    assert(data.chess_table, string.format("user %d not in chess.", data.id))
    skynet.error(string.format("user %d leave chess.", data.id))
    data.chess_table = nil
    cz.finish()
end

-------------------protocol process--------------------------

function proc.notify_info(msg)
    return notify.send()
end

function proc.heart_beat(msg)
    local data = game.data
    data.heart_beat = data.heart_beat + 1
    return "heart_beat_response", {time=msg.time, server_time=skynet.time()*100}
end

function proc.enter_game(msg)
	cz.start()
	local data = game.data
    if data.enter then
        error{code = error_code.ROLE_ALREADY_ENTER}
    end
	local user = data.user
    local now = floor(skynet.time())
    role.repair(user, now)
    user.last_login_time = user.login_time
    user.login_time = now
	game.iter("enter")
    local ret = {user=user}
    local om = skynet.call(offline_mgr, "lua", "get", user.id)
    if om then
        local p = update_user()
        for k, v in ipairs(om) do
            table.insert(v, 3, p)
            game.one(table.unpack(v))
        end
    end
    local pack = game.iter_ret("pack_all")
    for _, v in ipairs(pack) do
        ret[v[1]] = v[2]
    end
    local chess_table = skynet.call(chess_mgr, "lua", "get", user.id)
    if chess_table then
        data.chess_table = chess_table
        ret.chess = skynet.call(chess_table, "lua", "pack", user.id, user.ip, skynet.self())
    elseif msg.name and msg.number then
        chess_table = skynet.call(table_mgr, "lua", "get", msg.number)
        if chess_table then
            local rmsg, info = skynet.call(chess_table, "lua", "join", msg.name, data.info, skynet.self())
            if rmsg == "update_user" then
                data.chess_table = chess_table
                skynet.call(chess_mgr, "lua", "add", data.id, chess_table)
                ret.chess = info.update.chess
            end
        end
    end
    timer.add_routine("save_role", role.save_routine, 300)
    skynet.call(role_mgr, "lua", "enter", data.info, skynet.self())
    data.enter = true
    cz.finish()
    return "info_all", {user=ret, start_time=start_utc_time}
end

function proc.get_offline(msg)
    local data = game.data
    local om = skynet.call(offline_mgr, "lua", "get", user.id)
    if om then
        local p = update_user()
        for k, v in ipairs(om) do
            table.insert(v, 3, p)
            game.one(table.unpack(v))
        end
        return "update_user", {update=p}
    else
        return "response", ""
    end
end

function proc.get_role(msg)
    local user = skynet.call(role_mgr, "lua", "get_user", msg.id)
    if not user then
        error{code = error_code.ROLE_NOT_EXIST}
    end
    local puser = {
        user = user,
    }
    return "role_info", {info=puser}
end

function proc.new_chess(msg)
    if not valid_chess[msg.name] then
        error{code = error_code.NO_CHESS}
    end
    local data = game.data
    cz.start()
    if data.chess_table then
        error{code = error_code.ALREAD_IN_CHESS}
    end
    local rule = {pack=msg.rule}
    local p, c = string.unpack("BB", msg.rule)
    if p == 1 then
        rule.aa_pay = true
    else
        rule.aa_pay = false
    end
    if c == 1 then
        rule.total_count = 8
    else
        rule.total_count = 16
    end
    local user = data.user
    if rule.aa_pay then
        if user.room_card < rule.total_count/8 then
            error{code = error_code.ROOM_CARD_LIMIT}
        end
    else
        if user.room_card < rule.total_count/2 then
            error{code = error_code.ROOM_CARD_LIMIT}
        end
    end
    assert(not skynet.call(chess_mgr, "lua", "get", data.id), string.format("Chess mgr has %d.", data.id))
    local chess_table = skynet.call(table_mgr, "lua", "new")
    if not chess_table then
        error{code = error_code.INTERNAL_ERROR}
    end
    local card = data[msg.name .. "_card"]
    local rmsg, info = skynet.call(chess_table, "lua", "init", 
        msg.name, rule, data.info, skynet.self(), data.server_address, card)
    if rmsg == "update_user" then
        data.chess_table = chess_table
    else
        skynet.call(table_mgr, "lua", "free", chess_table)
    end
    cz.finish()
    return rmsg, info
end

function proc.join(msg)
    local chess_table = skynet.call(table_mgr, "lua", "get", msg.number)
    if not chess_table then
        error{code = error_code.ERROR_CHESS_NUMBER}
    end
    local data = game.data
    cz.start()
    if data.chess_table then
        error{code = error_code.ALREAD_IN_CHESS}
    end
    assert(not skynet.call(chess_mgr, "lua", "get", data.id), string.format("Chess mgr has %d.", data.id))
    local user = data.user
    local rmsg, info = skynet.call(chess_table, "lua", "join", msg.name, data.info, user.room_card, skynet.self())
    if rmsg == "update_user" then
        data.chess_table = chess_table
    end
    cz.finish()
    return rmsg, info
end

return role
