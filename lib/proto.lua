
local pairs = pairs
local ipairs = ipairs

local type_msg = {
    [1000] = {
        "error_code",
        "notify_info",
        "logout",
        "heart_beat",
        "heart_beat_response",
        "response",
    },

    [2000] = {
        "user_info",
        "user_all",
        "info_all",
        "update_user",
        "other_all",
        "get_role",
        "role_info",
        "chess_info",
        "chess_user",
        "chess_all",
        "chess_record",
        "record_info",
        "record_all",
        "invite_query",
        "invite_share",
        "invite_info",
        "reward_award",
        "invite_money_query",
        "reward_money",
        "roulette_query",
        "roulette_reward",
        "act_pay",
        "update_gzh",
    },

    [2100] = {
        "enter_game",
        "get_offline",
    },

    [2200] = {
        "add_room_card",
        "dymj_card",
        "jdmj_card",
        "test_update_day",
        "jd13_card",
        "dy13_card",
        "jhbj_card",
        "dy4_card",
    },

    [2300] = {
        "new_chess",
        "join",
        "get_record",
        "review_record",
        "iap",
        "update_day",
        "share",
        "invite_code",
        "charge",
        "charge_ret",
    },

    [2400] = {
        "club_info",
        "club_member",
        "club_member_list",
        "update_club_member",
        "club_apply",
        "club_apply_list",
        "update_club_apply",
        "room_user",
        "room_info",
        "room_list",
        "club_all",
        "query_club",
        "found_club",
        "apply_club",
        "accept_club_apply",
        "refuse_club_apply",
        "query_club_apply",
        "query_club_member",
        "club_top",
        "club_top_ret",
        "remove_club_member",
        "charge_club",
        "config_club",
        "promote_club_member",
        "demote_club_member",
        "query_club_room",
        "config_quick_start",
        "accept_all_club_apply",
        "refuse_all_club_apply",
        "leave_club",
        "query_club_all",
        "get_club_user_record",
        "club_user_record",
        "get_club_record",
        "club_record",
        "read_club_record",
        "check_agent",
        "check_agent_ret",
    },

    [20000] = {
        "ready",
        "deal_end",
        "out_card",
        "hu",
        "chi",
        "peng",
        "gang",
        "hide_gang",
        "pass",
        "conclude",
        "leave",
        "reply",
        "chat_info",
        "thirteen_out",
        "p13_call",
        "bj_out",
        "give_up",
        "location_info",
        "p4_out",
    },
}

local msg = {}
local name_msg = {}

for k, v in pairs(type_msg) do
    for k1, v1 in ipairs(v) do
        local i = k + k1
        msg[i] = v1
        name_msg[v1] = i
    end
end

local proto = {
    msg = msg,
    name_msg = name_msg,
}

function proto.get_id(name)
    return name_msg[name]
end

function proto.get_name(id)
    return msg[id]
end

return proto
