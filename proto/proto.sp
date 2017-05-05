.user_info {
    account 0 : string
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

.weave_card {
    op 0 : integer
    card 1 : integer
}

.chess_user {
    account 0 : string
    id 1 : integer
    sex 2 : integer
    nick_name 3 : string
    head_img 4 : string
    ip 5 : string
    index 6 : integer
    score 7 : integer
    ready 8 : boolean
    own_card 9 : *integer
    out_card 10 : integer
    weave_card 11 : *weave_card
    action 12 : integer
}

.chess_info {
    name 0 : string
    number 1 : integer
    rule 2 : string
    banker 3 : integer
    user 4 : *chess_user
    status 5 : integer
    left 6 : integer
    deal_index 7 : integer
    count 8 : integer
}

.user_all {
    user 0 : user_info
    chess 1 : chess_info
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

.add_room_card {
    num 0 : integer
}

.new_chess {
    name 0 : string
    rule 1 : string
}

.join {
    number 0 : integer
    name 1 : string
}

.out_card {
    card 0 : integer
}

.chi {
    card 0 : integer
}
