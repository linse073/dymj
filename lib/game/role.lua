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

local game

local proc = {}
local role = {proc = proc}

local update_user = util.update_user
local error_code
local base
local cz
local rand
local role_mgr
local offline_mgr
local table_mgr
local gm_level = tonumber(skynet.getenv("gm_level"))
local start_utc_time = tonumber(skynet.getenv("start_utc_time"))
local user_db
local info_db

skynet.init(function()
    error_code = share.error_code
    base = share.base
    cz = share.cz
    rand = share.rand
    role_mgr = skynet.queryservice("role_mgr")
    offline_mgr = skynet.queryservice("offline_mgr")
    table_mgr = skynet.queryservice("table_mgr")
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
				nick_name = user.nic_name,
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
    local user = game.data.user
    if user then
        skynet.call(role_mgr, "lua", "logout", user.id)
        user.logout_time = floor(skynet.time())
        role.save_user()
    end
    notify.exit()
end

function role.save_user()
    local data = game.data
    skynet.call(user_db, "lua", "save", data.user)
    skynet.call(info_db, "lua", "save", data.info)
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

function role.repair(user, now)
end

function role.add_room_card(p, num)
    local user = game.data.user
    user.room_card = user.room_card + num
    p.user.room_card = user.room_card
end

function role.leave()
    local data = game.data
    assert(data.table, string.format("user %d not in chess.", data.id))
    skynet.error(string.format("user %d leave chess.", data.id))
    data.table = nil
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
	-- local data = game.data
    -- if data.user then
        -- error{code = error_code.ROLE_ALREADY_ENTER}
    -- end
	local data = game.data
	local user = data.user
    local now = floor(skynet.time())
    role.repair(user, now)
    user.last_login_time = user.login_time
    user.login_time = now
	game.iter("enter")
    local p = update_user()
    local ret = {user=user}
    local om = skynet.call(offline_mgr, "lua", "get", user.id)
    if om then
        for k, v in ipairs(om) do
			game.one(v[1], "add", v[2], p)
        end
    end
    local pack = game.iter_ret("pack_all")
    for _, v in ipairs(pack) do
        ret[v[1]] = v[2]
    end
    timer.add_routine("save_role", role.save_routine, 300)
    skynet.call(role_mgr, "lua", "enter", data.info, skynet.self())
    cz.finish()
    return "info_all", {user=ret, start_time=start_utc_time}
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
    local name = "logic." .. msg.name
    local ok, chess = pcall(require, name)
    if not ok then
        error{code = error_code.NO_CHESS}
    end
    local data = game.data
    cz.start()
    if data.table then
        error{code = error_code.ALREAD_IN_CHESS}
    end
    local table = skynet.call(table_mgr, "lua", "new")
    if not table then
        error{code = error_code.INTERNAL_ERROR}
    end
    local rmsg, info = skynet.call(table, "lua", "init", name, msg.rule, data.info, skynet.self())
    if rmsg == "update_user" then
        data.table = table
    else
        skynet.call(table_mgr, "lua", "free", table)
    end
    cz.finish()
    return rmsg, info
end

function proc.join(msg)
    local table = skynet.call(table_mgr, "lua", "get", msg.number)
    if not table then
        error{code = error_code.ERROR_CHESS_NUMBER}
    end
    local data = game.data
    cz.start()
    if data.table then
        error{code = error_code.ALREAD_IN_CHESS}
    end
    local rmsg, info = skynet.call(table, "lua", "join", msg.name, data.info, skynet.self())
    if rmsg == "update_user" then
        data.table = table
    end
    cz.finish()
    return rmsg, info
end

return role
