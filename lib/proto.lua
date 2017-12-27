
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
