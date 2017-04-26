.user_info {
    account 0 : sting
    id 1 : integer
    sex 2 : integer
    create_time 3 : integer
    room_card 4 : integer
    nick_name 5 : string
    head_img 6 : string
}

.other_info {
    account 0 : string
    id 1 : integer
    sex 2 : integer
    nick_name 3 : string
    head_img 4 : string
    ip 5 : string
}

.other_all {
    other 0 : *other_info
}

.update_other {
    id 0 : integer
}

.brief_info {
    account 0 : string
    id 1 : integer
    sex 2 : integer
    nick_name 3 : string
    head_img 4 : string
    ip 5 : string
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

.logout {
    id 0 : integer
}

.get_role {
    id 0 : integer
}

.role_info {
    info 0 : user_all
}
