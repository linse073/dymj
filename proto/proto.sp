.user_info {
    account 0 : string
    id 1 : integer
    sex 2 : integer
    create_time 3 : integer
    room_card 4 : integer
    nick_name 5 : string
    head_img 6 : string
    ip 7 : string
    day_card 8 : boolean
    last_login_time 9 : integer
}

.other_all {
    other 0 : *user_info
}

.weave_card {
    op 0 : integer
    card 1 : integer
    index 2 : integer
    out_card 3 : integer
    old 4 : integer
}

.show_card {
    own_card 0 : *integer
    score 1 : integer
    last_deal 2 : integer
    hu 3 : integer
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
    out_card 10 : *integer
    weave_card 11 : *weave_card
    last_deal 12 : integer
    out_index 13 : integer
    action 14 : integer
    agree 15 : boolean
    show_card 16 : show_card
    own_count 17 : integer
    out_magic 18 : boolean
    chi_count 19 : *integer
    top_score 20 : integer
    hu_count 21 : integer
    status 22 : integer
    chat_text 23 : string
    chat_audio 24 : binary
    deal_end 25 : boolean
    pass 26 : boolean
}

.chess_info {
    name 0 : string
    number 1 : integer
    rule 2 : string
    banker 3 : integer
    status 4 : integer
    left 5 : integer
    deal_index 6 : integer
    count 7 : integer
    pause 8 : boolean
    rand 9 : integer
    out_card 10 : integer
    out_index 11 : integer
    old_banker 12 : integer
    close_index 13 : integer
    close_time 14 : integer
    record_id 15 : integer
    pass_status 16 : integer
    can_out 17 : integer
}

.chess_all {
    info 0 : chess_info
    user 1 : *chess_user
    start_session 2 : integer
    session 3 : integer
}

.record_info {
    .chess_action {
        index 0 : integer
        op 1 : integer
        card 2 : integer
        out_index 3 : integer
        deal_card 4 : integer
    }

    id 0 : integer
    time 1 : integer
    info 2 : chess_info
    user 3 : *chess_user
    aciton 4 : *chess_action
    score 5 : *integer
}

.chess_record {
    .record_detail {
        id 0 : integer
        time 1 : integer
        score 2 : *integer
    }

    id 0 : integer
    time 1 : integer
    info 2 : chess_info
    user 3 : *chess_user
    record 4 : *record_detail
}

.record_all {
    record 0 : *chess_record
}

.user_all {
    user 0 : user_info
    chess 1 : chess_all
}

.info_all {
    user 0 : user_all
    start_time 1 : integer
}

.update_user {
    update 0 : user_all
    iap_index 1 : integer
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
    index 1 : integer
}

.chi {
    card 0 : integer
}

.hide_gang {
    card 0 : integer
}

.reply {
    agree 0 : boolean
}

.dymj_card {
    card 0 : *integer
}

.enter_game {
    number 0 : integer
    name 1 : string
}

.review_record {
    id 0 : integer
}

.chat_info {
    text 0 : string
    audio 1 : binary
}

.iap {
    index 0 : integer
    receipt 1 : string
    sandbox 2 : boolean
}
