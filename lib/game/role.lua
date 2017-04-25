local skynet = require "skynet"
local timer = require "timer"
local share = require "share"
local notify = require "notify"
local util = require "util"
local func = require "func"
local new_rand = require "random"
local cjson = require "cjson"

local pairs = pairs
local ipairs = ipairs
local assert = assert
local error = error
local string = string
local math = math
local floor = math.floor
local randomseed = math.randomseed
local random = math.random
local tonumber = tonumber

local game

local proc = {}
local role = {proc = proc}

local update_user = util.update_user
local merge_table = util.merge_table
local game_day
local error_code
local base
local cz
local role_mgr
local offline_mgr
local gm_level = tonumber(skynet.getenv("gm_level"))
local start_utc_time = tonumber(skynet.getenv("start_utc_time"))
local user_db
local info_db

skynet.init(function()
    error_code = share.error_code
    base = share.base
    cz = share.cz
    game_day = func.game_day
    role_mgr = skynet.queryservice("role_mgr")
    offline_mgr = skynet.queryservice("offline_mgr")
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
			user.nick_name = data.nickName
			user.head_img = data.headImg
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
				_id = data.id
				account = data.uid,
				id = data.id,
				sex = data.sex or math.random(2),
				login_time = 0,
				last_login_time = 0,
				logout_time = 0,
				gm_level = gm_level,
				create_time = now,
				room_card = 0,
				nick_name = data.nickName,
				head_img = data.headImg,
				ip = data.ip,
			}
			skynet.call(user_db, "lua", "save_insert", user)
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
			skynet.call(info_db, "lua", "save_insert", info)
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
    randomseed(now)
	-- you may load user data from database
	skynet.fork(get_user)
end

function role.exit()
    timer.del_routine("save_role")
    timer.del_day_routine("update_day")
    timer.del_routine("heart_beat")
    timer.del_second_routine("update_second")
    local user = game.data.user
    if user then
        skynet.call(role_mgr, "lua", "logout", user.id)
        user.logout_time = floor(skynet.time())
        role.save_user()
    end
    notify.exit()
end

local function update_day(user, od, nd)

end

function role.update_day(od, nd)

end

function role.test_update_day()

end

function role.update_second()

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

-------------------protocol process--------------------------

function proc.notify_info(msg)
    return notify.send()
end

function proc.heart_beat(msg)
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
    if user.logout_time > 0 then
        local od = game_day(user.logout_time)
        local nd = game_day(now)
        if od ~= nd then
            update_day(user, od, nd)
        end
    end
    local p = update_user()
    local ret = {user=user}
    local om = skynet.call(offline_mgr, "lua", "get", user.id)
    if om then
        for k, v in ipairs(om) do
			game.one(v[1], "add", v[2], p)
        end
    end
    for k, v in ipairs(game.module) do
        if v.pack_all then
            local key, pack = v.pack_all()
            ret[key] = pack
        end
    end
    timer.add_routine("save_role", role.save_routine, 300)
    timer.add_day_routine("update_day", role.update_day)
    timer.add_second_routine("update_second", role.update_second)
    skynet.call(role_mgr, "lua", "enter", data.info, skynet.self())
    return "info_all", {user=ret, start_time=start_utc_time}
end

function proc.chat_info(msg)
    local user = data.user
    msg.id = user.id
    msg.account = user.account
    msg.sex = user.sex
	msg.nick_name = user.nick_name
    if msg.type == base.CHAT_TYPE_WORLD then
        skynet.send(role_mgr, "lua", "broadcast", "chat_info", msg, user.id)
        return "chat_info", msg
    elseif msg.type == base.CHAT_TYPE_PRIVATE then
        local agent = skynet.call(role_mgr, "lua", "get", msg.target)
        if agent then
            skynet.send(agent, "lua", "notify", "chat_info", msg)
            return "chat_info", msg
        else
            error{code = error_code.ROLE_OFFLINE}
        end
    else
        error{code = error_code.ERROR_CHAT_TYPE}
    end
end

function proc.get_role_info(msg)
    local user = skynet.call(role_mgr, "lua", "get_user", msg.id)
    if not user then
        error{code = error_code.ROLE_NOT_EXIST}
    end
    local puser = {
        user = user,
    }
    return "role_info", {info=puser}
end

return role
