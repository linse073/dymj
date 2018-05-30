local skynet = require "skynet"
local timer = require "timer"
local share = require "share"
local notify = require "notify"
local util = require "util"
local cjson = require "cjson"
local func = require "func"
local option = require "logic.option"
local md5 = require "md5"

local pairs = pairs
local ipairs = ipairs
local assert = assert
local error = error
local string = string
local math = math
local floor = math.floor
local tonumber = tonumber
local tostring = tostring
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
local define
local game_day
local role_mgr
local offline_mgr
local club_mgr
local club_role
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
local charge_log_db
local invite_info_db
local invite_user_detail_db
local activity_mgr

local web_sign = skynet.getenv("web_sign")
local debug = (skynet.getenv("debug")=="true")

skynet.init(function()
    error_code = share.error_code
    base = share.base
    cz = share.cz
    rand = share.rand
    define = share.define
    game_day = func.game_day
    role_mgr = skynet.queryservice("role_mgr")
    offline_mgr = skynet.queryservice("offline_mgr")
    club_mgr = skynet.queryservice("club_mgr")
    club_role = skynet.queryservice("club_role")
    table_mgr = skynet.queryservice("table_mgr")
    chess_mgr = skynet.queryservice("chess_mgr")
    webclient = skynet.queryservice("webclient")

    activity_mgr = skynet.queryservice("activity_mgr")

	local master = skynet.queryservice("mongo_master")
    user_db = skynet.call(master, "lua", "get", "user")
    info_db = skynet.call(master, "lua", "get", "info")
    user_record_db = skynet.call(master, "lua", "get", "user_record")
    record_info_db = skynet.call(master, "lua", "get", "record_info")
    record_detail_db = skynet.call(master, "lua", "get", "record_detail")
    iap_log_db = skynet.call(master, "lua", "get", "iap_log")
    charge_log_db = skynet.call(master, "lua", "get", "charge_log")
    
    invite_info_db = skynet.call(master, "lua", "get", "invite_info")
    invite_user_detail_db = skynet.call(master, "lua", "get", "invite_user_detail")
end)

function role.init_module()
	game = require "game"
end

local function sort_club(l, r)
    return l.index < r.index
end

local function get_user()
	cz.start()
	local data = game.data
    if not data.user then
        if not data.sex or data.sex == 0 then
            data.sex = rand.randi(1, 2)
        end
        local id = data.id
		local user = skynet.call(user_db, "lua", "findOne", {id=id})
		if user then
			user.nick_name = data.nick_name
			user.head_img = data.head_img
			user.ip = data.ip
            user.sex = data.sex
            user.openid = data.openid
            user.unionid = data.unionid
			data.user = user
			data.info = {
				account = user.account,
				id = id,
				sex = user.sex,
				nick_name = user.nick_name,
				head_img = user.head_img,
                openid = user.openid,
                unionid = user.unionid,
				ip = user.ip,
			}
            data.offline = skynet.call(offline_mgr, "lua", "get", id)
            local rc = skynet.call(club_role, "lua", "get", id)
            if rc then
                local id_club = {}
                local club_info = {}
                local club_found = 0
                for k, v in pairs(rc) do
                    local ci = skynet.call(v, "lua", "login", id)
                    if ci then
                        ci.index = base.MAX_CLUB
                        id_club[ci.id] = ci
                        club_info[#club_info+1] = ci
                        if ci.pos == base.CLUB_POS_CHIEF then
                            club_found = club_found + 1
                        end
                    end
                end
                for k, v in ipairs(user.club) do
                    local ci = id_club[v]
                    if ci then
                        ci.index = k
                    end
                end
                table.sort(club_info, sort_club)
                local club = {}
                for k, v in ipairs(club_info) do
                    v.index = k
                    club[k] = v.id
                end
                user.club = club
                data.club_info = club_info
                data.id_club = id_club
                data.club_found = club_found
            else
                user.club = {}
                data.club_info = {}
                data.id_club = {}
                data.club_found = 0
            end
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
				room_card = define.init_card,
				nick_name = data.nick_name,
				head_img = data.head_img,
                openid = data.openid,
                unionid = data.unionid,
				ip = data.ip,
                day_card = false,
                invite_code = 0,
                first_charge = {},
                club = {},
			}
			skynet.call(user_db, "lua", "safe_insert", user)
			data.user = user
			local info = {
				account = user.account,
				id = user.id,
				sex = user.sex,
				nick_name = user.nick_name,
				head_img = user.head_img,
                openid = user.openid,
                unionid = user.unionid,
				ip = user.ip,
			}
			skynet.call(info_db, "lua", "safe_insert", info)
            data.info = info
            data.club_info = {}
            data.id_club = {}
            data.club_found = 0
            
            skynet.send(activity_mgr, "lua", "reg_invite_user", info)
		end
    end
	cz.finish()
end

function role.init()
	local data = game.data
    data.heart_beat = 0
    timer.add_routine("heart_beat", role.heart_beat, 86400)
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
    notify.add("update_day", "")
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
    local id = data.id
    if chess_table then
        skynet.call(chess_table, "lua", "status", id, base.USER_STATUS_LOST)
    end
    for k, v in ipairs(data.club_info) do
        skynet.call(v.addr, "lua", "online", id, false)
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
    cz.start()
    local data = game.data
    data.ip = addr
    data.user.ip = addr
    data.info.ip = addr
    if data.enter then
        -- skynet.fork(btk, addr)
        btk(addr)
    end
    local id = data.id
    for k, v in ipairs(data.club_info) do
        skynet.call(v.addr, "lua", "online", id, true)
    end
    cz.finish()
end

function role.repair(user, now)
    if user.day_card == nil then
        user.day_card = false
    end
    if not user.invite_code then
        user.invite_code = 0
    end
    if not user.first_charge then
        user.first_charge = {}
    end
    if not user.club then
        user.club = {}
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

function role.unlink(p, inform)
    local user = game.data.user
    if user.invite_code > 0 then
        user.invite_code = 0
        p.user.invite_code = 0
        if inform then
            notify.add("update_user", {update=p})
        end
    end
end

function role.charge(p, inform, ret)
    if ret.retCode == "SUCCESS" then
        local trade_id = tonumber(ret.tradeNO)
        local r = skynet.call(charge_log_db, "lua", "findAndModify", 
            {query={id=trade_id, status=false}, update={["$set"]={status=true}}})
        if r.lastErrorObject.updatedExisting then
            local cashFee = r.value.num
            local user = game.data.user
            local num
            if user.invite_code > 0 then
                num = define.shop_item_2[cashFee]
                local first_charge = user.first_charge
                local feeStr = tostring(cashFee)
                if not first_charge[feeStr] then
                    first_charge[feeStr] = true
                    p.first_charge = {cashFee}
                    if cashFee == 600 then
                        num = num * 2
                    end
                end
            else
                num = define.shop_item[cashFee]
            end
            role.add_room_card(p, inform, num)
        else
            skynet.error(string.format("No unfinished trade: %d.", trade_id))
        end
    else
        skynet.error(string.format("Trade %s fail: %s.", ret.tradeNO, ret.retMsg))
    end
end

function role.bind_gzh(inform,ret)
    if inform and ret then
        notify.add("update_gzh", {bind_gzh=true})
    end
end

function role.leave()
    cz.start()
    local data = game.data
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

local function syn_info(now)
    local data = game.data
    local user = data.user
    local str = table.concat({
        user.id, 
        data.unionid or "", 
        data.openid or "", 
        data.nick_name or "", 
        data.head_img or "", 
        now, 
        web_sign
    }, "&")
    local sign = md5.sumhexa(str)
    local result, content = skynet.call(webclient, "lua", "request", define.syn_user_url, {
        id = user.id, 
        unionid = data.unionid, 
        openid = data.openid, 
        nickname = data.nick_name, 
        headimgurl = data.head_img, 
        time = now, 
        sign = sign,
    })
    if not result or content.ret ~= "OK" then
        skynet.error(string.format("synchronize user info %d fail.", user.id))
    end
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
    local om = data.offline
    if om then
        local p = update_user()
        for k, v in ipairs(om) do
            table.insert(v, 3, p)
            game.one(table.unpack(v))
        end
        data.offline = nil
    end
    local pack = game.iter_ret("pack_all")
    for _, v in ipairs(pack) do
        ret[v[1]] = v[2]
    end
    local first_charge = {}
    -- NOTICE: the type of mongo map key is string
    for k, v in pairs(user.first_charge) do
        first_charge[#first_charge+1] = tonumber(k)
    end
    ret.first_charge = first_charge
    ret.club = data.club_info
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
    if data.login_type == base.LOGIN_WEIXIN and not debug then
        skynet.fork(syn_info, now)
    end
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
    cz.start()
    local data = game.data
    if data.chess_table then
        error{code = error_code.ALREAD_IN_CHESS}
    end
    local rule = config(msg.rule)
    local user = data.user
    if msg.club then
        local c = data.id_club[msg.club]
        if not c then
            error{code = error_code.NOT_IN_CLUB}
        end
        local rc = skynet.call(c.addr, "lua", "get_room_card")
        if not rc then
            error{code = error_code.NO_CLUB}
        end
        if rc < rule.total_card then
            error{code = error_code.CLUB_ROOM_CARD_LIMIT}
        end
        local cr = skynet.call(c.addr, "lua", "check_role_day_card", data.id)
        if cr == nil then
            error{code = error_code.NOT_IN_CLUB}
        end
        if not cr then
            error{code = error_code.CLUB_DAY_CARD_LIMIT}
        end
    else
        if rule.aa_pay then
            if user.room_card < rule.single_card then
                error{code = error_code.ROOM_CARD_LIMIT}
            end
        else
            if user.room_card < rule.total_card then
                error{code = error_code.ROOM_CARD_LIMIT}
            end
        end
    end
    assert(not skynet.call(chess_mgr, "lua", "get", data.id), string.format("Chess mgr has %d.", data.id))
    local chess_table = skynet.call(table_mgr, "lua", "new")
    if not chess_table then
        error{code = error_code.INTERNAL_ERROR}
    end
    local card = data[msg.name .. "_card"]
    local rmsg, info = skynet.call(chess_table, "lua", "init", 
        msg.name, rule, data.info, skynet.self(), data.server_address, card, msg.location, msg.club)
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
    cz.start()
    local data = game.data
    if data.chess_table then
        error{code = error_code.ALREAD_IN_CHESS}
    end
    assert(not skynet.call(chess_mgr, "lua", "get", data.id), string.format("Chess mgr has %d.", data.id))
    local user = data.user
    local rmsg, info = skynet.call(chess_table, "lua", "join", data.info, user.room_card, skynet.self(), msg.location)
    if rmsg == "update_user" then
        data.chess_table = chess_table
    end
    cz.finish()
    return rmsg, info
end

function proc.get_record(msg)
    local data = game.data
    local ur = skynet.call(user_record_db, "lua", "findOne", {id=data.id}, {record=true})
    local ret = {}
    if ur then
        local nr = {}
        local record = ur.record
        if record then
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
                if count == 0 then
                    skynet.call(user_record_db, "lua", "update", {id=data.id}, {["$unset"]={record=true}}, true)
                else
                    skynet.call(user_record_db, "lua", "update", {id=data.id}, {["$set"]={record=nr}}, true)
                end
            end
        end
    end
    return "record_all", {record=ret}
end

function proc.get_club_user_record(msg)
    local data = game.data
    local club = data.id_club[msg.id]
    if not club then
        error{code = error_code.NOT_IN_CLUB}
    end
    local ur = skynet.call(user_record_db, "lua", "findOne", {id=data.id}, {club_record=true})
    local ret = {}
    if ur then
        local nr = {}
        local record = ur.club_record
        if record then
            local len = #record
            local count = 0
            for i = len, 1, -1 do
                local v = record[i]
                local ri = skynet.call(record_info_db, "lua", "findOne", {id=v, clubid=msg.id})
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
                if count == 0 then
                    skynet.call(user_record_db, "lua", "update", {id=data.id}, {["$unset"]={club_record=true}}, true)
                else
                    skynet.call(user_record_db, "lua", "update", {id=data.id}, {["$set"]={club_record=nr}}, true)
                end
            end
        end
    end
    return "club_user_record", {id=msg.id, record=ret}
end

function proc.get_club_record(msg)
    if not msg.begin_time or not msg.end_time then
        error{code = error_code.ERROR_ARGS}
    end
    local data = game.data
    local club = data.id_club[msg.id]
    if not club then
        error{code = error_code.NOT_IN_CLUB}
    end
    if club.pos ~= base.CLUB_POS_CHIEF then
        error{code = error_code.CLUB_PERMIT_LIMIT}
    end
    local ret = {}
    util.mongo_find(record_info_db, function(r)
        ret[#ret+1] = r
    end, {clubid=msg.id, time={["$gte"]=msg.begin_time, ["$lte"]=msg.end_time}})
    return "club_record", {id=msg.id, record=ret}
end

function proc.read_club_record(msg)
    if not msg.id or msg.read == nil then
        error{code = error_code.ERROR_ARGS}
    end
    local ri = skynet.call(record_info_db, "lua", "findOne", {id=msg.id}, {clubid=true, read=true})
    if not ri then
        error{code = error_code.NO_RECORD}
    end
    if not ri.clubid then
        error{code = error_code.NO_RECORD}
    end
    local data = game.data
    local club = data.id_club[ri.clubid]
    if not club then
        error{code = error_code.NOT_IN_CLUB}
    end
    if club.pos ~= base.CLUB_POS_CHIEF then
        error{code = error_code.CLUB_PERMIT_LIMIT}
    end
    if ri.read ~= msg.read then
        ri.read = msg.read
        skynet.call(record_info_db, "lua", "update", {id=msg.id}, {["$set"]={read=msg.read}})
    end
    return "response", ""
end

function proc.check_agent(msg)
    local data = game.data
    if data.unionid then
        local now = floor(skynet.time())
        local str = table.concat({data.id, data.unionid, now, web_sign}, "&")
        local sign = md5.sumhexa(str)
        local result, content = skynet.call(webclient, "lua", "request", 
            define.agent_url, {id=data.id, unionid=data.unionid, time=now, sign=sign})
        if not result then
            error{code = error_code.INTERNAL_ERROR}
        end
        local content = cjson.decode(content)
        if content.ret ~= "OK" then
            error{code = error_code.INVITE_CODE_ERROR}
        end
        return "check_agent_ret", {agent=content.is_agent}
    else
        return "check_agent_ret", {agent=true}
    end
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
    if not result then
        error{code = error_code.INTERNAL_ERROR}
    end
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
            role.add_room_card(p, false, assert(define.shop_item[tonumber(num)*100]))
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
    role.add_room_card(p, false, define.share_reward)
    user.day_card = true
    p.user.day_card = true
    return "update_user", {update=p}
end

function proc.invite_code(msg)
    local code = msg.code
    if not code or not msg.url then
        error{code = error_code.ERROR_ARGS}
    end
    local user = game.data.user
    if user.invite_code > 0 then
        error{code = error_code.HAS_INVITE_CODE}
    end
    local now = floor(skynet.time())
    local str = table.concat({user.id, code, now, web_sign}, "&")
    local sign = md5.sumhexa(str)
    local result, content = skynet.call(webclient, "lua", "request", 
        msg.url, {id=user.id, invite=code, time=now, sign=sign})
    if not result then
        error{code = error_code.INTERNAL_ERROR}
    end
    local content = cjson.decode(content)
    if content.ret == "OK" then
        local p = update_user()
        role.add_room_card(p, false, define.invite_reward)
        user.invite_code = code
        p.user.invite_code = code
        return "update_user", {update=p}
    else
        error{code = error_code.INVITE_CODE_ERROR}
    end
end

function proc.charge(msg)
    local num = msg.num
    if not num or not msg.url then
        error{code = error_code.ERROR_ARGS}
    end
    if not define.shop_item[num] then
        error{code = error_code.NO_SHOP_ITEM}
    end
    local data = game.data
    local user = data.user
    local now = floor(skynet.time())
    local trade_id = skynet.call(data.server_address, "lua", "gen_charge")
    local invite_code = user.invite_code
    local trade = {
        id = trade_id,
        user = user.id,
        invite_code = invite_code,
        num = num,
        time = now,
        status = false,
    }
    skynet.call(charge_log_db, "lua", "safe_insert", trade)
    local str = table.concat({user.id, invite_code, trade_id, num, now, web_sign}, "&")
    local sign = md5.sumhexa(str)
    local query = {
        id = user.id,
        invite = invite_code,
        tradeNO = trade_id,
        cashFee = num,
        time = now,
        sign = sign,
    }
    local url = msg.url .. "?" .. util.url_query(query)
    return "charge_ret", {url=url}
end

function proc.reward_award(msg)
    local data = game.data
    local p = update_user()
    if ((not msg) or msg.diamond_award<=0) then
        skynet.error(string.format("user %d has invalidate request parms to reward_award.", data.id))
    end

    local invite_info = skynet.call(activity_mgr, "lua", "get_invite_info", proc.getActivityParamUser(data))
    local num = invite_info.award_diamond
    if num and num>0 then
        invite_info.award_diamond = 0
        skynet.call(invite_info_db, "lua", "update", {id=data.id}, {["$inc"]={award_diamond=num*-1}}, false)
        -- skynet.call(invite_info_db, "lua", "findAndModify", 
        --     {query={_id=invite_info._id}, update={["$int"]={award_diamond=num*-1}}})       

        --添加用户砖石
        local user = game.data.user
        user.room_card = user.room_card + num
        p.user.room_card = user.room_card
    else
        skynet.error(string.format("user %d has no diamond to reward_award.", data.id))
    end
    
    return "update_user", {update=p}
end


function proc.invite_share(msg)
    -- invite_user_detail_db = skynet.call(master, "lua", "get", "invite_user_detail")
    -- invite_info_db = skynet.call(master, "lua", "get", "invite_info")        
    local data = game.data
    local invite_info = skynet.call(activity_mgr, "lua", "get_invite_info", proc.getActivityParamUser(data))
    local p = update_user()

    if (invite_info.share_done_times and invite_info.share_done_times>define.activity_maxtrix.share2invite_max) then
        skynet.error(string.format("user %d had finished share activity of inviting.", data.id))
    else
        if  not func.is_today(invite_info.share_done_date) then -- 今天第一次,
            invite_info.share_done_times = invite_info.share_done_times+1
            invite_info.share_done_date = floor(skynet.time())

            local user = game.data.user
            local count_per_share=define.activity_maxtrix.diamond[invite_info.share_done_times] or 0 --分享一次加n砖石
            user.room_card = user.room_card + count_per_share --
            p.user.room_card = user.room_card

            skynet.call(invite_info_db, "lua", "update", {id=data.id},
                {["$set"]={share_done_times=invite_info.share_done_times,share_done_date=invite_info.share_done_date}}, false)

            -- skynet.call(invite_info_db, "lua", "findAndModify", 
            --     {query={_id=invite_info._id}, update={["$set"]={share_done_times=invite_info.share_done_times,share_done_date=invite_info.share_done_date}}})

        end
    end

    return "update_user", {update=p}
end

function proc.invite_assemble(invite_info)
    local info = {done_times=0,curr_times=1}
    if invite_info then
        local done_times = (invite_info.share_done_times or 0)
        local curr_times = done_times
        if (done_times<define.activity_maxtrix.share2invite_max) then
            if not func.is_today(invite_info.share_done_date) then
                --最近的邀请时间非今天
                curr_times = curr_times +1
            end
        end
        info = {
            done_times=done_times,
            curr_times=curr_times,
            award_diamond=invite_info.award_diamond,
            reward_off=invite_info.reward_off,
        }
    end
    return info
end

function proc.invite_query(msg)
    local data = game.data
    local invite_info = skynet.call(activity_mgr, "lua", "get_invite_info", proc.getActivityParamUser(data))
    local info = proc.invite_assemble(invite_info)
    info.record_detail = proc.my_invite_user_detail_query()
    return "invite_info", info
end

function proc.my_invite_user_detail_query()
    local data = game.data
    local result = {}
    -- local cursor = skynet.call(user_db, "lua", "find", nil,{"id"})
    -- local i =0
    -- while cursor:hasNext() do
    --     i = i+1
    --     if (i>25) then break end
    --     local r = cursor:next()
    --     result[#result+1] = {name=r.nick_name or r.id,play_count=r.play_total_count or 0, invite_time=r.invited_date}
    -- end

    util.mongo_find(invite_user_detail_db, function(r)
        -- cs(add, r.id, module, func, ...)
        result[#result+1]={name=r.nick_name or r.id,play_count=r.play_total_count or 0, invite_time=r.invited_date}
    end, {belong_id=data.id}, {_id=false})   

    -- local r = skynet.call(invite_user_detail_db, "lua", "findOne", {belong_id=data.id})
    -- result[1]={name=r.nick_name or r.id,play_count=r.play_total_count or 0, invite_time=r.invited_date}

    return result
end

function proc.invite_money_query(msg)  --邀请红包查询
    local data = game.data
    local invite_info = skynet.call(activity_mgr, "lua", "get_invite_info", proc.getActivityParamUser(data))
    
    local info = {mine_done=invite_info.mine_done,
            invite_count = invite_info.invite_count,
            pay_total = invite_info.pay_total,
            reward_off=invite_info.reward_off,bind_gzh=invite_info.bind_gzh}

    local detail_info = skynet.call(activity_mgr,"lua","get_invite_user_detail",data.id)
    if (detail_info) then
        info.mine_play = detail_info.play_total_count or 0
    end

    local reward_invite_r = {}
    local reward_pay_r = {}

    if invite_info.reward_invite_r then
        for k,v in pairs(define.activity_maxtrix.money_invite) do
            local status = invite_info.reward_invite_r[k .. ""]
            if (status) then
                reward_invite_r[#reward_invite_r+1] = {index=k,status=status}
            end 
        end
    end

    if invite_info.reward_pay_r then
        for k,v in pairs(define.activity_maxtrix.money_pay) do
            local status = invite_info.reward_pay_r[k .. ""]
            if (status) then
                reward_pay_r[#reward_pay_r+1] = {index=k,status=status}
            end
        end
    end
    
    info.reward_invite_r = reward_invite_r
    info.reward_pay_r = reward_pay_r

    local detail_info = skynet.call(invite_user_detail_db, "lua", "findOne", {id=data.id})
    if (detail_info) then
        info.mine_play =  detail_info.play_total_count or 0
    end

    return "invite_info", info
end

function proc.reward_money(msg)
    if (msg) then
        local data = game.data
        skynet.call(activity_mgr, "lua", "reward_money", proc.getActivityParamUser(data), msg)
    end
    return proc.invite_money_query()
end

function proc.getActivityParamUser(data)
    return {id=data.info.id,account=data.info.account,unionid=data.user.unionid,create_time=data.user.create_time}
end

function proc.roulette_query(msg)
    local data = game.data
    local invite_info = skynet.call(activity_mgr, "lua", "get_invite_info", proc.getActivityParamUser(data))

    local info ={roulette_cur=invite_info.roulette_cur,roulette_total=invite_info.roulette_total,bind_gzh=invite_info.bind_gzh,
        reward_off=invite_info.reward_off}
    local roulette_r = {}

    if (invite_info.roulette_r) then
        for k,v in pairs(define.activity_maxtrix.roulette.conditions) do
            local status = invite_info.roulette_r[k .. ""]
            if (status) then
                roulette_r[#roulette_r+1] = {index=k,status=status}
            end
        end            
    end    

    info.roulette_r = roulette_r

    return "invite_info", info
end

function proc.roulette_reward(msg)
    local p = update_user()
    local roulette_index = -1
    if (msg) then
        local data = game.data
        local prize = skynet.call(activity_mgr, "lua", "roulette_reward", proc.getActivityParamUser(data), msg)
        if prize then
            roulette_index = prize.idx
            if ( prize.t == "d") then
                local user = game.data.user
                user.room_card = user.room_card + prize.v --随机砖石
                p.user.room_card = user.room_card
            end
        end
    end
    return "update_user", {update=p,roulette_index=roulette_index}
end

return role
