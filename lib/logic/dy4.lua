local skynet = require "skynet"
local share = require "share"
local util = require "util"
local timer = require "timer"
local bson = require "bson"
local func = require "func"

local string = string
local ipairs = ipairs
local pairs = pairs
local table = table
local floor = math.floor
local os = os

local base
local error_code
local user_record_db
local record_info_db
local record_detail_db
local table_mgr
local chess_mgr
local offline_mgr
local club_mgr
local activity_mgr

local function sort_card(l, r)
    return l > r
end

local function sort_line(l, r)
    if l.line ~= r.line then
        return l.line > r.line
    end
    return l.value > r.value
    -- local lc, rc = l.card, r.card
    -- local i = 1
    -- while true do
    --     local lv, rv = lc[i] or 0, rc[i] or 0
    --     if lv == 0 and rv == 0 then
    --         return false
    --     end
    --     if lv ~= rv then
    --         return lv > rv
    --     end
    --     i = i + 1
    -- end
end

local function poker_info(c)
    if c <= base.POKER_CARD then
        local tc = c - 1
        return tc//base.POKER_VALUE+1, tc%base.POKER_VALUE+1
    else
        return 0, c
    end
end

local function poker_line(tc)
    local len = #tc.card
    if tc.value > base.POKER_CARD then
        if tc.king4 then
            tc.line = len * 2
        else
            if len >= 4 then
                tc.line = len + 3
            else
                tc.line = len
            end
        end
    else
        tc.line = len
    end
end

local function analyze(out)
    local tc = {card=out}
    local o1 = out[1]
    if o1 > base.POKER_CARD then
        tc.count = 0
        local c, mc = 0, 0
        for k, v in ipairs(out) do
            c = c + 1
            if v ~= out[k+1] then
                if c > mc then
                    mc = c
                end
                c = 0
                tc.count = tc.count + 1
            end
        end
        if mc >= base.P4_POKER then
            tc.king4 = true
        end
        if tc.count > 1 then
            tc.value = 55
        else
            local pc, pv = poker_info(o1)
            tc.value = pv
        end
    else
        local pc, pv = poker_info(o1)
        tc.value = pv
    end
    poker_line(tc)
    return tc
end

local king_1 = {53, 54, 55}
local king_2 = {54, 55}

local score_card = {
    [3] = 5,
    [8] = 10,
    [11] = 10,
}

skynet.init(function()
    base = share.base
    error_code = share.error_code
    local master = skynet.queryservice("mongo_master")
    user_record_db = skynet.call(master, "lua", "get", "user_record")
    record_info_db = skynet.call(master, "lua", "get", "record_info")
    record_detail_db = skynet.call(master, "lua", "get", "record_detail")
    table_mgr = skynet.queryservice("table_mgr")
    chess_mgr = skynet.queryservice("chess_mgr")
    offline_mgr = skynet.queryservice("offline_mgr")
    club_mgr = skynet.queryservice("club_mgr")

    activity_mgr = skynet.queryservice("activity_mgr")
end)

local function session_msg(user, chess_user, chess_info)
    local msg = {update={chess={
        info = chess_info,
        user = chess_user,
        session = user.session,
    }}}
    user.session = user.session + 1
    return "update_user", msg
end

local function send(user, chess_user, chess_info)
    if user.agent then
        local m, i = session_msg(user, chess_user, chess_info)
        skynet.call(user.agent, "lua", "notify", m, i)
    end
end

local function broadcast(chess_user, chess_info, role, ...)
    if ... then
        local exclude = {}
        for k, v in ipairs({...}) do
            exclude[v] = v
        end
        for k, v in pairs(role) do
            if not exclude[v.id] then
                send(v, chess_user, chess_info)
            end
        end
    else
        for k, v in pairs(role) do
            send(v, chess_user, chess_info)
        end
    end
end

local function play(role) --完成一牌局
    local id = {}
    for k, v in pairs(role) do
        id[k] = v.id
    end

    skynet.send(activity_mgr, "lua", "play", id)
end

local function play_winner(role, winner) --大赢家
    local id = {}
    for k, v in pairs(role) do
        id[k] = v.id
    end

    local w = id[winner]
    if (w) then --大赢家
        skynet.send(activity_mgr, "lua", "top_win", w)
    end
end

local dy4 = {}

function dy4:init(number, rule, rand, server, card, club)
    self._number = number
    self._rule = rule
    self._rand = rand
    self._server = server
    self._custom_card = card
    self._club = club
    self._banker = rand.randi(1, base.P4_FOUR)
    self._status = base.CHESS_STATUS_READY
    self._role = {}
    self._id = {}
    self._count = 0
    self._pause = false
    self._close_index = 0
    self._record = {
        info = {
            name = "dy4",
            number = number,
            rule = rule.pack,
            club = club,
        },
    }
    if club then
        local c = skynet.call(club_mgr, "lua", "get_by_id", club)
        if c then
            skynet.call(c, "lua", "add_room", {
                name = "dy4",
                number = number,
                rule = rule.pack,
                user = base.P4_FOUR,
            })
        end
    end
end

function dy4:status(id, status, addr)
    local info = self._id[id]
    if info then
        if status~=info.status or (addr and addr~=info.ip) then
            info.status = status
            if addr then
                info.ip = addr
            end
            if status == base.USER_STATUS_LOGOUT then
                info.agent = nil
            end
            local user = {index=info.index, status=status, ip=addr}
            local chess
            if self._status == base.CHESS_STATUS_DEAL and not info.deal_end then
                info.deal_end = true
                user.deal_end = true
                if self:is_all_deal() then
                    self._status = base.CHESS_STATUS_START
                    chess = {status=self._status}
                end
            end
            broadcast({user}, chess, self._role)
        end
    end
end

function dy4:destroy()
    timer.del_once_routine("close_timer")
end

local function finish()
    skynet.call(skynet.self(), "lua", "destroy")
    skynet.call(table_mgr, "lua", "free", skynet.self())
end
function dy4:finish()
    local role = self._role

    -- 大赢家
    if (self.win_idx) then
        play_winner(role, self.win_idx)
    end
    self.win_idx = nil

    self._role = {}
    self._id = {}
    for i = 1, base.P4_FOUR do
        local v = role[i]
        if v then
            skynet.call(chess_mgr, "lua", "del", v.id)
            if v.agent then
                skynet.call(v.agent, "lua", "action", "role", "leave")
            end
        end
    end
    if self._club then
        local club = skynet.call(club_mgr, "lua", "get_by_id", self._club)
        if club then
            skynet.call(club, "lua", "del_room", self._number)
        end
    end
    skynet.fork(finish)
end

function dy4:custom_card(name, card)
    if name ~= "dy4" then
        error{code = error_code.ERROR_CHESS_NAME}
    end
    self._custom_card = card
    return "response", ""
end

function dy4:pack(id, ip, agent)
    local si = self._id[id]
    if si then
        si.ip = ip
        si.status = base.USER_STATUS_ONLINE
        si.agent = agent
        local role = self._role
        broadcast({
            {index=si.index, status=si.status, ip=ip},
        }, nil, role, id)
        local status = self._status
        if status == base.CHESS_STATUS_READY then
            local chess = {
                name = "dy4",
                number = self._number,
                rule = self._rule.pack,
                banker = self._banker,
                status = status,
                count = self._count,
                pause = self._pause,
                close_index = self._close_index,
                close_time = self._close_time,
                record_id = self._record.id,
                club = self._club,
            }
            local user = {}
            for i = 1, base.P4_FOUR do
                local info = role[i]
                if info then
                    local u = {
                        account = info.account,
                        id = info.id,
                        sex = info.sex,
                        nick_name = info.nick_name,
                        head_img = info.head_img,
                        ip = info.ip,
                        index = info.index,
                        score = info.score,
                        ready = info.ready,
                        deal_end = info.deal_end,
                        top_score = info.top_score,
                        hu_count = info.hu_count,
                        status = info.status,
                        location = info.location,
                    }
                    local card_list = info.card_list
                    if card_list then
                        local own_card 
                        if #card_list > 0 then
                            own_card = {}
                            for k1, v1 in ipairs(card_list) do
                                for k2, v2 in ipairs(v1.card) do
                                    own_card[#own_card+1] = v2
                                end
                            end
                        end
                        local show_card = {
                            own_card = own_card,
                            score = info.last_score,
                            grab_score = info.grab_score,
                            line_score = info.line_score,
                            last_index = info.last_index,
                            alone_award = info.alone_award,
                        }
                        u.show_card = show_card
                    end
                    user[#user+1] = u
                end
            end
            return {info=chess, user=user, start_session=si.session}
        elseif status == base.CHESS_STATUS_START or status == base.CHESS_STATUS_DEAL then
            local chess = {
                name = "dy4",
                number = self._number,
                rule = self._rule.pack,
                banker = self._banker,
                status = status,
                count = self._count,
                pause = self._pause,
                close_index = self._close_index,
                close_time = self._close_time,
                can_out = self._can_out,
                record_id = self._record.id,
                score = self._score,
                out_index = self._out_index,
                club = self._club,
            }
            local user = {}
            for i = 1, base.P4_FOUR do
                local info = role[i]
                local u = {
                    account = info.account,
                    id = info.id,
                    sex = info.sex,
                    nick_name = info.nick_name,
                    head_img = info.head_img,
                    ip = info.ip,
                    index = info.index,
                    score = info.score,
                    ready = info.ready,
                    deal_end = info.deal_end,
                    agree = info.agree,
                    top_score = info.top_score,
                    hu_count = info.hu_count,
                    status = info.status,
                    location = info.location,
                    grab_score = info.grab_score,
                    line_score = info.line_score,
                    pass = info.pass,
                    out_card = info.out_card,
                    last_index = info.last_index,
                }
                if info.id == id then
                    local own_card = {}
                    for k1, v1 in ipairs(info.card_list) do
                        for k2, v2 in ipairs(v1.card) do
                            own_card[#own_card+1] = v2
                        end
                    end
                    u.own_card = own_card
                end
                user[#user+1] = u
            end
            return {info=chess, user=user, start_session=si.session}
        end
    end
end

function dy4:enter(info, agent, index, location)
    local role = self._role
    assert(not role[index], string.format("Seat %d already has role.", index))
    info.agent = agent
    info.index = index
    info.location = location
    info.score = 0
    info.ready = false
    info.deal_end = false
    info.hu_count = 0
    info.top_score = 0
    info.session = 1
    info.status = base.USER_STATUS_ONLINE
    role[index] = info
    self._id[info.id] = info
    skynet.call(chess_mgr, "lua", "add", info.id, skynet.self())
    if self._club then
        local club = skynet.call(club_mgr, "lua", "get_by_id", self._club)
        if club then
            skynet.call(club, "lua", "enter_room", self._number, {
                id = info.id,
                name = info.nick_name or info.account,
                head_img = info.head_img,
                sex = info.sex,
            })
        end
    end
    local user = {}
    for i = 1, base.P4_FOUR do
        user[#user+1] = role[i] -- role[i] can be nil
    end
    local chess = {
        name = "dy4",
        number = self._number,
        rule = self._rule.pack,
        banker = self._banker,
        status = self._status,
        count = self._count,
        pause = self._pause,
        close_index = self._close_index,
        club = self._club,
    }
    return "update_user", {update={chess={
        info = chess,
        user = user,
        start_session = info.session,
    }}}
end

function dy4:join(info, room_card, agent, location)
    -- if self._status ~= base.CHESS_STATUS_READY then
    --     error{code = error_code.ERROR_OPERATION}
    -- end
    local rule = self._rule
    if self._club then
        local club = skynet.call(club_mgr, "lua", "get_by_id", self._club)
        if club then
            local cr = skynet.call(club, "lua", "check_role_day_card", info.id)
            if cr == nil then
                error{code = error_code.NOT_IN_CLUB}
            end
            if not cr then
                error{code = error_code.CLUB_DAY_CARD_LIMIT}
            end
        end
    else
        if rule.aa_pay and room_card < rule.single_card then
            error{code = error_code.ROOM_CARD_LIMIT}
        end
    end
    local role = self._role
    if rule.ip then
        for i = 1, base.P4_FOUR do
            local r = role[i]
            if r and r.ip == info.ip then
                error{code = error_code.IP_LIMIT}
            end
        end
    end
    local index
    for i = 1, base.P4_FOUR do
        if not role[i] then
            index = i
            break
        end
    end
    if not index then
        error{code = error_code.CHESS_ROLE_FULL}
    end
    local i = self._id[info.id]
    if i then
        error{code = error_code.ALREAD_IN_CHESS}
    end
    local rmsg, rinfo = self:enter(info, agent, index, location)
    broadcast({info}, nil, role, info.id)
    return rmsg, rinfo
end

function dy4:leave(id, msg)
    local info = self._id[id]
    if not info then
        error{code = error_code.NOT_IN_CHESS}
    end
    local role = self._role
    local index = info.index
    if self._count > 0 or self._status == base.CHESS_STATUS_START
        or self._status == base.CHESS_STATUS_DEAL then
        if self._close_index > 0 then
            error{code = error_code.IN_CLOSE_PROCESS}
        end
        self._pause = true
        local now = floor(skynet.time())
        self._close_time = now
        self._close_index = index
        info.agree = true
        local cu = {
            {index=index, agree=true},
        }
        local ci = {pause=self._pause, close_index=index, close_time=now}
        broadcast(cu, ci, role, id)
        timer.add_once_routine("close_timer", function()
            self._status = base.CHESS_STATUS_EXIT
            self._pause = false
            self._close_index = 0
            broadcast(nil, {
                status = self._status, 
                pause = self._pause,
                close_index = self._close_index,
            }, role)
            self:finish()
        end, 180)
        return session_msg(info, cu, ci)
    elseif index == 1 then
        local cu = {
            {index=index, action=base.MJ_OP_LEAVE},
        }
        broadcast(cu, nil, role, id)
        self:finish()
        return session_msg(info, cu)
    else
        self._id[id] = nil
        role[index] = nil
        skynet.call(chess_mgr, "lua", "del", id)
        if info.agent then
            skynet.call(info.agent, "lua", "action", "role", "leave")
        end
        if self._club then
            local club = skynet.call(club_mgr, "lua", "get_by_id", self._club)
            if club then
                skynet.call(club, "lua", "leave_room", self._number, id)
            end
        end
        local cu = {
            {index=index, action=base.MJ_OP_LEAVE},
        }
        broadcast(cu, nil, role)
        return session_msg(info, cu)
    end
end

function dy4:chat_info(id, msg)
    local info = self._id[id]
    if not info then
        error{code = error_code.NOT_IN_CHESS}
    end
    local cu = {
        {index=info.index, chat_text=msg.text, chat_audio=msg.audio}
    }
    broadcast(cu, nil, self._role, id)
    return session_msg(info, cu)
end

function dy4:location_info(id, msg)
    local info = self._id[id]
    if not info then
        error{code = error_code.NOT_IN_CHESS}
    end
    info.location = msg.location
    local cu = {
        {index=info.index, location=msg.location}
    }
    broadcast(cu, nil, self._role, id)
    return session_msg(info, cu)
end

function dy4:is_all_agree()
    local count = 0
    for k, v in ipairs(self._role) do
        if v.agree then
            count = count + 1
        end
    end
    return count >= 3
end

function dy4:reply(id, msg)
    local info = self._id[id]
    if not info then
        error{code = error_code.NOT_IN_CHESS}
    end
    if self._close_index == 0 then
        error{code = error_code.NOT_IN_CLOSE}
    end
    if info.agree ~= nil then
        error{code = error_code.ALREADY_REPLY}
    end
    info.agree = msg.agree
    local chess = {}
    if info.agree then
        if self:is_all_agree() then
            self._status = base.CHESS_STATUS_EXIT
            chess.status = self._status
            self._pause = false
        end
    else
        self._pause = false
    end
    local cu = {
        {index=info.index, agree=info.agree},
    }
    if not self._pause then
        self._close_index = 0
        chess.pause = self._pause
        chess.close_index = self._close_index
        timer.del_once_routine("close_timer")
        for k, v in ipairs(self._role) do
            v.agree = nil
        end
    end
    broadcast(cu, chess, self._role, id)
    if self._status == base.CHESS_STATUS_EXIT then
        self:finish()
    end
    return session_msg(info, cu, chess)
end

function dy4:is_all_ready()
    local role = self._role
    for i = 1, base.P4_FOUR do
        local v = role[i]
        if not v or not v.ready then
            return false
        end
    end
    return true
end

function dy4:op_check(id, status)
    if self._status ~= status then
        error{code = error_code.ERROR_OPERATION}
    end
    local info = self._id[id]
    if not info then
        error{code = error_code.NOT_IN_CHESS}
    end
    return info
end

function dy4:ready(id, msg)
    local info = self:op_check(id, base.CHESS_STATUS_READY)
    if info.ready then
        error{code = error_code.ALREADY_READY}
    end
    info.ready = true
    local index = info.index
    local user = {index=index, ready=true}
    local chess
    if self:is_all_ready() then
        self:start()
        -- self
        local now = floor(skynet.time())
        chess = {
            status = self._status,
            rand = now,
            can_out = self._can_out,
        }
        self._detail.info.rand = now
        local own_card = {}
        for k1, v1 in ipairs(info.card_list) do
            for k2, v2 in ipairs(v1.card) do
                own_card[#own_card+1] = v2
            end
        end
        user.own_card = own_card
        -- other
        for k, v in ipairs(self._role) do
            if v.id ~= id then
                local oc = {}
                for k1, v1 in ipairs(v.card_list) do
                    for k2, v2 in ipairs(v1.card) do
                        oc[#oc+1] = v2
                    end
                end
                send(v, {
                    {index=index, ready=true}, 
                    {index=k, own_card=oc},
                }, chess)
            end
        end
    else
        broadcast({user}, chess, self._role, id)
    end
    return session_msg(info, {user}, chess)
end

function dy4:is_all_deal()
    local role = self._role
    for i = 1, base.P4_FOUR do
        local v = role[i]
        if not v.deal_end then
            return false
        end
    end
    return true
end

function dy4:deal_end(id, msg)
    local info = self:op_check(id, base.CHESS_STATUS_DEAL)
    if info.deal_end then
        error{code = error_code.ALREADY_DEAL_END}
    end
    info.deal_end = true
    local user = {index=info.index, deal_end=true}
    local chess
    if self:is_all_deal() then
        self._status = base.CHESS_STATUS_START
        chess = {status=self._status}
    end
    broadcast({user}, chess, self._role, id)
    return session_msg(info, {user}, chess)
end

function dy4:p4_out(id, msg)
    local info = self:op_check(id, base.CHESS_STATUS_START)
    local index = info.index
    if index ~= self._can_out then
        error{code = error_code.ERROR_OUT_INDEX}
    end
    local out_card = msg.out_card
    if not out_card or #out_card == 0 then
        error{code = error_code.ERROR_ARGS}
    end
    table.sort(out_card, sort_card)
    local tc = analyze(out_card)
    if self._out_card then
        if tc.line < 4 and tc.line ~= self._out_card.line then
            error{code = error_code.ILLEGAL_POKER}
        end
        if not sort_line(tc, self._out_card) then
            error{code = error_code.SMALL_POKER}
        end
    end
    local type_card = info.type_card
    local self_card = type_card[tc.value]
    if not self_card then
        error{code = error_code.INVALID_CARD}
    end
    local self_len = #self_card.card
    local out_len = #out_card
    local card_list = info.card_list
    if self_len == out_len then
        for k, v in ipairs(self_card.card) do
            if v ~= out_card[k] then
                error{code = error_code.INVALID_CARD}
            end
        end
    else
        if not self._rule.split then
            error{code = error_code.CAN_NOT_SPLIT_POKER}
        end
        if card_list[1].line >= 4 then
            error{code = error_code.SPLIT_POKER_LIMIT}
        end
        local diff = self_len - out_len
        for k, v in ipairs(out_card) do
            if v ~= self_card.card[k+diff] then
                error{code = error_code.INVALID_CARD}
            end
        end
    end
    self._out_index = index
    self._out_card = tc
    info.out_card = out_card
    info.pass = false
    if self_len == out_len then
        table.remove(card_list, self_card.index)
        for i = self_card.index, #card_list do
            card_list[i].index = i
        end
        if tc.value > base.POKER_CARD then
            for k, v in ipairs(king_1) do
                if type_card[v] == self_card then
                    type_card[v] = nil
                end
            end
        else
            type_card[tc.value] = nil
        end
    else
        for i = self_len-out_len+1, self_len do
            self_card.card[i] = nil
        end
        poker_line(self_card)
        local change_index = #card_list
        for i = self_card.index, #card_list-1 do
            local nc = card_list[i+1]
            if sort_line(self_card, nc) then
                change_index = i
                break
            else
                card_list[i] = nc
                nc.index = i
            end
        end
        card_list[change_index] = self_card
        self_card.index = change_index
    end
    local record_action = self._detail.action
    record_action[#record_action+1] = {
        index = index,
        card = out_card,
    }
    local sc = score_card[tc.value]
    if sc then
        self._score = self._score + out_len * sc
    end
    local user = {index=index, out_card=out_card}
    local all_user = {user}
    local role = self._role
    if tc.line >= 7 then
        local line_score = (tc.line - 6) * 30
        if info.alone_award then
            line_score = line_score * 2
        end
        for k, v in ipairs(role) do
            if k ~= index then
                v.line_score = v.line_score - line_score
                all_user[#all_user+1] = {index=k, line_score=v.line_score}
            end
        end
        info.line_score = info.line_score + line_score * 3
        user.line_score = info.line_score
    end
    if #card_list == 0 then
        info.last_index = self._none_index
        user.last_index = info.last_index
        self._none_index = self._none_index + 1
        if self._none_index == base.P4_FOUR then
            return self:settle(info, all_user)
        end
    end
    local next_out = index
    for i = 1, base.P4_FOUR-1 do
        local ni = (index+i-1)%base.P4_FOUR+1
        local r = role[ni]
        if not r.last_index then
            local rc = r.card_list
            local cl = rc[1]
            if sort_line(cl, tc) then
                if cl.line < 4 then
                    if cl.line == tc.line then
                        next_out = ni
                        break
                    else
                        if self._rule.split then
                            for k, v in ipairs(rc) do
                                if v.line >= tc.line then
                                    if v.value > tc.value then
                                        next_out = ni
                                        break
                                    end
                                else
                                    break
                                end
                            end
                            if next_out ~= index then
                                break
                            end
                        end
                    end
                else
                    next_out = ni
                    break
                end
            end
            r.pass = true
            r.out_card = nil
            all_user[#all_user+1] = {index=r.index, pass=r.pass}
        end
    end
    local chess = {}
    if next_out == index then
        if info.last_index then
            for i = 1, base.P4_FOUR-1 do
                local ni = (index+i-1)%base.P4_FOUR+1
                local r = role[ni]
                if not r.last_index then
                    next_out = ni
                    break
                end
            end
        end
        if self._score > 0 then
            info.grab_score = info.grab_score + self._score
            all_user[#all_user+1] = {index=index, grab_score=info.grab_score}
            self._score = 0
        end
        chess.score = self._score
        for k, v in ipairs(role) do
            v.pass = false
            v.out_card = nil
        end
        self._out_card = nil
        self._out_index = nil
    end
    self._can_out = next_out
    chess.can_out = next_out
    broadcast(all_user, chess, role, id)
    return session_msg(info, all_user, chess)
end

function dy4:consume_card()
    local rule = self._rule
    if self._club then
        local club = skynet.call(club_mgr, "lua", "get_by_id", self._club)
        if club then
            skynet.call(club, "lua", "consume_card", self._number, rule.total_card, rule.single_card)
        end
    else
        if rule.aa_pay then
            local count = -rule.single_card
            for k, v in ipairs(self._role) do
                skynet.call(offline_mgr, "lua", "add", v.id, "role", "add_room_card", count)
            end
        else
            local id = self._role[1].id
            local count = -rule.total_card
            skynet.call(offline_mgr, "lua", "add", id, "role", "add_room_card", count)
        end
    end

    skynet.send(activity_mgr, "lua", "consume_room_succ", {self._role[1].id,}) --有效创建房间
end

function dy4:settle(info, all_user)
    local id = info.id
    local index = info.index
    if self._score > 0 then
        info.grab_score = info.grab_score + self._score
        all_user[#all_user+1] = {index=index, grab_score=info.grab_score}
        self._score = 0
    end
    self._count = self._count + 1
    if self._count == self._rule.total_count then
        self._status = base.CHESS_STATUS_FINISH
    else
        self._status = base.CHESS_STATUS_READY
    end
    if self._count == 1 then
        self:consume_card()
    end
    local role = self._role
    local detail = self._detail
    local now = floor(skynet.time())
    detail.id = skynet.call(self._server, "lua", "gen_record_detail")
    local show_card = {}
    local record_detail = {
        id = detail.id,
        time = now,
        show_card = show_card,
        banker = self._banker,
    }
    local tail_score = 0
    local rank = {}
    for k, v in ipairs(role) do
        for k1, v1 in ipairs(v.card_list) do
            local score = score_card[v1.value]
            if score then
                tail_score = tail_score + #v1.card * score
            end
        end
        if not v.last_index then
            v.last_index = self._none_index
        end
        rank[v.last_index] = v
        v.last_score = v.grab_score + v.line_score - 100
        if v.last_score%10 == 5 then
            v.last_score = v.last_score - 5
            tail_score = tail_score + 5
        end
    end
    local r1 = rank[1]
    r1.last_score = r1.last_score + tail_score + 30
    local r4 = rank[4]
    r4.last_score = r4.last_score - 30
    local top_score, top_role
    for k, v in ipairs(role) do
        v.ready = false
        v.deal_end = false
        local rc = v.score + v.last_score
        v.score = rc
        if not top_score or rc > top_score then
            top_score = rc
            top_role = {k}
        elseif rc == top_score then
            top_role[#top_role+1] = k
        end
        local card_list = v.card_list
        local own_card 
        if #card_list > 0 then
            own_card = {}
            for k1, v1 in ipairs(card_list) do
                for k2, v2 in ipairs(v1.card) do
                    own_card[#own_card+1] = v2
                end
            end
        end
        local sc = {
            own_card = own_card,
            score = v.last_score,
            grab_score = v.grab_score,
            line_score = v.line_score,
            last_index = v.last_index,
            alone_award = v.alone_award,
        }
        local u = {
            index = k,
            ready = v.ready,
            deal_end = v.deal_end,
            score = rc,
            show_card = sc,
        }
        if v.last_score > 0 then
            v.hu_count = v.hu_count + 1
            u.hu_count = v.hu_count
        end
        detail.user[k].show_card = sc
        show_card[k] = sc
        if v.last_score > v.top_score then
            v.top_score = v.last_score
            u.top_score = v.last_score
        end
        all_user[#all_user+1] = u
    end
    local winner = 0
    if top_score > 0 then
        local top_len = #top_role
        if top_len == 1 then
            winner = top_role[1]
        else
            winner = top_role[self._rand.randi(1, top_len)]
        end
    end
    local expire = bson.date(os.time())
    detail.time = now
    detail.expire = expire
    skynet.call(record_detail_db, "lua", "safe_insert", detail)
    local sr = self._record
    sr.expire = expire
    sr.time = now
    local record_id
    if sr.id then
        skynet.call(record_info_db, "lua", "update", {id=sr.id}, {
            ["$push"] = {record=record_detail},
            ["$set"] = {expire=expire, time=now, winner=winner},
        }, true)
    else
        record_id = skynet.call(self._server, "lua", "gen_record")
        sr.id = record_id
        local record_user = {}
        for k, v in ipairs(role) do
            record_user[k] = {
                account = v.account,
                id = v.id,
                sex = v.sex,
                nick_name = v.nick_name,
                head_img = v.head_img,
                ip = v.ip,
                index = v.index,
            }
            if self._club then
                skynet.call(user_record_db, "lua", "update", {id=v.id}, {["$push"]={club_record=record_id}}, true)
            else
                skynet.call(user_record_db, "lua", "update", {id=v.id}, {["$push"]={record=record_id}}, true)
            end
        end
        sr.user = record_user
        sr.clubid = self._club
        sr.read = false
        sr.record = {record_detail}
        sr.winner = winner
        skynet.call(record_info_db, "lua", "safe_insert", sr)
    end
    self._old_banker = self._banker
    self._banker = r1.index
    local ci = {
        status = self._status, 
        count = self._count, 
        banker = self._banker, 
        record_id = record_id,
        win = winner,
        score = self._score,
    }

    self.win_idx = winner
    
    play(role) -- 完成一牌局

    broadcast(all_user, ci, role, id)
    if self._status == base.CHESS_STATUS_FINISH then
        self:finish()
    end
    return session_msg(info, all_user, ci)
end

function dy4:start()
    local card
    if self._custom_card then
        card = util.clone(self._custom_card)
    else
        card = {}
        for i = 1, base.P4_POKER do
            for j = 1, base.POKER_CARD do
                card[#card+1] = j
            end
        end
        local king
        if self._rule.extra_king then
            king = king_1
        else
            king = king_2
        end
        for i = 1, base.P4_POKER do
            for k, v in ipairs(king) do
                card[#card+1] = v
            end
        end
        util.shuffle(card, self._rand)
    end
    self._card = card
    self._status = base.CHESS_STATUS_DEAL
    self._can_out = self._banker
    self._score = 0
    self._out_index = nil
    self._out_card = nil
    self._none_index = 1
    local left = #card
    local role_card = left // base.P4_FOUR
    local role = self._role
    local record_user = {}
    local start_index = self._rand.randi(1, base.P4_FOUR)
    local line7 = {}
    for j = 1, base.P4_FOUR do
        local index = (start_index+j-2)%base.P4_FOUR+1
        local v = role[index]
        v.out_card = nil
        v.pass = false
        v.grab_score = 0
        v.line_score = 0
        v.alone_award = false
        v.last_index = nil
        local type_card = {}
        local deal_card = {}
        for i = 1, role_card do
            local c = card[left+1-((i-1)*base.P4_FOUR+j)]
            deal_card[#deal_card+1] = c
            local pc, pv = poker_info(c)
            local tc = type_card[pv]
            if tc then
                tc.card[#tc.card+1] = c
            else
                tc = {card={c}, value=pv}
                type_card[pv] = tc
            end
        end
        local king = {
            card = {},
            king4 = false,
            count = 0,
            value = 55,
        }
        for k1, v1 in ipairs(king_1) do
            local tc = type_card[v1]
            if tc then
                for k2, v2 in ipairs(tc.card) do
                    king.card[#king.card+1] = v2
                end
                if #tc.card >= base.P4_POKER then
                    tc.king4 = true
                    king.king4 = true
                end
                king.count = king.count + 1
            end
        end
        if king.count > 1 and #king.card >= base.P4_POKER then
            for k1, v1 in ipairs(king_1) do
                type_card[v1] = king
            end
        end
        local temp_card = {}
        local card_list = {}
        for k1, v1 in pairs(type_card) do
            if not temp_card[v1] then
                temp_card[v1] = true
                card_list[#card_list+1] = v1
                table.sort(v1.card, sort_card)
                poker_line(v1)
            end
        end
        table.sort(card_list, sort_line)
        if card_list[1].line >= 7 then
            line7[#line7+1] = index
        end
        for k1, v1 in ipairs(card_list) do
            v1.index = k1
        end
        v.type_card = type_card
        v.card_list = card_list
        record_user[index] = {
            account = v.account,
            id = v.id,
            sex = v.sex,
            nick_name = v.nick_name,
            head_img = v.head_img,
            ip = v.ip,
            index = index,
            score = v.score,
            own_card = deal_card,
        }
    end
    if #line7 == 1 and self._rule.alone_award then
        role[line7[1]].alone_award = true
    end
    self._detail = {
        info = {
            name = "dy4",
            number = self._number,
            rule = self._rule.pack,
            banker = self._banker,
            count = self._count,
            club = self._club,
        },
        user = record_user,
        action = {},
    }
end

return {__index=dy4}
