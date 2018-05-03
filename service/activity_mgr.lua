local skynet = require "skynet"
local util = require "util"
local cjson = require "cjson"
local md5 = require "md5"

local sharedata = require "skynet.sharedata"
local random = require "random"

local ipairs = ipairs
local assert = assert
local tonumber = tonumber
local error = error
local floor = math.floor

local user_db
-- local update_user = util.update_user

local invite_info_db
local invite_user_detail_db
local role_mgr

local base
local define
local error_code
local rand

local webclient
local web_sign = skynet.getenv("web_sign")

local CMD = {}

local approval_type_roulette= "roulette_reward"  -- 抽奖现金审批类型

local function is_today(datetime)
    if not datetime then
        return false
    end
    local now = os.date("*t")
    local diff = datetime-os.time({year=now.year,month=now.month,day=now.day,hour=0})
    -- return diff >= 0 and diff<24*60*60
    return diff >=0 and diff < 86400 
end

local function is_activity_my_play_expired(datetime)
    if not datetime then return true end
    local diff =  os.time() - datetime
    return diff>(define.activity_maxtrix.limit_hour*3600)
end

local function roulette_calculate(id, roulette_idx) --抽奖计算 id,条件conditions索引
    if (id) then
        local invite_info = CMD.get_invite_info({id=id})
        local count = 0
        if (invite_info.roulette_r) then
            count = invite_info.roulette_r[roulette_idx .. ""] or 0
        end
        local max = define.activity_maxtrix.roulette.conditions[roulette_idx]
        if (count<max) then
            local field = "roulette_r." .. roulette_idx
            if count == (max-1) then --抽奖数也加一
                skynet.call(invite_info_db, "lua", "update", {id=id}, {["$inc"]={roulette_cur=1,[field]=1},["$set"]={roulette_date=os.time()}}, false)
            else
                skynet.call(invite_info_db, "lua", "update", {id=id}, {["$inc"]={[field]=1},["$set"]={roulette_date=os.time()}}, false)
            end
        end
    end    
end

local function probabilityRandom(probability)
    local randMax = 10000
    local rand = rand.randi(1, randMax)
    local idx = 0
    for i=#probability-1,1,-1 do 
        if (probability[i]<rand) then
            idx = i
            break
        end
    end
    return idx+1    
end

-- uid,unionid 用户id,unionid
-- type, 正常情况下为审核通过后，更新的mongo字段
-- fee_fen 红包,单位为分
local function approval_money(uid,unionid,type,fee_fen)
     -- client invoke by unionid
    -- TOTEST TOFIX
    -- unionid = "wiwuek"

    if unionid then
        local now = floor(skynet.time())
        local str = table.concat(
            {
                define.intercommunion.sys_id,
                uid,
                unionid,
                type,
                fee_fen, 
                now, 
                web_sign
            }, "&")
        local sign = md5.sumhexa(str)
        local result, content = skynet.call(webclient, "lua", "request", define.intercommunion.activity_approval_url, 
            {
                gid=define.intercommunion.sys_id,
                id=uid,
                unionid=unionid,
                tf = type,
                fee = fee_fen,
                time=now, 
                sign=sign
            }
        )
        if not result then
            -- error{code = error_code.INTERNAL_ERROR}
            skynet.error(string.format("approval money user [%d]  %s %s.",uid, type,result))
        else
            -- local ret,content = pcall(cjson.decode,content)
            content = cjson.decode(content)
            -- if (ret) then
                if content.ret == "OK" then
                    if type ~= approval_type_roulette then --非抽奖
                        skynet.call(invite_info_db, "lua", "update", {id=uid}, {["$set"]={[type]=base.ACTIVITY_STATUS.PROGRESSING}}, false)
                    end
                else
                    -- error{code = error_code.INTERNAL_ERROR}
                    skynet.error(string.format("approval money user [%d] %s  %s.",uid, type,content.error))
                    error{code = error_code.INTERNAL_ERROR}
                end
            -- else
            --     error{code = error_code.INTERNAL_ERROR}             
            -- end
        end
    end
end

function CMD.get_invite_info(info) ---- 返回非空对象
    local invite_info = skynet.call(invite_info_db, "lua", "findOne", {id=info.id})
    if not invite_info then
        invite_info = {
            account = info.account,
            id = info.id,  --
            --bind_gzh, 是否已经绑定红包公众号
            award_diamond = 0, --邀请好友成功的待领取钻石数
            share_done_times = 0, --分享完成数
            -- share_done_date = floor(os.time()), --分享完成时间
            
            mine_done=nil, -- 个人完成领取红包状态  base.ACTIVITY_STATUS
            reward_off=false, --领取红包是否关闭
            invite_count=0, -- 邀请成功人数
            pay_total=0,--邀请人支付总额
            reward_invite_r={}, --领取邀请红包记录[value]=status patterm :{[1]="d",[4]="N"}
            reward_pay_r={}, --领取支付红包记录[value]=status

            roulette_cur=0,--当日抽奖数
            roulette_total=0,--总的已抽象数
            roulette_r={}, -- 抽奖条件记录[index]=value patterm:[[1]=8,[2]=10,[3]=6]
            -- roulette_date=nil,--抽奖日期
        }
        skynet.call(invite_info_db, "lua", "safe_insert", invite_info)
    end

    if (not invite_info.mine_done) 
        or invite_info.mine_done ~= base.ACTIVITY_STATUS.MISS 
        or invite_info.mine_done == base.ACTIVITY_STATUS.UNDO then -- judge  expired or not
        if info.create_time and is_activity_my_play_expired(info.create_time) then
            invite_info.mine_done=base.ACTIVITY_STATUS.MISS
            skynet.call(invite_info_db, "lua", "update", {id=info.id},
                {["$set"]={mine_done=base.ACTIVITY_STATUS.MISS}}, false)            
        end
    end 

    if not is_today(invite_info.roulette_date) then -- 转盘抽奖时间非今天，清零
        if invite_info.roulette_cur>0 or invite_info.roulette_r~=nil then
            invite_info.roulette_cur =0
            invite_info.roulette_r = nil
            skynet.call(invite_info_db, "lua", "update", {id=info.id},
                {["$unset"]={roulette_r=1},["$set"]={roulette_cur=0,roulette_date=os.time()}}, false)
        end
    end    
    

    
    local reward_off = skynet.call(invite_info_db, "lua", "findOne", {id=-1})
    if (reward_off) then
        invite_info.reward_off = reward_off.off
    end

    return invite_info
end

function CMD.roulette_reward(info,msg)
    local invite_info = CMD.get_invite_info(info)
    if invite_info.roulette_cur>0 then 
        
        local probability = nil
        if invite_info.roulette_total==0 then
            probability = define.activity_maxtrix.roulette.probability_1
        else
            probability = define.activity_maxtrix.roulette.probability_2
        end
        local idx = probabilityRandom(probability)

        -- skynet.error(string.format("the %d prize is roulette", idx))

        local prize = define.activity_maxtrix.roulette.prize[idx]
        local p = {t=prize.t, v= prize.v,idx=idx}
        if p.t== "m" then
            -- cash client
            approval_money(info.id,info.unionid,approval_type_roulette,prize.v)
        else

        end

        skynet.call(invite_info_db, "lua", "update", {id=info.id}, {["$inc"]={roulette_cur=-1,roulette_total=1},["$set"]={roulette_date=os.time()}}, false)

        return p
    end
end

function CMD.reward_money(info, msg)
    local invite_info = CMD.get_invite_info(info)

    local detail_info = skynet.call(invite_user_detail_db, "lua", "findOne", {id=info.id})
    local mine_play = 0
    if (detail_info) then
        mine_play =  detail_info.play_total_count or 0
    end  

    local award_type = msg.award_type or ""
    local award_idx = msg.award_idx or 0
    local award_num = msg.award_num or 0
    
    local yuan = 0
    local type = nil 
    if (award_type == "play_done") then --个人领取
        if (not invite_info.mine_done)
            or mine_done == base.ACTIVITY_STATUS.UNDO then

            if mine_play>= define.activity_maxtrix.done_count then 
                -- skynet.call(invite_info_db, "lua", "update", {id=info.id}, {["$set"]={mine_done=base.ACTIVITY_STATUS.PROGRESSING}}, false)
                --随机红包
                local idx = probabilityRandom(define.activity_maxtrix.play_probability)
                -- skynet.error(string.format("the %d prize is roulette", idx))
                yuan = define.activity_maxtrix.play_prize[idx]
                type = "mine_done"          
            end
        end
    elseif award_type == "money_invite" then
        local status = nil
        if invite_info.reward_invite_r then
            status = invite_info.reward_invite_r[award_num .. ""]
        end
        if  (not status) or status==base.ACTIVITY_STATUS.UNDO then
            if award_num<=invite_info.invite_count and mine_play>= define.activity_maxtrix.done_count*award_num then                
                local field = "reward_invite_r." .. award_num
                type = field
                -- skynet.call(invite_info_db, "lua", "update", {id=info.id}, {["$set"]={[field]=base.ACTIVITY_STATUS.PROGRESSING}}, false)
                yuan = define.activity_maxtrix.money_invite[award_num]            
            end
        end 
    elseif award_type == "money_pay" then
        local status = nil
        if invite_info.reward_pay_r then
            status = invite_info.reward_pay_r[award_num .. ""]

        end
        if  (not status) or status==base.ACTIVITY_STATUS.UNDO then
            if (award_num<=invite_info.pay_total) then
                local field = "reward_pay_r." .. award_num
                type = field
                -- skynet.call(invite_info_db, "lua", "update", {id=info.id}, {["$set"]={[field]=base.ACTIVITY_STATUS.PROGRESSING}}, false)
                yuan = define.activity_maxtrix.money_pay[award_num]                    
            end
        end        

    end

    --- 请求client 
    if (yuan>0 and type) then
        approval_money(info.id,info.unionid,type,yuan * 100)
    end
end

function CMD.get_invite_user_detail(id)
    local detail_info = skynet.call(invite_user_detail_db, "lua", "findOne", {id=id})
    if not detail_info then
        detail_info = {
            -- account = user.account,
            id = id,  --
            -- nick_name = user.nick_name,
            -- belong_id = uid,

            play_total_count =0, --完成局数
            pay_money_count=0, --支付总数

            invited_date = os.time(), --邀请时间
        }
        skynet.call(invite_user_detail_db, "lua", "safe_insert", detail_info)
    end
    return detail_info
end

function CMD.approval(id, tf) -- 审核结果
    if (id and tf) then
        if tf ~= approval_type_roulette then --非抽奖类
            -- 设置自己奖励为完成
            skynet.call(invite_info_db, "lua", "update", {id=id}, {["$set"]={[tf]=base.ACTIVITY_STATUS.FINISH}}, false)
        end
    end
    return 1
end

function CMD.play(roles) --统计邀请者累计人数，自己玩的局数
    if (roles) then
        for i,v in ipairs(roles) do
            local id = v

            local user_detail = CMD.get_invite_user_detail(id)
            local belong_id = user_detail.belong_id
            local count = user_detail.play_total_count or 0 --此用户完成局数

            if count == (define.activity_maxtrix.done_count -1) then --有效完成局数
                --邀请者累计有效用户+1, 并获得相关钻石
                if (belong_id) then 
                    skynet.call(invite_info_db, "lua", "update", {id=belong_id}, {["$inc"]={invite_count=1,award_diamond=define.activity_maxtrix.invite_succ_diamond}}, false)
                end
            end
            -- 自己完成数+1
            skynet.call(invite_user_detail_db, "lua", "update", {id=id}, {["$inc"]={play_total_count=1}}, false)

            --当天的完成抽奖数统计
            roulette_calculate(id, 1) -- 完成局数索引为1

        end
    end
end

function CMD.pay(roles, fee_fen) --统计邀请者累计支付，自己的支付
    if (roles and fee_fen>0) then
        -- 支付金额
        local yuan = fee_fen // 100        
        for i,v in ipairs(roles) do
            local id = v

            local user_detail = CMD.get_invite_user_detail(id)
            local belong_id = user_detail.belong_id
            skynet.call(invite_user_detail_db, "lua", "update", {id=id}, {["$inc"]={pay_money_count=yuan}}, false)

            if (belong_id and belong_id>0) then --邀请者累计
                -- local invite_info = CMD.get_invite_info({id=belong_id})
                -- if (invite_info) then
                    skynet.call(invite_info_db, "lua", "update", {id=belong_id}, {["$inc"]={pay_total=yuan}}, false)
                -- end
            end
        end
    end
end

function CMD.consume_room_succ(roles) -- 消费房卡: 有效创建房间次数
    if (roles) then
        for i,v in ipairs(roles) do
            local id = v
            roulette_calculate(id,2) --创建有效房间索引为2
        end
    end
end

function CMD.top_win(id) --成为大赢家
    roulette_calculate(id, 3)  -- 大赢家索引为3
end

function CMD.reg_invite_user(user) --新用户,关联邀请人
     -- client invoke by unionid
    -- TOTEST TOFIX
    -- user.unionid = "sksdksf"
    if (user and user.unionid) then
        local unionid = user.unionid
        local uid = nil
        
        if unionid then
            local now = floor(skynet.time())
            local str = table.concat({define.intercommunion.sys_id,user.id, unionid, now, web_sign}, "&")
            local sign = md5.sumhexa(str)
            local result, content = skynet.call(webclient, "lua", "request", 
                define.intercommunion.query_invite_url, {gid=define.intercommunion.sys_id,id=user.id, unionid=unionid, time=now, sign=sign})
            if not result then
                -- error{code = error_code.INTERNAL_ERROR}
                skynet.error(string.format("query invite user [%d]  %s.",user.id, result))
            else
                local ret,content = pcall(cjson.decode,content)
                if ret then
                    if content.ret == "OK" then
                        if content.guid then
                            uid = tonumber(content.guid)
                        end
                    else
                        -- error{code = error_code.INTERNAL_ERROR}
                        skynet.error(string.format("query invite user [%d]  %s.",user.id, content.error))
                    end               
                else
                    skynet.error(string.format("query invite user [%d]  %s.",user.id, content))
                end
                                 
            end
        end        
        
        --TOTEST TOFIX
        --if (user.id ~= 111) then uid = 111 end

        local detail_info = {
            account = user.account,
            id = user.id,  --
            nick_name = user.nick_name,
            belong_id = uid,

            play_total_count =0, --完成局数
            pay_money_count=0, --支付总数

            invited_date = os.time(), --邀请时间
        }
        skynet.call(invite_user_detail_db, "lua", "safe_insert", detail_info)
    end
end

function CMD.wx_binding(unionid) --微信公众号绑定
    local user = skynet.call(user_db, "lua", "findOne", {unionid=unionid},{id=1})
    if (user and user.id) then
        skynet.call(invite_info_db, "lua", "update", {id=user.id},
        {["$set"]={bind_gzh=true}}, false)

        local agent = skynet.call(role_mgr, "lua", "get", user.id)
        if agent then --如果在线,通知
            skynet.call(agent, "lua", "action", "role", "bind_gzh", true, unionid)
        end
    end
    return 1
end

skynet.start(function()
    local master = skynet.queryservice("mongo_master")
    -- web_sign = skynet.getenv("web_sign")
    role_mgr = skynet.queryservice("role_mgr")

    user_db = skynet.call(master, "lua", "get", "user")
    invite_info_db = skynet.call(master, "lua", "get", "invite_info")
    invite_user_detail_db = skynet.call(master, "lua", "get", "invite_user_detail")

    base = sharedata.query("base")
    define = sharedata.query("define")
    error_code = sharedata.query("error_code")
    rand = random()

    webclient = skynet.queryservice("webclient")

	skynet.dispatch("lua", function(session, source, command, ...)
		local f = assert(CMD[command])
        if session == 0 then
            f(...)
        else
            skynet.retpack(f(...))
        end
	end)
end)
