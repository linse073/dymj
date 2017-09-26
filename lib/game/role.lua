local skynet = require "skynet"
local timer = require "timer"
local share = require "share"
local notify = require "notify"
local util = require "util"
local cjson = require "cjson"
local func = require "func"
local option = require "logic.option"

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
local game_day
local role_mgr
local offline_mgr
local table_mgr
local chess_mgr
local webclient
local gm_level = tonumber(skynet.getenv("gm_level"))
local start_utc_time = tonumber(skynet.getenv("start_utc_time"))
local user_db
local info_db
local user_record_db
local record_info_db
local record_detail_db
local iap_log_db

skynet.init(function()
    error_code = share.error_code
    base = share.base
    cz = share.cz
    rand = share.rand
    game_day = func.game_day
    role_mgr = skynet.queryservice("role_mgr")
    offline_mgr = skynet.queryservice("offline_mgr")
    table_mgr = skynet.queryservice("table_mgr")
    chess_mgr = skynet.queryservice("chess_mgr")
    webclient = skynet.queryservice("webclient")
	local master = skynet.queryservice("mongo_master")
    user_db = skynet.call(master, "lua", "get", "user")
    info_db = skynet.call(master, "lua", "get", "info")
    user_record_db = skynet.call(master, "lua", "get", "user_record")
    record_info_db = skynet.call(master, "lua", "get", "record_info")
    record_detail_db = skynet.call(master, "lua", "get", "record_detail")
    iap_log_db = skynet.call(master, "lua", "get", "iap_log")
end)

function role.init_module()
	game = require "game"
end

local function get_user()
	cz.start()
	local data = game.data
    if not data.user then
        if not data.sex or data.sex == 0 then
            data.sex = rand.randi(1, 2)
        end
		local user = skynet.call(user_db, "lua", "findOne", {id=data.id})
		if user then
			user.nick_name = data.nick_name
			user.head_img = data.head_img
			user.ip = data.ip
            user.sex = data.sex
			data.user = user
			data.info = {
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
				account = data.uid,
				id = data.id,
				sex = data.sex,
				login_time = 0,
				last_login_time = 0,
				logout_time = 0,
				gm_level = gm_level,
				create_time = now,
				room_card = 30,
				nick_name = data.nick_name,
				head_img = data.head_img,
				ip = data.ip,
                day_card = false,
			}
			skynet.call(user_db, "lua", "safe_insert", user)
			data.user = user
			local info = {
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
    timer.del_day_routine("update_day")
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

local function update_day(user, od, nd)
    user.day_card = false
end

function role.update_day(od, nd)
    local user = game.data.user
    update_day(user, od, nd)
    notify.add("update_day", {})
end

function role.test_update_day()
    local user = game.data.user
    local now = floor(skynet.time())
    local nd = game_day(now)
    update_user(user, nd, nd)
    return "update_day", ""
end

function role.save_user()
    local data = game.data
    local id = data.id
    skynet.call(user_db, "lua", "update", {id=id}, data.user, true)
    skynet.call(info_db, "lua", "update", {id=id}, data.info, true)
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

local function btk(addr)
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
        skynet.fork(btk, addr)
    end
end

function role.repair(user, now)
    if user.day_card == nil then
        user.day_card = false
    end
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
    if user.logout_time > 0 then
        local od = game_day(user.logout_time)
        local nd = game_day(now)
        if od ~= nd then
            update_day(user, od, nd)
        end
    end
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
    local code
    if chess_table then
        data.chess_table = chess_table
        ret.chess = skynet.call(chess_table, "lua", "pack", user.id, user.ip, skynet.self())
    elseif msg.number then
        chess_table = skynet.call(table_mgr, "lua", "get", msg.number)
        if chess_table then
            local rmsg, info = skynet.call(chess_table, "lua", "join", data.info, user.room_card, skynet.self())
            if rmsg == "update_user" then
                data.chess_table = chess_table
                ret.chess = info.update.chess
            elseif rmsg == "error_code" then
                code = info.code
            end
        else
            code = error_code.ROOM_CLOSE
        end
    end
    timer.add_routine("save_role", role.save_routine, 300)
    timer.add_day_routine("update_day", role.update_day)
    skynet.call(role_mgr, "lua", "enter", data.info, skynet.self())
    data.enter = true
    cz.finish()
    return "info_all", {user=ret, start_time=start_utc_time, code=code}
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
    local config = option[msg.name]
    if not config then
        error{code = error_code.NO_CHESS}
    end
    local data = game.data
    cz.start()
    if data.chess_table then
        error{code = error_code.ALREAD_IN_CHESS}
    end
    local rule = config(msg.rule)
    local user = data.user
    if rule.aa_pay then
        if user.room_card < rule.single_card then
            error{code = error_code.ROOM_CARD_LIMIT}
        end
    else
        if user.room_card < rule.total_card then
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
    local rmsg, info = skynet.call(chess_table, "lua", "join", data.info, user.room_card, skynet.self())
    if rmsg == "update_user" then
        data.chess_table = chess_table
    end
    cz.finish()
    return rmsg, info
end

function proc.get_record(msg)
    local data = game.data
    local ur = skynet.call(user_record_db, "lua", "findOne", {id=data.id})
    local ret = {}
    if ur then
        local nr = {}
        local record = ur.record
        local len = #record
        local count = 0
        for i = len, 1, -1 do
            local v = record[i]
            local ri = skynet.call(record_info_db, "lua", "findOne", {id=v})
            if ri then
                count = count + 1
                ret[count] = ri
                nr[count] = v
                if count >= 12 then
                    break
                end
            end
        end
        if count ~= len then
            util.reverse(nr)
            skynet.call(user_record_db, "lua", "update", {id=data.id}, {["$set"]={record=nr}}, true)
        end
    end
    return "record_all", {record=ret}
end

function proc.review_record(msg)
    if not msg.id then
        error{code = error_code.ERROR_ARGS}
    end
    local rd = skynet.call(record_detail_db, "lua", "findOne", {id=msg.id})
    if not rd then
        error{code = error_code.NO_RECORD}
    end
    return "record_info", rd
end

function proc.iap(msg)
    if not msg.receipt then
        error{code = error_code.ERROR_ARGS}
    end
    local url
    if msg.sandbox then
        url = "https://sandbox.itunes.apple.com/verifyReceipt"
    else
        url = "https://buy.itunes.apple.com/verifyReceipt"
    end
    local result, content = skynet.call(webclient, "lua", "request", url, nil, msg.receipt, 
        false, "Content-Type: application/json")
    local content = cjson.decode(content)
    if content.status == 0 then
        local receipt = content.receipt
        cz.start()
        local has = skynet.call(iap_log_db, "lua", "findOne", {transaction_id=receipt.transaction_id})
        if not has then
            skynet.call(iap_log_db, "lua", "safe_insert", receipt)
        end
        cz.finish()
        if has then
            return "update_user", {iap_index=msg.index}
        else
            local num = string.match(receipt.product_id, "store_(%d+)")
            local p = update_user()
            role.add_room_card(p, false, tonumber(num))
            return "update_user", {update=p, iap_index=msg.index}
        end
    else
        error{code = error_code.IAP_FAIL}
    end
end

function proc.share(msg)
    local user = game.data.user
    if user.day_card then
        error{code = error_code.ALREADY_SHARE}
    end
    local p = update_user()
    role.add_room_card(p, false, 4)
    user.day_card = true
    p.user.day_card = true
    return "update_user", {update=p}
end

return role
