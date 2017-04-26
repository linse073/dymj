
local msg = {
    [1000] = "error_code",
    [1001] = "notify_info",
    [1002] = "logout",
    [1003] = "heart_beat",
    [1004] = "heart_beat_response",
    [1005] = "response",

    [2000] = "user_info",
    [2001] = "user_all",
    [2002] = "info_all",
    [2003] = "update_user",
    [2004] = "other_info",
    [2005] = "other_all",
    [2006] = "update_other",
    [2007] = "get_role",
    [2008] = "role_info",

    [2100] = "enter_game",
}
local name_msg = {}

for k, v in pairs(msg) do
    name_msg[v] = k
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
