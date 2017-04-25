.user_info {
    name 0 : string
    id 1 : integer
    sex 2 : integer
    create_time 3 : integer
}

.other_info {
    name 0 : string
    id 1 : integer
    sex 2 : integer
}

.other_all {
    other 0 : *other_info
}

.update_other {
    id 0 : integer
}

.rank_info {
    id 0 : integer
    name 1 : string
    sex 2 : integer
}

.user_all {
    user 0 : user_info
}

.info_all {
    user 0 : user_all
    start_time 1 : integer
}

.update_user {
    update 0 : user_all
}

.update_day {
}

.heart_beat {
    time 0 : integer
}

.heart_beat_response {
    time 0 : integer
    server_time 1 : integer
}

.error_code {
    code 0 : integer
}

.enter_game {
}

.logout {
    id 0 : integer
}

.chat_info {
    id 0 : integer
    name 1 : string
    sex 3 : integer
    type 5 : integer
    target 6 : integer
    text 7 : string
}

.get_role_info {
    id 0 : integer
}

.role_info {
    info 0 : user_all
}